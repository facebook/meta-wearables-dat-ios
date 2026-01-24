import SwiftUI

struct OnboardingPage4: View {
    var onNext: () -> Void
    
    @State private var showCard = false
    @State private var topicProgress: [CGFloat] = [0, 0, 0, 0]
    @State private var showInsight = false
    @State private var showText = false
    @State private var showButton = false
    
    private let topics: [(name: String, time: String, progress: CGFloat, color: String, icon: String)] = [
        ("Calculus", "65 min", 0.65, "00c6a2", "∫"),
        ("Physics", "45 min", 0.45, "8ef1de", "⚡"),
        ("History", "30 min", 0.30, "67d5ff", "📜"),
        ("Literature", "50 min", 0.50, "ffaa54", "📖")
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // Topic time card
            if showCard {
                VStack(spacing: 14) {
                    Text("Today's Study Time")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 6)
                    
                    VStack(spacing: 14) {
                        ForEach(Array(topics.enumerated()), id: \.offset) { index, topic in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    HStack(spacing: 8) {
                                        Text(topic.icon)
                                            .font(.system(size: 16))
                                        Text(topic.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                    Text(topic.time)
                                        .font(.system(size: 14).monospacedDigit())
                                        .foregroundColor(Color(hex: "a1a1aa"))
                                }
                                .padding(.horizontal, 12)
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(hex: "27272a"))
                                        
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(hex: topic.color))
                                            .frame(width: geo.size.width * topicProgress[index])
                                            .shadow(color: Color(hex: topic.color).opacity(0.5), radius: 6)
                                    }
                                }
                                .frame(height: 10)
                                .padding(.horizontal, 12)
                            }
                            .opacity(topicProgress[index] > 0 ? 1 : 0.5)
                        }
                    }
                    
                    // Insight box - with top padding to push it lower
                    if showInsight {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "00c6a2").opacity(0.2))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(hex: "00c6a2"))
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Quick insight")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(hex: "00c6a2"))
                                Text("You spent 2x more time on Calculus.")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "a1a1aa"))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "00c6a2").opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "00c6a2").opacity(0.3), lineWidth: 1)
                                )
                        )
                        .padding(.top, 8)
                        .padding(.horizontal, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(hex: "18181b"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color(hex: "27272a"), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .offset(y: 20)))
            }
            
            // Text
            if showText {
                Text("See what you studied and for how long. Spot which topics slow you down.")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
            
            Spacer()
            
            // Button
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
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            showCard = true
        }
        
        for index in 0..<topics.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(index) * 0.2) {
                withAnimation(.easeOut(duration: 0.8)) {
                    topicProgress[index] = topics[index].progress
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showInsight = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.5)) {
                showText = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showButton = true
            }
        }
    }
}
