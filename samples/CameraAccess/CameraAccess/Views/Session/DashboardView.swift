import SwiftUI

// MARK: - View Model

class DashboardViewModel: ObservableObject {
    @Published var view: DashboardViewType = .summary
    
    let strainScore: Double = 7.8
    let focusedTime: Int = 60
    let consistency: Int = 21
    let overallScore: Int = 85
    let struggles: Int = 6
    
    let topics: [DashboardTopicData] = [
        DashboardTopicData(topic: "Calculus - Integration", time: "45 min", progress: 0.85, color: Color(hex: "00c6a2")),
        DashboardTopicData(topic: "Geometry - Proofs", time: "32 min", progress: 0.60, color: Color(hex: "8ef1de")),
        DashboardTopicData(topic: "Shakespeare - Analysis", time: "28 min", progress: 0.45, color: Color(hex: "ffaa54")),
        DashboardTopicData(topic: "Physics - Kinematics", time: "15 min", progress: 0.30, color: Color(hex: "67d5ff"))
    ]
    
    let effortData: [Int] = [3, 4, 6, 8, 9, 7, 8, 9, 10, 8, 6, 5]
    
    func toggleView() {
        withAnimation(.easeInOut(duration: 0.3)) {
            view = view == .summary ? .detailed : .summary
        }
    }
}

enum DashboardViewType {
    case summary
    case detailed
}

// MARK: - Data Models

struct DashboardTopicData: Identifiable {
    let id = UUID()
    let topic: String
    let time: String
    let progress: Double
    let color: Color
}

struct StatData: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let color: Color
}

