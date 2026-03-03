import SwiftUI

struct CategoryRow: View {
    let name: String
    let icon: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(name)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 1)
    }
}
