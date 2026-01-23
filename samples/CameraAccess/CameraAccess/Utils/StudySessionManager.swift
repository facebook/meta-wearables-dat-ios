/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StudySessionManager.swift
//
// Manages study session API calls including starting sessions,
// uploading images for analysis, and ending sessions.
//

import UIKit
import Foundation

// MARK: - Response Models

struct SessionStartResponse: Codable {
  let success: Bool
  let data: SessionStartData?
}

struct SessionStartData: Codable {
  let sessionId: String
  let startedAt: String
  let status: String
}

struct UploadAnalysisResponse: Codable {
  let success: Bool
  let data: UploadAnalysisData?
}

struct UploadAnalysisData: Codable {
  let sessionId: String?
  let s3Key: String?
  let s3Url: String?
  let originalName: String?
  let contentType: String?
  let analysisId: String?
  let analysis: AnalysisWrapper?
  let uploadedAt: String?
}

struct AnalysisWrapper: Codable {
  let contentAnalysis: ContentAnalysis?
}

struct ContentAnalysis: Codable {
  let extracted_text: String?
  let language: String?
  let is_studying: Bool?
  let topic: String?
  let subtopic: String?
  let notes: String?
}

struct SessionEndResponse: Codable {
  let success: Bool
  let data: SessionEndData?
}

struct SessionEndData: Codable {
  let sessionId: String
  let endedAt: String
  let totalAnalyses: Int
}

// MARK: - Study Session Manager

@MainActor
class StudySessionManager: ObservableObject {
  static let shared = StudySessionManager()
  
  // Server configuration - UPDATE THIS IP IF YOUR SERVER CHANGES
  // Make sure your iPhone is on the same WiFi network as the server!
  private let serverURL = "http://10.29.240.40:7863"
  
  // Connection status
  @Published var isConnected: Bool = false
  
  // Session state
  @Published var currentSessionId: String?
  @Published var isSessionActive: Bool = false
  @Published var lastUploadSuccess: Bool?
  @Published var lastAnalysis: ContentAnalysis?
  @Published var uploadSuccessCount: Int = 0
  @Published var uploadFailureCount: Int = 0
  @Published var lastError: String?
  
  private init() {}
  
  // MARK: - Start Session
  
  func startSession() async -> Bool {
    guard let url = URL(string: "\(serverURL)/api/session/start") else {
      lastError = "Invalid URL"
      return false
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30 // 30 second timeout
    
    print("🔄 Attempting to connect to: \(serverURL)/api/session/start")
    
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
        lastError = "Invalid response from server"
        print("❌ Session start failed: Invalid response")
        return false
      }
      
      let sessionResponse = try JSONDecoder().decode(SessionStartResponse.self, from: data)
      
      guard sessionResponse.success, let sessionData = sessionResponse.data else {
        lastError = "Failed to start session"
        print("❌ Session start failed: success=false")
        return false
      }
      
      currentSessionId = sessionData.sessionId
      isSessionActive = true
      isConnected = true
      uploadSuccessCount = 0
      uploadFailureCount = 0
      lastAnalysis = nil
      lastError = nil
      
      print("✅ Session started: \(sessionData.sessionId)")
      return true
      
    } catch {
      lastError = error.localizedDescription
      print("❌ Session start error: \(error)")
      return false
    }
  }
  
  // MARK: - Upload and Analyze Image
  
  func uploadAndAnalyze(imageData: Data) async {
    // If no session, try to start one
    if currentSessionId == nil {
      print("⚠️ No active session, attempting to start one...")
      let started = await startSession()
      if !started {
        print("❌ Could not start session, skipping upload")
        lastUploadSuccess = false
        uploadFailureCount += 1
        return
      }
    }
    
    guard let sessionId = currentSessionId else {
      print("❌ No active session for upload")
      lastUploadSuccess = false
      uploadFailureCount += 1
      return
    }
    
    guard let url = URL(string: "\(serverURL)/api/upload-and-analyze") else {
      print("❌ Invalid upload URL")
      lastUploadSuccess = false
      uploadFailureCount += 1
      return
    }
    
    // Create multipart form request
    let boundary = UUID().uuidString
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30 // 30 second timeout
    
    // Build multipart body
    var body = Data()
    
    // Add image field (field name MUST be "image")
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n".data(using: .utf8)!)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    
    request.httpBody = body
    
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200 else {
        print("❌ Upload failed: Invalid response")
        lastUploadSuccess = false
        uploadFailureCount += 1
        return
      }
      
      let uploadResponse = try JSONDecoder().decode(UploadAnalysisResponse.self, from: data)
      
      guard uploadResponse.success, let uploadData = uploadResponse.data else {
        print("❌ Upload failed: success=false")
        lastUploadSuccess = false
        uploadFailureCount += 1
        return
      }
      
      // Update state with analysis results
      lastUploadSuccess = true
      uploadSuccessCount += 1
      lastAnalysis = uploadData.analysis?.contentAnalysis
      lastError = nil
      
      if let analysis = lastAnalysis {
        print("✅ Upload successful! Topic: \(analysis.topic ?? "Unknown"), Studying: \(analysis.is_studying ?? false)")
      } else {
        print("✅ Upload successful! (No analysis data)")
      }
      
    } catch {
      print("❌ Upload error: \(error)")
      lastUploadSuccess = false
      uploadFailureCount += 1
      lastError = error.localizedDescription
    }
  }
  
  // MARK: - End Session
  
  func endSession() async -> Int? {
    guard let sessionId = currentSessionId else {
      print("❌ No active session to end")
      return nil
    }
    
    guard let url = URL(string: "\(serverURL)/api/session/\(sessionId)/end") else {
      lastError = "Invalid URL"
      return nil
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200 else {
        print("❌ End session failed: Invalid response")
        // Still clean up local state
        cleanupSession()
        return nil
      }
      
      let endResponse = try JSONDecoder().decode(SessionEndResponse.self, from: data)
      
      guard endResponse.success, let endData = endResponse.data else {
        print("❌ End session failed: success=false")
        cleanupSession()
        return nil
      }
      
      print("✅ Session ended. Total analyses: \(endData.totalAnalyses)")
      cleanupSession()
      return endData.totalAnalyses
      
    } catch {
      print("❌ End session error: \(error)")
      cleanupSession()
      return nil
    }
  }
  
  // MARK: - Helpers
  
  private func cleanupSession() {
    currentSessionId = nil
    isSessionActive = false
    isConnected = false
    lastUploadSuccess = nil
    lastAnalysis = nil
  }
  
  func resetStats() {
    uploadSuccessCount = 0
    uploadFailureCount = 0
    lastError = nil
  }
}
