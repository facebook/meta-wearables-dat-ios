import SwiftUI

enum ButtonVariant {
    case primary, secondary, danger
}

struct NeonButton: View {
    let title: String
    let icon: String?
    let variant: ButtonVariant
    let action: () -> Void
    
    init(_ title: String, icon: String? = nil, variant: ButtonVariant = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.action = action
    }
    
    var backgroundView: some View {
        switch variant {
        case .primary:
            return AnyView(
                LinearGradient(colors: [.themeTeal, .themeBlue], startPoint: .leading, endPoint: .trailing)
            )
        case .secondary:
            return AnyView(
                Color.white.opacity(0.1)
            )
        case .danger:
            return AnyView(
                LinearGradient(colors: [.themeOrange, .red], startPoint: .leading, endPoint: .trailing)
            )
        }
    }
    
    var textColor: Color {
        switch variant {
        case .primary, .danger: return .black
        case .secondary: return .white
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .fontWeight(.bold)
                if let icon = icon {
                    Image(systemName: icon)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundView)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: variant == .secondary ? 1 : 0)
            )
            .cornerRadius(16)
            .foregroundColor(textColor)
            .shadow(radius: 5)
        }
    }
}
