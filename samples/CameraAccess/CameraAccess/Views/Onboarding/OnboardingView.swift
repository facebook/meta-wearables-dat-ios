import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    var onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Subtle gradient accents
            Circle()
                .fill(Color(hex: "00c6a2").opacity(0.05))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(x: 150, y: -200)
            
            Circle()
                .fill(Color(hex: "67d5ff").opacity(0.05))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(x: -150, y: 300)
            
            VStack(spacing: 0) {
                // Content
                Group {
                    switch currentPage {
                    case 0:
                        OnboardingPage1(onNext: nextPage)
                    case 1:
                        OnboardingPage2(onNext: nextPage)
                    case 2:
                        OnboardingPage3(onNext: nextPage)
                    case 3:
                        OnboardingPage4(onNext: nextPage)
                    case 4:
                        OnboardingPage5(onNext: onComplete)
                    default:
                        EmptyView()
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color(hex: "00c6a2") : Color(hex: "3f3f46"))
                            .frame(width: index == currentPage ? 24 : 6, height: 6)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
    
    private func nextPage() {
        withAnimation {
            if currentPage < 4 {
                currentPage += 1
            } else {
                onComplete()
            }
        }
    }
}
