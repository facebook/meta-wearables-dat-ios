import Foundation
import AVFoundation
import Speech

final class AudioWsClient: NSObject {
    private let url: URL
    private let sessionId: String?
    private var wsTask: URLSessionWebSocketTask?
    private var session: URLSession!
    
    // Connection state
    enum ConnectionState: String {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }
    
    private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            log("🔄 Connection state changed: \(oldValue.rawValue) → \(connectionState.rawValue)")
        }
    }
    
    // Reconnection settings
    private var shouldReconnect = true
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var reconnectWorkItem: DispatchWorkItem?
    
    // Audio capture
    private let engine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { engine.inputNode }

    // Audio playback
    private let player = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!
    
    // Bookmark notification playback (through same AVAudioEngine for same output device)
    private let notificationPlayer = AVAudioPlayerNode()
    private var notificationBuffer: AVAudioPCMBuffer?

    // Speech recognition (wake/stop phrases)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRealtimeAIOn = false
    private var lastNormalizedTranscript = ""
    private var recentWords: [String] = []
    private let wakePhrases = ["hey luma", "hey lu na","hey luna"]
    private let stopPhrase = "thank you"
    private let highlightPhrases = ["highlight", "high light", "high five"]
    private let maxRecentWords = 50

    init(wsURL: URL, sessionId: String? = nil) {
        self.url = wsURL
        self.sessionId = sessionId

        super.init()
        
        // Configure audio session for Bluetooth FIRST (before getting formats)
        configureAudioSession()
        
        // Create session with delegate for connection events
        self.session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: OperationQueue()
        )

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        
        // Attach notification player to the SAME engine for guaranteed same output device
        engine.attach(notificationPlayer)
        loadBookmarkNotificationBuffer()

        log("📱 AudioWsClient initialized with URL: \(wsURL.absoluteString)")
    }
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // Use playAndRecord for both input and output
            // allowBluetoothHFP: enables HFP (Hands-Free Profile) for headsets
            // allowBluetoothA2DP: enables A2DP (Advanced Audio Distribution) for high-quality audio
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP,
                    .defaultToSpeaker  // Fallback to speaker if no Bluetooth
                ]
            )
            
            try audioSession.setActive(true)
            
            // Log current audio route
            logCurrentAudioRoute()
            
            // Listen for route changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
            
        } catch {
            logError("Failed to configure audio session", error: error)
        }
    }
    
    private func logCurrentAudioRoute() {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        log("🎧 Audio route:")
        log("   Inputs: \(currentRoute.inputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")
        log("   Outputs: \(currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        log("🔀 Audio route changed: \(describeRouteChangeReason(reason))")
        logCurrentAudioRoute()
        
        // If we lost our output, try to reconfigure
        if reason == .oldDeviceUnavailable {
            log("⚠️ Previous audio device unavailable, reconfiguring...")
            configureAudioSession()
        }
    }
    
    private func describeRouteChangeReason(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: return "Unknown"
        case .newDeviceAvailable: return "New device available"
        case .oldDeviceUnavailable: return "Old device unavailable"
        case .categoryChange: return "Category change"
        case .override: return "Override"
        case .wakeFromSleep: return "Wake from sleep"
        case .noSuitableRouteForCategory: return "No suitable route"
        case .routeConfigurationChange: return "Route configuration change"
        @unknown default: return "Unknown (\(reason.rawValue))"
        }
    }

    func start() {
        log("▶️ Starting AudioWsClient...")
        shouldReconnect = true
        reconnectAttempts = 0
        requestSpeechAuthorizationAndStart()
        connectWebSocket()
        startAudioCapture()
        startAudioPlayback()
    }

    func stop() {
        log("⏹️ Stopping AudioWsClient...")
        shouldReconnect = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        connectionState = .disconnected
        
        // Remove the input tap before stopping
        inputNode.removeTap(onBus: 0)
        
        engine.stop()
        player.stop()
        notificationPlayer.stop()

        stopSpeechRecognition(clearState: true)
        isRealtimeAIOn = false
        
        // Remove route change observer
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        
        log("✅ AudioWsClient stopped")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Logging
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [AudioWsClient] \(message)")
    }
    
    private func logError(_ message: String, error: Error?) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var fullMessage = "[\(timestamp)] [AudioWsClient] ❌ \(message)"
        
        if let error = error {
            fullMessage += "\n  Error: \(error.localizedDescription)"
            
            // Extract more details from URLError
            if let urlError = error as? URLError {
                fullMessage += "\n  URLError Code: \(urlError.code.rawValue) - \(describeURLErrorCode(urlError.code))"
                if let failingURL = urlError.failingURL {
                    fullMessage += "\n  Failing URL: \(failingURL)"
                }
                if let underlying = urlError.userInfo[NSUnderlyingErrorKey] as? Error {
                    fullMessage += "\n  Underlying: \(underlying.localizedDescription)"
                }
            }
            
            // Extract NSError details
            let nsError = error as NSError
            fullMessage += "\n  Domain: \(nsError.domain), Code: \(nsError.code)"
            if !nsError.userInfo.isEmpty {
                fullMessage += "\n  UserInfo: \(nsError.userInfo)"
            }
        }
        
        print(fullMessage)
    }
    
    private func describeURLErrorCode(_ code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet: return "Not connected to internet"
        case .networkConnectionLost: return "Network connection lost"
        case .timedOut: return "Connection timed out"
        case .cannotFindHost: return "Cannot find host"
        case .cannotConnectToHost: return "Cannot connect to host"
        case .dnsLookupFailed: return "DNS lookup failed"
        case .secureConnectionFailed: return "Secure connection failed"
        case .serverCertificateUntrusted: return "Server certificate untrusted"
        case .badServerResponse: return "Bad server response"
        case .cancelled: return "Connection cancelled"
        default: return "Unknown error"
        }
    }

    // MARK: - WebSocket

    private func connectWebSocket() {
        guard connectionState != .connected else {
            log("⚠️ Already connected, skipping connection attempt")
            return
        }
        
        connectionState = reconnectAttempts > 0 ? .reconnecting : .connecting
        log("🔌 Connecting to WebSocket... (attempt \(reconnectAttempts + 1)/\(maxReconnectAttempts + 1))")
        
        wsTask = session.webSocketTask(with: url)
        wsTask?.resume()
        
        // Start receiving messages
        receiveLoop()
        
        // Mark as connected (actual confirmation comes from delegate)
        connectionState = .connected
        reconnectAttempts = 0
        log("✅ WebSocket connection established")
        
        // Send start_session message with session_id
        sendStartSessionMessage()
    }
    
    private struct StartSessionMessage: Codable {
        let type: String
        let session_id: String
    }
    
    private func sendStartSessionMessage() {
        guard let sessionId = sessionId else {
            log("⚠️ No session_id provided, skipping start_session message")
            return
        }
        
        let startMessage = StartSessionMessage(
            type: "start_session",
            session_id: sessionId
        )
        
        do {
            let data = try JSONEncoder().encode(startMessage)
            
            guard let jsonString = String(data: data, encoding: .utf8) else {
                logError("Failed to convert start_session data to string", error: nil)
                return
            }
            
            print("")
            print("📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨")
            print("📨 SENDING START_SESSION TO WEBSOCKET")
            print("📨")
            print("📨 Frame Type: TEXT FRAME (.string)")
            print("📨 WebSocket URL: \(url.absoluteString)")
            print("📨")
            print("📨 Session ID: \(sessionId)")
            print("📨 Message Type: start_session")
            print("📨")
            print("📨 Full JSON Payload:")
            print("📨 \(jsonString)")
            print("📨")
            print("📨 Payload Length: \(jsonString.count) characters")
            print("📨 Payload Bytes: \(data.count) bytes")
            print("📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨📨")
            print("")
            
            // Send as text frame
            wsTask?.send(.string(jsonString)) { [weak self] error in
                if let error = error {
                    self?.logError("Failed to send start_session message", error: error)
                } else {
                    print("✅ start_session message sent successfully via TEXT FRAME")
                }
            }
        } catch {
            logError("Failed to encode start_session message", error: error)
        }
    }
    
    private func scheduleReconnect() {
        guard shouldReconnect else {
            log("🚫 Reconnection disabled, not scheduling reconnect")
            return
        }
        
        guard reconnectAttempts < maxReconnectAttempts else {
            logError("Max reconnection attempts (\(maxReconnectAttempts)) reached, giving up", error: nil)
            connectionState = .disconnected
            return
        }
        
        reconnectAttempts += 1
        
        // Exponential backoff with jitter
        let delay = min(
            baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1)),
            maxReconnectDelay
        )
        let jitter = Double.random(in: 0...0.5) * delay
        let totalDelay = delay + jitter
        
        log("⏱️ Scheduling reconnect in \(String(format: "%.1f", totalDelay))s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
        
        reconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.connectWebSocket()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay, execute: workItem)
    }
    
    private func handleConnectionLost(error: Error?) {
        wsTask = nil
        
        logError("Connection lost", error: error)
        
        if shouldReconnect {
            scheduleReconnect()
        } else {
            connectionState = .disconnected
        }
    }

    private func sendText(_ text: String) {
        guard connectionState == .connected else {
            log("⚠️ Cannot send text, not connected (state: \(connectionState.rawValue))")
            return
        }
        
        wsTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                self?.logError("Send text failed", error: error)
                self?.handleConnectionLost(error: error)
            }
        }
    }

    private func sendBinary(_ data: Data) {
        guard connectionState == .connected else {
            return // Silently skip to avoid log spam during reconnection
        }
        
        wsTask?.send(.data(data)) { [weak self] error in
            if let error = error {
                self?.logError("Send binary failed (\(data.count) bytes)", error: error)
                self?.handleConnectionLost(error: error)
            }
        }
    }

    private func receiveLoop() {
        wsTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                self.logError("Receive failed", error: error)
                self.handleConnectionLost(error: error)
                return // Don't continue receive loop on error
                
            case .success(let message):
                switch message {
                case .data(let data):
                    self.log("📥 Received binary data: \(data.count) bytes")
                    if self.isRealtimeAIOn {
                        self.playPcm16Audio(data)
                    }
                case .string(let text):
                    self.log("📥 Received text: \(text.prefix(200))\(text.count > 200 ? "..." : "")")
                @unknown default:
                    self.log("⚠️ Received unknown message type")
                }
                
                // Continue receiving only if still connected
                if self.connectionState == .connected {
                    self.receiveLoop()
                }
            }
        }
    }

    // MARK: - Audio Capture
    
    private var captureBufferCount = 0
    private var lastCaptureFormat: AVAudioFormat?

    private func startAudioCapture() {
        let bus = 0
        let bufferSize: AVAudioFrameCount = 1024
        
        // Log input device info FIRST
        logInputAudioRoute()
        
        // Get the current hardware format (after audio session is configured)
        let hardwareFormat = inputNode.inputFormat(forBus: bus)
        
        print("") // Empty line for readability
        print("🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤")
        print("🎤 INPUT AUDIO FORMAT (from mic)")
        print("🎤 Sample Rate: \(hardwareFormat.sampleRate) Hz")
        print("🎤 Channels: \(hardwareFormat.channelCount)")
        print("🎤 Common Format Raw Value: \(hardwareFormat.commonFormat.rawValue)")
        print("🎤 Format Description: \(describeAudioFormat(hardwareFormat.commonFormat))")
        print("🎤 Bits per channel: \(hardwareFormat.streamDescription.pointee.mBitsPerChannel)")
        print("🎤 Bytes per frame: \(hardwareFormat.streamDescription.pointee.mBytesPerFrame)")
        print("🎤 Bytes per packet: \(hardwareFormat.streamDescription.pointee.mBytesPerPacket)")
        print("🎤 Frames per packet: \(hardwareFormat.streamDescription.pointee.mFramesPerPacket)")
        print("🎤 Interleaved: \(hardwareFormat.isInterleaved)")
        print("🎤 Is Standard: \(hardwareFormat.isStandard)")
        print("🎤 Full Format: \(hardwareFormat)")
        print("🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤🎤")
        print("")
        
        captureBufferCount = 0
        
        // Use nil for format to use the hardware's native format directly
        // This avoids format mismatch errors with Bluetooth devices
        inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: nil) {
            [weak self] buffer, _ in
            guard let self = self else { return }
            
            self.captureBufferCount += 1
            
            // Log format change detection (only logs if format changes)
            self.logCaptureBufferFormat(buffer)

            if let request = self.recognitionRequest {
                request.append(buffer)
            }

            // Send raw audio buffer data
            if let data = self.bufferToData(buffer) {
                if self.isRealtimeAIOn {
                    // Log only every 500 buffers (~10-15 seconds depending on sample rate)
                    if self.captureBufferCount == 1 || self.captureBufferCount % 500 == 0 {
                        self.logDataBeingSent(data, buffer: buffer)
                        self.log("🎙️ Realtime AI ON, sending audio")
                    }
                    self.sendBinary(data)
                } else if self.captureBufferCount == 1 || self.captureBufferCount % 500 == 0 {
                    self.log("🚫 Realtime AI OFF, not sending audio")
                }
            }
        }

        do {
            try engine.start()
            log("✅ Audio engine started successfully")
        } catch {
            logError("Audio engine start error", error: error)
        }
    }
    
    private func logInputAudioRoute() {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        
        print("")
        print("📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱")
        print("📱 CURRENT INPUT DEVICE")
        print("📱 Number of inputs: \(currentRoute.inputs.count)")
        
        if currentRoute.inputs.isEmpty {
            print("📱 ⚠️ NO INPUT DEVICES FOUND!")
        }
        
        for (index, input) in currentRoute.inputs.enumerated() {
            print("📱 --- Input \(index + 1) ---")
            print("📱 Device Name: \(input.portName)")
            print("📱 Port Type: \(input.portType.rawValue)")
            print("📱 UID: \(input.uid)")
            if let channels = input.channels {
                print("📱 Channels: \(channels.count)")
            }
            if let dataSources = input.dataSources {
                print("📱 Data sources: \(dataSources.map { $0.dataSourceName }.joined(separator: ", "))")
            }
            
            // Check if it's Bluetooth
            if input.portType == .bluetoothHFP {
                print("📱 ✅ THIS IS BLUETOOTH HFP (Hands-Free Profile)")
            } else if input.portType == .bluetoothA2DP {
                print("📱 ✅ THIS IS BLUETOOTH A2DP")
            } else if input.portType == .builtInMic {
                print("📱 📱 THIS IS THE BUILT-IN PHONE MIC")
            }
        }
        print("📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱📱")
        print("")
    }
    
    private func logCaptureBufferFormat(_ buffer: AVAudioPCMBuffer) {
        let format = buffer.format
        if lastCaptureFormat == nil || lastCaptureFormat != format {
            log("📤 ===== CAPTURE BUFFER FORMAT CHANGED =====")
            log("📤 Sample Rate: \(format.sampleRate) Hz")
            log("📤 Channels: \(format.channelCount)")
            log("📤 Format: \(describeAudioFormat(format.commonFormat))")
            log("📤 Frame Length: \(buffer.frameLength) frames")
            log("📤 Frame Capacity: \(buffer.frameCapacity) frames")
            log("📤 ==========================================")
            lastCaptureFormat = format
        }
    }
    
    private func logDataBeingSent(_ data: Data, buffer: AVAudioPCMBuffer) {
        let format = buffer.format
        let frameCount = Int(buffer.frameLength)
        
        print("")
        print("📡📡📡 SENDING TO SERVER (buffer #\(captureBufferCount)) 📡📡📡")
        print("📡 Data size: \(data.count) bytes | Frames: \(frameCount)")
        print("📡 Sample rate: \(format.sampleRate) Hz | Format: \(describeAudioFormat(format.commonFormat))")
        print("")
    }
    
    private func describeAudioFormat(_ format: AVAudioCommonFormat) -> String {
        switch format {
        case .pcmFormatFloat32: return "Float32 (32-bit float)"
        case .pcmFormatFloat64: return "Float64 (64-bit float)"
        case .pcmFormatInt16: return "Int16 (16-bit signed integer)"
        case .pcmFormatInt32: return "Int32 (32-bit signed integer)"
        case .otherFormat: return "Other format"
        @unknown default: return "Unknown format"
        }
    }

    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)
        return Data(bytes: samples.baseAddress!, count: frameCount * MemoryLayout<Float>.size)
    }

    // MARK: - Audio Playback (PCM16LE 24k mono)
    
    private var playbackBufferCount = 0

    private func startAudioPlayback() {
        log("🔊 ===== OUTPUT AUDIO FORMAT (to speaker/Bluetooth) =====")
        log("🔊 Sample Rate: \(outputFormat.sampleRate) Hz")
        log("🔊 Channels: \(outputFormat.channelCount)")
        log("🔊 Format: \(describeAudioFormat(outputFormat.commonFormat))")
        log("🔊 Interleaved: \(outputFormat.isInterleaved)")
        logOutputAudioRoute()
        log("🔊 ======================================================")
        
        playbackBufferCount = 0
        player.play()
        notificationPlayer.play()
    }
    
    private func logOutputAudioRoute() {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        log("🔊 ===== CURRENT OUTPUT DEVICE =====")
        for output in currentRoute.outputs {
            log("🔊 Device: \(output.portName)")
            log("🔊 Type: \(output.portType.rawValue)")
            log("🔊 UID: \(output.uid)")
            if let channels = output.channels {
                log("🔊 Channels: \(channels.count)")
            }
        }
        log("🔊 ===================================")
    }

    private func playPcm16Audio(_ data: Data) {
        let bytesPerFrame = 2
        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        
        playbackBufferCount += 1
        
        // Log only every 100 buffers (or first one)
        if playbackBufferCount == 1 || playbackBufferCount % 100 == 0 {
            log("🔊 ===== RECEIVED FROM SERVER (buffer #\(playbackBufferCount)) =====")
            log("🔊 Data size: \(data.count) bytes")
            log("🔊 Frame count: \(frameCount) frames")
            log("🔊 Expected format: PCM Int16, 24000 Hz, 1 channel")
            log("🔊 Duration: \(String(format: "%.3f", Double(frameCount) / 24000.0)) seconds")
            
            // Log first few bytes of raw data
            let bytesToShow = min(16, data.count)
            let firstBytes = data.prefix(bytesToShow).map { String(format: "%02X", $0) }.joined(separator: " ")
            log("🔊 First \(bytesToShow) bytes (hex): \(firstBytes)")
            
            // Interpret first few samples as Int16
            if data.count >= 8 {
                let samples = data.withUnsafeBytes { raw -> [Int16] in
                    let ptr = raw.bindMemory(to: Int16.self)
                    return Array(ptr.prefix(4))
                }
                log("🔊 First 4 samples (Int16): \(samples)")
            }
            log("🔊 ======================================================")
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCount
        ) else {
            log("🔊 ❌ Failed to create PCM buffer!")
            return
        }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            memcpy(buffer.int16ChannelData![0], base, data.count)
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: - Speech Recognition (Wake/Stop Phrases)

    private func requestSpeechAuthorizationAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            guard status == .authorized else {
                self.log("⚠️ Speech recognition not authorized: \(status.rawValue)")
                return
            }
            self.startSpeechRecognition()
        }
    }

    private func startSpeechRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.requiresOnDeviceRecognition = false

        guard let recognitionRequest else {
            log("⚠️ Failed to create speech recognition request")
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                self.handleTranscription(result.bestTranscription.formattedString)
            }
            if let error = error as NSError? {
                // Filter out expected errors when manually stopping recognition
                if error.domain == "kLSRErrorDomain" && error.code == 301 {
                    return
                }
                // "No speech detected" - occurs when we cancel recognition after keyword trigger
                if error.domain == "kAFAssistantErrorDomain" && error.code == 1110 {
                    return
                }
                self.logError("Speech recognition error", error: error)
            }
        }
    }

    private func stopSpeechRecognition(clearState: Bool) {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        if clearState {
            clearTranscriptState()
        }
    }

    private func handleTranscription(_ text: String) {
        let normalized = normalizeText(text)
        guard !normalized.isEmpty else { return }

        updateRecentWords(with: normalized)
        let window = recentWords.joined(separator: " ")
        log("📝 Transcription: raw='\(text)' norm='\(normalized)' window='\(window)'")

        // "thank you" always works - it's the only way to turn off AI session
        if window.contains(stopPhrase) {
            setRealtimeAI(on: false, reason: "stop phrase detected")
            clearTranscriptState()

            DispatchQueue.main.async { [weak self] in
                self?.stopSpeechRecognition(clearState: true)
                self?.startSpeechRecognition()
            }
        } else if !isRealtimeAIOn && wakePhrases.contains(where: { window.contains($0) }) {
            // Only trigger "hey luna" when AI is OFF
            setRealtimeAI(on: true, reason: "wake phrase detected")
            clearTranscriptState()
            DispatchQueue.main.async { [weak self] in
                self?.stopSpeechRecognition(clearState: true)
                self?.startSpeechRecognition()
            }
        } else if !isRealtimeAIOn && highlightPhrases.contains(where: { window.contains($0) }) {
            // Only trigger "highlight" when AI is OFF
            log("📌 Highlight detected")
            playBookmarkNotification()
            sendHighlightSignal()
            clearTranscriptState()
            DispatchQueue.main.async { [weak self] in
                self?.stopSpeechRecognition(clearState: true)
                self?.startSpeechRecognition()
            }
        }
    }

    private func updateRecentWords(with normalized: String) {
        if lastNormalizedTranscript.isEmpty {
            recentWords = normalized.split(separator: " ").map(String.init)
        } else if normalized.hasPrefix(lastNormalizedTranscript) {
            let delta = normalized.dropFirst(lastNormalizedTranscript.count)
            let deltaWords = delta.split(whereSeparator: { $0 == " " }).map(String.init)
            if !deltaWords.isEmpty {
                recentWords.append(contentsOf: deltaWords)
            }
        } else {
            recentWords = normalized.split(separator: " ").map(String.init)
        }

        if recentWords.count > maxRecentWords {
            recentWords = Array(recentWords.suffix(maxRecentWords))
        }
        lastNormalizedTranscript = normalized
    }

    private func normalizeText(_ text: String) -> String {
        let lowercased = text.lowercased()
        let cleaned = lowercased.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(cleaned)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func clearTranscriptState() {
        lastNormalizedTranscript = ""
        recentWords.removeAll(keepingCapacity: true)
    }

    private func setRealtimeAI(on: Bool, reason: String) {
        guard isRealtimeAIOn != on else { return }
        isRealtimeAIOn = on
        log("🧠 Realtime AI set to \(on ? "ON" : "OFF") (\(reason))")
    }

    private func highlightURL() -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "ws":
            components.scheme = "http"
        case "wss":
            components.scheme = "https"
        default:
            break
        }
        components.path = "/api/bookmark"
        components.query = nil
        return components.url
    }

    private func sendHighlightSignal() {
        guard let highlightURL = highlightURL() else {
            log("⚠️ Highlight URL invalid")
            return
        }
        var request = URLRequest(url: highlightURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var payload: [String: Any] = [
            "type": "bookmark"
        ]
        if let sessionId = sessionId {
            payload["session_id"] = sessionId
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            logError("Failed to encode highlight payload", error: error)
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                self?.logError("Highlight request failed", error: error)
                return
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                self?.logError("Highlight request failed with status \(httpResponse.statusCode)", error: nil)
            } else {
                self?.log("✅ Highlight signal sent")
            }
        }.resume()
    }

    // MARK: - Bookmark Notification Sound (via AVAudioEngine for same output device)

    private func loadBookmarkNotificationBuffer() {
        // Try without subdirectory first (flat bundle structure)
        var fileURL = Bundle.main.url(forResource: "BookmarkNotification", withExtension: "wav")
        
        // If not found, try with subdirectory
        if fileURL == nil {
            fileURL = Bundle.main.url(
                forResource: "BookmarkNotification",
                withExtension: "wav",
                subdirectory: "Audio"
            )
        }
        
        guard let url = fileURL else {
            log("⚠️ BookmarkNotification.wav not found in bundle")
            return
        }
        
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let fileFormat = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            log("🔔 Loading BookmarkNotification.wav:")
            log("🔔   Sample Rate: \(fileFormat.sampleRate) Hz")
            log("🔔   Channels: \(fileFormat.channelCount)")
            log("🔔   Format: \(describeAudioFormat(fileFormat.commonFormat))")
            log("🔔   Frame Count: \(frameCount)")
            log("🔔   Duration: \(String(format: "%.2f", Double(frameCount) / fileFormat.sampleRate))s")
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frameCount) else {
                log("⚠️ Failed to create buffer for BookmarkNotification.wav")
                return
            }
            
            try audioFile.read(into: buffer)
            notificationBuffer = buffer
            
            // Connect notification player to mixer with the file's format
            engine.connect(notificationPlayer, to: engine.mainMixerNode, format: fileFormat)
            
            log("✅ BookmarkNotification.wav loaded and connected to audio engine")
            
        } catch {
            logError("Failed to load BookmarkNotification.wav", error: error)
        }
    }

    private func playBookmarkNotification() {
        guard let buffer = notificationBuffer else {
            log("⚠️ Notification buffer not loaded")
            return
        }
        
        log("🔔 Playing bookmark notification on same output as server audio")
        
        // Schedule the buffer on the notification player (which is attached to the same engine)
        notificationPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }
}

