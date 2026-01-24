import SwiftUI

struct OnboardingPage3: View {
    var onNext: () -> Void
    
    @State private var glassesOpacity: Double = 0
    @State private var glassesScale: Double = 0.5
    @State private var glassesFloat: CGFloat = 0
    @State private var glowPulse = false
    @State private var indicatorOpacity: Double = 0
    @State private var indicatorScale: Double = 0.5
    @State private var indicatorPulse = false
    @State private var titleOpacity: Double = 0
    @State private var descriptionOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Glasses icon with glow
            ZStack {
                Circle()
                    .fill(Color(hex: "00c6a2"))
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .opacity(glowPulse ? 0.4 : 0.15)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 32)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "18181b"), Color(hex: "27272a")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 170, height: 170)
                        .overlay(
                            RoundedRectangle(cornerRadius: 32)
                                .stroke(Color(hex: "3f3f46"), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 40)
                    
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 80, weight: .thin))
                        .foregroundColor(Color(hex: "00c6a2"))
                    
                    Circle()
                        .fill(Color(hex: "00c6a2"))
                        .frame(width: 14, height: 14)
                        .shadow(color: Color(hex: "00c6a2"), radius: indicatorPulse ? 16 : 8)
                        .scaleEffect(indicatorPulse ? 1.2 : 1.0)
                        .offset(x: 70, y: -70)
                        .opacity(indicatorOpacity)
                        .scaleEffect(indicatorScale)
                }
                .opacity(glassesOpacity)
                .scaleEffect(glassesScale)
                .offset(y: glassesFloat)
            }
            .frame(height: 210)
            
            // Text content - ensure text fits
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    Text("Meet ")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("SmartSight")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .opacity(titleOpacity)
                
                Text("Your hands-free learning companion")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: "d4d4d8"))
                    .multilineTextAlignment(.center)
                    .opacity(descriptionOpacity)
                
                (
                    Text("Built for ")
                        .foregroundColor(Color(hex: "a1a1aa"))
                    +
                    Text("Meta Ray-Ban smart glasses")
                        .foregroundColor(Color(hex: "00c6a2"))
                        .fontWeight(.bold)
                    +
                    Text(", SmartSight quietly captures your study sessions so you can ")
                        .foregroundColor(Color(hex: "a1a1aa"))
                    +
                    Text("stay focused")
                        .foregroundColor(Color(hex: "00c6a2"))
                        .fontWeight(.bold)
                    +
                    Text(" while it remembers for you.")
                        .foregroundColor(Color(hex: "a1a1aa"))
                )
                .font(.system(size: 18))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(descriptionOpacity)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Button - bigger
            Button(action: onNext) {
                HStack(spacing: 12) {
                    Text("See how it works")
                        .font(.system(size: 20, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 44)
                .padding(.vertical, 20)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(hex: "00c6a2").opacity(0.4), radius: 30)
                )
            }
            .opacity(buttonOpacity)
            
            Spacer()
                .frame(height: 40)
        }
        .padding(.horizontal, 16)
        .onAppear {
            animateSequence()
        }
    }
    
    private func animateSequence() {
        withAnimation(.easeOut(duration: 0.7).delay(0.3)) {
            glassesOpacity = 1
            glassesScale = 1
        }
        
        // Start floating animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glassesFloat = -10
            }
        }
        
        // Glow pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(0.8)) {
            indicatorOpacity = 1
            indicatorScale = 1
        }
        
        // Indicator pulse animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                indicatorPulse = true
            }
        }
        
        withAnimation(.easeOut(duration: 0.6).delay(1.0)) {
            titleOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 0.7).delay(2.5)) {
            descriptionOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(3.2)) {
            buttonOpacity = 1
        }
    }
}
