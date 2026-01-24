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
        VStack(spacing: 28) {
            Spacer()
            
            // Animation area - stacked illustration
            ZStack {
                // Book (base layer) - bigger
                if showBook {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "3f3f46"))
                        .frame(width: 160, height: 115)
                        .overlay(
                            VStack(spacing: 10) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: "52525b"))
                                        .frame(height: 8)
                                }
                            }
                            .padding(24)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(hex: "52525b"), lineWidth: 1)
                        )
                        .offset(y: 35)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Person silhouette - bigger
                if showPerson {
                    Circle()
                        .fill(Color(hex: "3f3f46"))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "52525b"), lineWidth: 1)
                        )
                        .offset(x: -60, y: -25)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Phone - bigger
                if showPhone {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "67d5ff"))
                            .frame(width: 70, height: 115)
                            .blur(radius: 35)
                            .opacity(glowPulse ? 0.5 : 0.2)
                        
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "27272a"))
                            .frame(width: 70, height: 115)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "67d5ff"), Color(hex: "00c6a2")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .opacity(glowPulse ? 0.6 : 0.3)
                                    .padding(6)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "3f3f46"), lineWidth: 2)
                            )
                            .overlay(
                                Circle()
                                    .fill(Color(hex: "ffaa54"))
                                    .frame(width: 12, height: 12)
                                    .shadow(color: Color(hex: "ffaa54"), radius: 5)
                                    .offset(x: 26, y: -48)
                            )
                    }
                    .offset(x: 60, y: -35)
                    .rotationEffect(.degrees(-8))
                    .offset(y: glowPulse ? -4 : 0)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Focus broken label - bigger
                if showFocusBroken {
                    Text("Focus broken")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "ffaa54"))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
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
                        .offset(y: -105)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 240)
            
            // Text content - bigger
            if showText {
                VStack(spacing: 20) {
                    (
                        Text("Tracking your study sessions means pulling out your phone—")
                            .foregroundColor(.white)
                        +
                        Text("breaking your focus")
                            .foregroundColor(Color(hex: "ffaa54"))
                            .fontWeight(.bold)
                        +
                        Text(" before you even start.")
                            .foregroundColor(.white)
                    )
                    .font(.system(size: 26))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    
                    Text("So most learning goes unrecorded.\nYour effort stays invisible.")
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: "a1a1aa"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .offset(y: 20)))
            }
            
            Spacer()
            
            // Continue button - bigger
            if showButton {
                Button(action: onNext) {
                    HStack(spacing: 10) {
                        Text("Continue")
                            .font(.system(size: 20, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 20)
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
                .frame(height: 40)
        }
        .padding(.horizontal, 16)
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
