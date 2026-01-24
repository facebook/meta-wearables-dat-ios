import SwiftUI

struct DetailRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let value: String
    let valueColor: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .padding(10)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading) {
                Text(title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(valueColor)
                .fontWeight(valueColor == .gray ? .regular : .bold)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}
