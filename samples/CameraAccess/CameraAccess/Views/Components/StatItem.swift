import SwiftUI

struct StatItem: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .fontWeight(.bold)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}
