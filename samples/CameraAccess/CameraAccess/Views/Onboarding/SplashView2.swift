import SwiftUI

struct SplashView2: View {
    var transitionToNext: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 120, height: 120)
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 2))
                
                Image(systemName: "eye")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(.white)
            }
            
            Text("SmartSight")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 32)
            
            Text("Your personal AI learning companion")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
                .padding(.top, 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                transitionToNext()
            }
        }
    }
}
