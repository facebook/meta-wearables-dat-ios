import SwiftUI

struct OnboardingPage4: View {
    var onNext: () -> Void
    
    @State private var showBadges = false
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
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 16)
            
            // Feature badges - bigger
            if showBadges {
                HStack(spacing: 16) {
                    BadgePill(text: "📊 Track time", color: "00c6a2")
                    BadgePill(text: "🎯 Spot struggles", color: "ffaa54")
                }
                .transition(.opacity.combined(with: .offset(y: -20)))
            }
            
            // Topic time card - bigger
            if showCard {
                VStack(spacing: 18) {
                    Text("Today's Study Time")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 20) {
                        ForEach(Array(topics.enumerated()), id: \.offset) { index, topic in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    HStack(spacing: 10) {
                                        Text(topic.icon)
                                            .font(.system(size: 20))
                                        Text(topic.name)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                    Text(topic.time)
                                        .font(.system(size: 16).monospacedDigit())
                                        .foregroundColor(Color(hex: "a1a1aa"))
                                }
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(hex: "27272a"))
                                        
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(hex: topic.color))
                                            .frame(width: geo.size.width * topicProgress[index])
                                            .shadow(color: Color(hex: topic.color).opacity(0.5), radius: 8)
                                    }
                                }
                                .frame(height: 12)
                            }
                            .opacity(topicProgress[index] > 0 ? 1 : 0.5)
                        }
                    }
                    
                    // Insight box - bigger
                    if showInsight {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "00c6a2").opacity(0.2))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color(hex: "00c6a2"))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Quick insight")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color(hex: "00c6a2"))
                                Text("You spent 2x more time on Calculus. History might need more focus.")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "a1a1aa"))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(hex: "00c6a2").opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(hex: "00c6a2").opacity(0.3), lineWidth: 1)
                                )
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: "18181b"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(hex: "27272a"), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .offset(y: 20)))
            }
            
            // Text - bigger
            if showText {
                Text("See what you studied and for how long. Spot which topics slow you down.")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
            
            Spacer()
            
            // Button - bigger
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
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            showBadges = true
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            showCard = true
        }
        
        for index in 0..<topics.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + Double(index) * 0.2) {
                withAnimation(.easeOut(duration: 0.8)) {
                    topicProgress[index] = topics[index].progress
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showInsight = true
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

private struct BadgePill: View {
    let text: String
    let color: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(Color(hex: color))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color(hex: color).opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: color).opacity(0.3), lineWidth: 1)
                    )
            )
    }
}
