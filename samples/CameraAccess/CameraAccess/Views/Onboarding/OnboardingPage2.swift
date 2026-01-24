import SwiftUI

struct OnboardingPage2: View {
    var onNext: () -> Void
    
    @State private var investedBarOpacity: Double = 0
    @State private var investedProgress: CGFloat = 0
    @State private var vsOpacity: Double = 0
    @State private var vsScale: Double = 0.5
    @State private var retainedBarOpacity: Double = 0
    @State private var retainedProgress: CGFloat = 0
    @State private var alertOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Comparison bars - bigger
            VStack(spacing: 20) {
                // Time Invested bar
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Time Invested")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color(hex: "a1a1aa"))
                        Spacer()
                        Text("8 hours")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "00c6a2"))
                    }
                    
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "27272a"))
                            .frame(height: 64)
                        
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * investedProgress, height: 64)
                                .shadow(color: Color(hex: "00c6a2").opacity(0.4), radius: 20)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Full day studying")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 18)
                    }
                    .frame(height: 64)
                }
                .opacity(investedBarOpacity)
                
                // VS indicator - bigger
                ZStack {
                    Circle()
                        .fill(Color(hex: "27272a"))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "3f3f46"), lineWidth: 1)
                        )
                    
                    Text("VS")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "a1a1aa"))
                }
                .opacity(vsOpacity)
                .scaleEffect(vsScale)
                
                // Knowledge Retained bar
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Knowledge Retained")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color(hex: "a1a1aa"))
                        Spacer()
                        Text("~3 hours worth")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "ffaa54"))
                    }
                    
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "27272a"))
                            .frame(height: 64)
                        
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "ffaa54"), Color(hex: "ff8844")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * retainedProgress * 0.37, height: 64)
                                .shadow(color: Color(hex: "ffaa54").opacity(0.4), radius: 20)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.downtrend.xyaxis")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Actual retention")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 18)
                    }
                    .frame(height: 64)
                }
                .opacity(retainedBarOpacity)
                
                // Alert box - ensure text doesn't clip
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "ffaa54").opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "ffaa54"))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("~5 hours lost")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(hex: "ffaa54"))
                        Text("Without tracking what worked, you can't optimize")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "a1a1aa"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "ffaa54").opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(hex: "ffaa54").opacity(0.3), lineWidth: 1)
                        )
                )
                .opacity(alertOpacity)
            }
            .padding(.horizontal, 24)
            
            // Text - ensure it doesn't clip
            Text("Without data, you can't see where you struggled, what actually worked, or how to improve.")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .opacity(textOpacity)
            
            Spacer()
            
            // Button - bigger
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
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            investedBarOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 1.2).delay(0.5)) {
            investedProgress = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
            vsOpacity = 1
            vsScale = 1
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(1.3)) {
            retainedBarOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 1.2).delay(1.5)) {
            retainedProgress = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(2.5)) {
            alertOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 0.6).delay(3.0)) {
            textOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(3.3)) {
            buttonOpacity = 1
        }
    }
}
