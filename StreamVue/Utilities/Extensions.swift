import SwiftUI

extension Color {
    static let cardBackground = Color.white.opacity(0.05)
    static let cardBorder = Color.white.opacity(0.1)
}

extension View {
    func cardStyle(isSelected: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : .cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : .cardBorder, lineWidth: 1)
            )
    }
}

extension Date {
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
}