// MARK: - Main View

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var animateRing = false
    var onBack: () -> Void
    
    var body: some View {
        ZStack {
            Color(hex: "121212")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                
                ScrollView {
                    if viewModel.view == .summary {
                        summaryContent
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    } else {
                        detailedContent
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5)) {
                animateRing = true
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 0) {
            // This spacer pushes into the safe area, filled by the background
            Spacer()
                .frame(height: 0)
            
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text("Learning Dashboard")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: viewModel.toggleView) {
                    Text(viewModel.view == .summary ? "Details" : "Summary")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "00c6a2"))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(
            Color(hex: "121212")
                .ignoresSafeArea(edges: .top)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.2)),
            alignment: .bottom
        )
    }
    
    // MARK: - Summary Content
    
    private var summaryContent: some View {
        VStack(spacing: 24) {
            strainRingView
            statsGrid
            aiInsightCard
        }
        .padding(24)
    }
    
    // MARK: - Strain Ring
    
    private var strainRingView: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 20)
                .frame(width: 200, height: 200)
            
            // Green ring - Focused Time (60%)
            Circle()
                .trim(from: 0, to: animateRing ? Double(viewModel.focusedTime) / 100.0 : 0)
                .stroke(
                    Color(hex: "00c6a2"),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(hex: "00c6a2").opacity(0.5), radius: 10)
            
            // Orange ring - Consistency (21%) - overlays from the start
            Circle()
                .trim(from: 0, to: animateRing ? Double(viewModel.consistency) / 100.0 : 0)
                .stroke(
                    Color(hex: "ffaa54"),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(hex: "ffaa54").opacity(0.5), radius: 10)
            
            // Center text
            VStack(spacing: 4) {
                Text("Focus Score")
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundColor(.gray)
                
                Text("\(viewModel.overallScore)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                + Text("%")
                    .font(.title2)
                    .foregroundColor(.gray)
                
                Text("overall")
                    .font(.caption2)
                    .foregroundColor(Color.gray.opacity(0.6))
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Stats Grid
    
    private var statsGrid: some View {
        let stats = [
            StatData(icon: "clock", label: "Focused Time", value: "\(viewModel.focusedTime)%", color: Color(hex: "00c6a2")),
            StatData(icon: "target", label: "Consistency", value: "\(viewModel.consistency)%", color: Color(hex: "ffaa54")),
            StatData(icon: "trophy", label: "Score", value: "\(viewModel.overallScore)%", color: Color(hex: "00c6a2")),
            StatData(icon: "exclamationmark.circle", label: "Struggles", value: "\(viewModel.struggles)/10", color: Color(hex: "ffaa54"))
        ]
        
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(stats) { stat in
                StatCard(stat: stat)
            }
        }
    }
    
    // MARK: - AI Insight
    
    private var aiInsightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "00c6a2"), Color(hex: "8ef1de")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "bolt.fill")
                    .foregroundColor(.black)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Insight")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("You struggled with logical questions today—let's review those specifically.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineSpacing(4)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Detailed Content
    
    private var detailedContent: some View {
        VStack(spacing: 24) {
            topicCoverageSection
            struggleHeatmapSection
            mentalEffortSection
            Spacer().frame(height: 32)
        }
        .padding(24)
    }
    
    // MARK: - Topic Coverage
    
    private var topicCoverageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "book")
                    .foregroundColor(Color(hex: "00c6a2"))
                Text("Topic Coverage")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                ForEach(Array(viewModel.topics.enumerated()), id: \.element.id) { index, topic in
                    TopicCard(topic: topic, delay: Double(index) * 0.1)
                }
            }
        }
    }
    
    // MARK: - Struggle Heatmap
    
    private var struggleHeatmapSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(Color(hex: "ffaa54"))
                Text("Struggle Heatmap")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 16) {
                HStack(spacing: 2) {
                    ForEach(0..<24, id: \.self) { i in
                        let intensity = (i >= 8 && i <= 12) ? Double.random(in: 0.2...1.0) : Double.random(in: 0...0.3)
                        let color = intensity > 0.5 ? Color(hex: "ffaa54") : Color(hex: "00c6a2")
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(intensity))
                            .frame(height: 80)
                            .shadow(color: intensity > 0.5 ? color.opacity(0.4) : .clear, radius: 5)
                    }
                }
                
                HStack {
                    Text("12:00 PM")
                        .font(.caption2)
                        .foregroundColor(Color.gray.opacity(0.6))
                    
                    Spacer()
                    
                    Text("Most struggle at 2:30 PM (15+ min stuck)")
                        .font(.caption2)
                        .foregroundColor(Color.gray.opacity(0.6))
                    
                    Spacer()
                    
                    Text("4:00 PM")
                        .font(.caption2)
                        .foregroundColor(Color.gray.opacity(0.6))
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Mental Effort Graph
    
    private var mentalEffortSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(Color(hex: "00c6a2"))
                Text("Mental Effort Over Time")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 16) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(viewModel.effortData.enumerated()), id: \.offset) { index, value in
                        EffortBar(value: value, index: index)
                    }
                }
                .frame(height: 128)
                
                HStack(spacing: 16) {
                    legendItem(color: Color(hex: "00c6a2"), label: "Low Strain")
                    legendItem(color: Color(hex: "ffaa54"), label: "High Strain")
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .shadow(color: color.opacity(0.6), radius: 4)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
    let stat: StatData
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: stat.icon)
                    .foregroundColor(stat.color)
                
                Text(stat.label)
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundColor(.gray)
            }
            
            Text(stat.value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: stat.color.opacity(0.1), radius: 10)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

struct TopicCard: View {
    let topic: DashboardTopicData
    let delay: Double
    @State private var animateProgress = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(topic.topic)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(topic.time)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(topic.color)
                        .frame(width: animateProgress ? geometry.size.width * topic.progress : 0, height: 8)
                        .shadow(color: topic.color.opacity(0.4), radius: 5)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1).delay(delay)) {
                animateProgress = true
            }
        }
    }
}

struct EffortBar: View {
    let value: Int
    let index: Int
    @State private var animateHeight = false
    
    var color: Color {
        value > 7 ? Color(hex: "ffaa54") : Color(hex: "00c6a2")
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(height: animateHeight ? CGFloat(value) * 12.8 : 0)
            .frame(maxWidth: .infinity)
            .shadow(color: color.opacity(0.4), radius: 5)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(Double(index) * 0.1)) {
                    animateHeight = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    DashboardView(onBack: {})
}
