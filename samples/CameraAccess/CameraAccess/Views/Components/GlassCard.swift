import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    var borderColor: Color = .white.opacity(0.2)
    
    init(borderColor: Color = .white.opacity(0.2), @ViewBuilder content: () -> Content) {
        self.borderColor = borderColor
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}
