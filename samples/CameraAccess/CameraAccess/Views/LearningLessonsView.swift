import SwiftUI

// MARK: - 1. Data Models & View Model

// 1A. Lesson Card
struct LessonCard: Identifiable {
    let id = UUID()
    let topic: String
    let subtopic: String
    let text: String
    let iconName: String
    let color: Color
    var isBookmarked: Bool
}

// 1B. Shared View Model (Single Source of Truth)
@Observable
class LessonViewModel {
    var allLessons: [LessonCard] = [
        LessonCard(topic: "SwiftUI Architecture", subtopic: "State Management", text: "Mastering the flow of data using @State, @Binding, and the Observation framework.", iconName: "square.stack.3d.up.fill", color: .cyan, isBookmarked: false),
        LessonCard(topic: "Human Interface", subtopic: "Micro-Interactions", text: "How subtle haptics and spring animations can elevate the overall user experience.", iconName: "hand.tap.fill", color: .purple, isBookmarked: true),
        LessonCard(topic: "Data Structures", subtopic: "Graph Traversal", text: "Exploring efficient pathfinding algorithms for complex navigation tasks.", iconName: "point.topleft.down.curvedto.point.bottomright.up", color: .green, isBookmarked: false)
    ]
    
    var bookmarkedLessons: [LessonCard] {
        allLessons.filter { $0.isBookmarked }
    }
    
    func toggleBookmark(for lessonID: UUID) {
        if let index = allLessons.firstIndex(where: { $0.id == lessonID }) {
            allLessons[index].isBookmarked.toggle()
        }
    }
}

// MARK: - 2. Custom Colors
extension Color {
    static let whoopBackground = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let whoopCard = Color(red: 0.11, green: 0.11, blue: 0.12)
}

// MARK: - 3. Main App View (Renamed)
struct LearningLessonsView: View {
    @State private var viewModel = LessonViewModel()

    var body: some View {
        TabView {
            HomeTab()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            BookmarksTab()
                .tabItem {
                    Label("Bookmarks", systemImage: "bookmark.fill")
                }
        }
        .tint(.white)
        .environment(viewModel)
        .preferredColorScheme(.dark)
    }
}

// MARK: - 4. Home Tab
struct HomeTab: View {
    @Environment(LessonViewModel.self) private var viewModel
    
    // Animation states for the circular charts (values between 0.0 and 1.0)
    @State private var chart1Progress: CGFloat = 0.0
    @State private var chart2Progress: CGFloat = 0.0
    @State private var chart3Progress: CGFloat = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: Top Section - Circular Graphs
                    VStack(alignment: .leading, spacing: 16) {
                        Text("DAILY METRICS")
                            .font(.subheadline)
                            .fontWeight(.heavy)
                            .foregroundColor(.gray)
                            .tracking(1.2)
                            .padding(.horizontal, 24)

                        HStack(spacing: 0) {
                            Spacer()
                            // Chart 1: Shows 45 minutes (75% of 60)
                            CircularProgressView(progress: chart1Progress, maxValue: 60, unit: "m", title: "Math", color: .cyan)
                            Spacer()
                            // Chart 2: Shows 20 minutes (40% of 50)
                            CircularProgressView(progress: chart2Progress, maxValue: 50, unit: "m", title: "Physics", color: .orange)
                            Spacer()
                            // Chart 3: Shows 90% (90% of 100)
                            CircularProgressView(progress: chart3Progress, maxValue: 100, unit: "m", title: "Biology", color: .green)
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.top, 20)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.spring(response: 1.5, dampingFraction: 0.8)) {
                                chart1Progress = 0.75 // 75% of 60 mins = 45m
                                chart2Progress = 0.40 // 40% of 50 mins = 20m
                                chart3Progress = 0.90 // 90% of 100% = 90%
                            }
                        }
                    }

                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.gray.opacity(0.3))
                        .padding(.horizontal, 24)

                    // MARK: Bottom Section - All Lessons List
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ALL LESSONS")
                            .font(.subheadline)
                            .fontWeight(.heavy)
                            .foregroundColor(.gray)
                            .tracking(1.2)
                            .padding(.horizontal, 24)

                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.allLessons) { lesson in
                                BookmarkCardView(lesson: lesson)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Learning Lessons")
            .background(Color.whoopBackground)
        }
    }
}

// MARK: - 5. Bookmarks Tab
struct BookmarksTab: View {
    @Environment(LessonViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.bookmarkedLessons.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks Yet",
                        systemImage: "bookmark.slash",
                        description: Text("Lessons you bookmark will appear here.")
                    )
                    .padding(.top, 100)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.bookmarkedLessons) { lesson in
                            BookmarkCardView(lesson: lesson)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Bookmarks")
            .background(Color.whoopBackground)
        }
    }
}

// MARK: - 6. Subviews

// UPDATED: Circular Progress View with Dynamic Units
struct CircularProgressView: View {
    var progress: CGFloat // Current percentage (0.0 to 1.0)
    var maxValue: CGFloat // The target total (e.g., 60 for minutes, 100 for percent)
    var unit: String      // The string suffix (e.g., "m", "%", "h")
    var title: String
    var color: Color

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 10)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.5), radius: 5)
                
                // Calculates the current value based on the animated progress
                let currentValue = Int(progress * maxValue)
                
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(currentValue)")
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.bold)
                    
                    Text(unit)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .foregroundColor(.white)
            }
            .frame(width: 70, height: 70)
            
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
                .tracking(1.0)
        }
    }
}

// Lesson Card Component
struct BookmarkCardView: View {
    @Environment(LessonViewModel.self) private var viewModel
    var lesson: LessonCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: lesson.iconName)
                    .font(.title3)
                    .foregroundColor(lesson.color)
                    .padding(10)
                    .background(lesson.color.opacity(0.15))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.topic)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(lesson.subtopic)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.toggleBookmark(for: lesson.id)
                    }
                }) {
                    Image(systemName: lesson.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                        .foregroundColor(lesson.isBookmarked ? lesson.color : .gray)
                }
            }
            
            Text(lesson.text)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(3)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.whoopCard)
        )
    }
}

#Preview {
    LearningLessonsView()
}