// MARK: - URLSessionWebSocketDelegate

extension AudioWsClient: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        log("✅ WebSocket didOpen with protocol: \(`protocol` ?? "none")")
        connectionState = .connected
        reconnectAttempts = 0
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        log("🔴 WebSocket didClose with code: \(closeCode.rawValue) (\(describeCloseCode(closeCode))), reason: \(reasonString)")
        
        if shouldReconnect && closeCode != .goingAway {
            scheduleReconnect()
        } else {
            connectionState = .disconnected
        }
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            logError("URLSession task completed with error", error: error)
            handleConnectionLost(error: error)
        } else {
            log("📋 URLSession task completed successfully")
        }
    }
    
    private func describeCloseCode(_ code: URLSessionWebSocketTask.CloseCode) -> String {
        switch code {
        case .invalid: return "Invalid"
        case .normalClosure: return "Normal closure"
        case .goingAway: return "Going away"
        case .protocolError: return "Protocol error"
        case .unsupportedData: return "Unsupported data"
        case .noStatusReceived: return "No status received"
        case .abnormalClosure: return "Abnormal closure"
        case .invalidFramePayloadData: return "Invalid frame payload"
        case .policyViolation: return "Policy violation"
        case .messageTooBig: return "Message too big"
        case .mandatoryExtensionMissing: return "Mandatory extension missing"
        case .internalServerError: return "Internal server error"
        case .tlsHandshakeFailure: return "TLS handshake failure"
        @unknown default: return "Unknown"
        }
    }
}
