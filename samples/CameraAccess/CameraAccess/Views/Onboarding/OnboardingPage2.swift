import SwiftUI

struct OnboardingPage2: View {
    var onNext: () -> Void
    
    @State private var investedBarOpacity: Double = 0
    @State private var investedProgress: CGFloat = 0
    @State private var retainedBarOpacity: Double = 0
    @State private var retainedProgress: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Comparison bars
            VStack(spacing: 16) {
                // Time Invested bar
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Time Invested")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "a1a1aa"))
                        Spacer()
                        Text("8 hours")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "00c6a2"))
                    }
                    
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "27272a"))
                            .frame(height: 54)
                        
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * investedProgress, height: 54)
                                .shadow(color: Color(hex: "00c6a2").opacity(0.4), radius: 16)
                        }
                        
                        HStack(spacing: 10) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Full day studying")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(height: 54)
                }
                .opacity(investedBarOpacity)
                .padding(20)
                
                // Knowledge Retained bar
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Knowledge Retained")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "a1a1aa"))
                        Spacer()
                        Text("~3 hours worth")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "ffaa54"))
                    }
                    
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "27272a"))
                            .frame(height: 54)
                        
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "ffaa54"), Color(hex: "ff8844")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * retainedProgress * 0.37, height: 54)
                                .shadow(color: Color(hex: "ffaa54").opacity(0.4), radius: 16)
                        }
                        
                        HStack(spacing: 10) {
                            Image(systemName: "chart.line.downtrend.xyaxis")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Actual retention")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(height: 54)
                }
                .opacity(retainedBarOpacity)
            }
            .padding(.horizontal, 8)
            
            // Text
            Text("Without data, you can't see where you struggled, what actually worked, or how to improve.")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .opacity(textOpacity)
            
            Spacer()
            
            // Button
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
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            investedBarOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 1.2).delay(0.5)) {
            investedProgress = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
            retainedBarOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 1.2).delay(1.2)) {
            retainedProgress = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.6).delay(2.2)) {
            textOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(2.5)) {
            buttonOpacity = 1
        }
    }
}
