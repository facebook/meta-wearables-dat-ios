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
        VStack(spacing: 20) {
            Spacer()
            
            // Glasses icon with glow
            ZStack {
                Circle()
                    .fill(Color(hex: "00c6a2"))
                    .frame(width: 160, height: 160)
                    .blur(radius: 50)
                    .opacity(glowPulse ? 0.4 : 0.15)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "18181b"), Color(hex: "27272a")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color(hex: "3f3f46"), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 30)
                    
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 65, weight: .thin))
                        .foregroundColor(Color(hex: "00c6a2"))
                    
                    Circle()
                        .fill(Color(hex: "00c6a2"))
                        .frame(width: 12, height: 12)
                        .shadow(color: Color(hex: "00c6a2"), radius: indicatorPulse ? 14 : 6)
                        .scaleEffect(indicatorPulse ? 1.2 : 1.0)
                        .offset(x: 58, y: -58)
                        .opacity(indicatorOpacity)
                        .scaleEffect(indicatorScale)
                }
                .opacity(glassesOpacity)
                .scaleEffect(glassesScale)
                .offset(y: glassesFloat)
            }
            .frame(height: 180)
            
            // Text content
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    Text("Meet ")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("SmartSight")
                        .font(.system(size: 30, weight: .bold))
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
                    .font(.system(size: 18))
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
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(descriptionOpacity)
            }
            .padding(.horizontal, 8)
            
            Spacer()
            
            // Button
            Button(action: onNext) {
                HStack(spacing: 10) {
                    Text("See how it works")
                        .font(.system(size: 18, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 36)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(hex: "00c6a2").opacity(0.4), radius: 24)
                )
            }
            .opacity(buttonOpacity)
            
            Spacer()
                .frame(height: 32)
        }
        .padding(.horizontal, 28)
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
