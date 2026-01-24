import SwiftUI

struct OnboardingPage5: View {
    var onNext: () -> Void
    
    @State private var showIcon = false
    @State private var pulsing = false
    @State private var orbitRotations: [Double] = [0, 120, 240]
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var featuresOpacity: Double = 0
    @State private var featuresScale: Double = 0.8
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: Double = 30
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Animated icon with orbiting particles - restored original animation
            ZStack {
                // Pulsing glow
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 180, height: 180)
                    .blur(radius: 50)
                    .scaleEffect(pulsing ? 1.5 : 1.0)
                    .opacity(pulsing ? 0.2 : 0.5)
                
                // Main circle - bigger
                if showIcon {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 160)
                        .shadow(color: .black.opacity(0.3), radius: 20)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 72))
                                .foregroundColor(.white)
                                .offset(y: pulsing ? -4 : 0)
                        )
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Orbiting particles - restored
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(hex: "67d5ff"))
                        .frame(width: 14, height: 14)
                        .shadow(color: Color(hex: "67d5ff").opacity(0.8), radius: 10)
                        .offset(y: -100)
                        .rotationEffect(.degrees(orbitRotations[index]))
                }
            }
            .frame(height: 220)
            
            // Title - bigger
            VStack(spacing: 12) {
                Text("Let's start your first")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                
                Text("study session!")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de"), Color(hex: "67d5ff")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .multilineTextAlignment(.center)
            .opacity(titleOpacity)
            
            Text("Your learning journey begins now")
                .font(.system(size: 22))
                .foregroundColor(Color(hex: "a1a1aa"))
                .opacity(subtitleOpacity)
            
            // Feature pills - bigger
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    FeaturePill5(emoji: "👓", text: "Hands-free")
                    FeaturePill5(emoji: "🎯", text: "Smart insights")
                }
                FeaturePill5(emoji: "📊", text: "Visual progress")
            }
            .opacity(featuresOpacity)
            .scaleEffect(featuresScale)
            
            Spacer()
            
            // CTA Button - bigger
            Button(action: onNext) {
                HStack(spacing: 14) {
                    Text("Start Learning Session")
                        .font(.system(size: 22, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(hex: "00c6a2").opacity(0.4), radius: 25)
                )
            }
            .padding(.horizontal, 24)
            .opacity(buttonOpacity)
            .offset(y: buttonOffset)
            
            Spacer()
                .frame(height: 40)
        }
        .padding(.horizontal, 16)
        .onAppear {
            animateSequence()
        }
    }
    
    private func animateSequence() {
        // Icon appears with spring
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
            showIcon = true
        }
        
        // Pulse animation starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        
        // Orbit animations - restored
        for index in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                    orbitRotations[index] = orbitRotations[index] + 360
                }
            }
        }
        
        // Title fades in
        withAnimation(.easeOut(duration: 0.7).delay(0.8)) {
            titleOpacity = 1
        }
        
        // Subtitle fades in
        withAnimation(.easeOut(duration: 0.7).delay(1.3)) {
            subtitleOpacity = 1
        }
        
        // Features fade and scale in
        withAnimation(.easeOut(duration: 0.6).delay(1.8)) {
            featuresOpacity = 1
            featuresScale = 1
        }
        
        // Button fades in and slides up
        withAnimation(.easeOut(duration: 0.6).delay(2.3)) {
            buttonOpacity = 1
            buttonOffset = 0
        }
    }
}

private struct FeaturePill5: View {
    let emoji: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 20))
            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(hex: "d4d4d8"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(hex: "18181b"))
                .overlay(
                    Capsule()
                        .stroke(Color(hex: "3f3f46"), lineWidth: 1)
                )
        )
    }
}
