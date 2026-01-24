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
        VStack(spacing: 22) {
            Spacer()
            
            // Animated icon with orbiting particles
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
                    .frame(width: 150, height: 150)
                    .blur(radius: 45)
                    .scaleEffect(pulsing ? 1.5 : 1.0)
                    .opacity(pulsing ? 0.2 : 0.5)
                
                // Main circle
                if showIcon {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 130, height: 130)
                        .shadow(color: .black.opacity(0.3), radius: 18)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 58))
                                .foregroundColor(.white)
                                .offset(y: pulsing ? -3 : 0)
                        )
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Orbiting particles
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(hex: "67d5ff"))
                        .frame(width: 12, height: 12)
                        .shadow(color: Color(hex: "67d5ff").opacity(0.8), radius: 8)
                        .offset(y: -85)
                        .rotationEffect(.degrees(orbitRotations[index]))
                }
            }
            .frame(height: 190)
            
            // Title
            VStack(spacing: 10) {
                Text("Let's start your first")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                
                Text("study session!")
                    .font(.system(size: 30, weight: .bold))
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
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "a1a1aa"))
                .opacity(subtitleOpacity)
            
            // Feature pills
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    FeaturePill5(emoji: "👓", text: "Hands-free")
                    FeaturePill5(emoji: "🎯", text: "Smart insights")
                }
                FeaturePill5(emoji: "📊", text: "Visual progress")
            }
            .opacity(featuresOpacity)
            .scaleEffect(featuresScale)
            
            Spacer()
            
            // CTA Button
            Button(action: onNext) {
                HStack(spacing: 12) {
                    Text("Start Learning Session")
                        .font(.system(size: 18, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(hex: "00c6a2").opacity(0.4), radius: 20)
                )
            }
            .padding(.horizontal, 4)
            .opacity(buttonOpacity)
            .offset(y: buttonOffset)
            
            Spacer()
                .frame(height: 32)
        }
        .padding(.horizontal, 28)
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
        HStack(spacing: 5) {
            Text(emoji)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "d4d4d8"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
