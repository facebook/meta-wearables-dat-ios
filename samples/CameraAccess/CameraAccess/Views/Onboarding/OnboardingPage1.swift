import SwiftUI

struct OnboardingPage1: View {
    var onNext: () -> Void
    
    @State private var showBook = false
    @State private var showPhone = false
    @State private var showPerson = false
    @State private var glowPulse = false
    @State private var showFocusBroken = false
    @State private var showText = false
    @State private var showButton = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Animation area - stacked illustration
            ZStack {
                // Book (base layer)
                if showBook {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "3f3f46"))
                        .frame(width: 140, height: 100)
                        .overlay(
                            VStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: "52525b"))
                                        .frame(height: 6)
                                }
                            }
                            .padding(20)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "52525b"), lineWidth: 1)
                        )
                        .offset(y: 30)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Person silhouette
                if showPerson {
                    Circle()
                        .fill(Color(hex: "3f3f46"))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "52525b"), lineWidth: 1)
                        )
                        .offset(x: -50, y: -20)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Phone
                if showPhone {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hex: "67d5ff"))
                            .frame(width: 60, height: 100)
                            .blur(radius: 30)
                            .opacity(glowPulse ? 0.5 : 0.2)
                        
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hex: "27272a"))
                            .frame(width: 60, height: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "67d5ff"), Color(hex: "00c6a2")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .opacity(glowPulse ? 0.6 : 0.3)
                                    .padding(5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(hex: "3f3f46"), lineWidth: 2)
                            )
                            .overlay(
                                Circle()
                                    .fill(Color(hex: "ffaa54"))
                                    .frame(width: 10, height: 10)
                                    .shadow(color: Color(hex: "ffaa54"), radius: 5)
                                    .offset(x: 22, y: -42)
                            )
                    }
                    .offset(x: 50, y: -30)
                    .rotationEffect(.degrees(-8))
                    .offset(y: glowPulse ? -4 : 0)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Focus broken label
                if showFocusBroken {
                    Text("Focus broken")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "ffaa54"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(hex: "ffaa54").opacity(glowPulse ? 0.3 : 0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(Color(hex: "ffaa54").opacity(glowPulse ? 0.8 : 0.5), lineWidth: 1)
                                )
                        )
                        .scaleEffect(glowPulse ? 1.05 : 1.0)
                        .shadow(color: Color(hex: "ffaa54").opacity(glowPulse ? 0.5 : 0), radius: 10)
                        .offset(y: -90)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 200)
            
            // Text content
            if showText {
                VStack(spacing: 12) {
                    Text("Tracking your learning means manual work...")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 4) {
                        Text("Breaking your focus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(hex: "ffaa54"))
                            .padding(10)
                        
                        Text("before you even start.")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .offset(y: 20)))
            }
            
            Spacer()
            
            // Continue button
            if showButton {
                Button(action: onNext) {
                    HStack(spacing: 8) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Color(hex: "27272a"))
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: "3f3f46"), lineWidth: 1)
                            )
                    )
                }
                .transition(.opacity)
            }
            
            Spacer()
                .frame(height: 32)
        }
        .padding(.horizontal, 28)
        .onAppear {
            animateSequence()
        }
    }
    
    private func animateSequence() {
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            showBook = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showPhone = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.5)) {
                showPerson = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showFocusBroken = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                showText = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.5)) {
                showButton = true
            }
        }
    }
}
