import SwiftUI

struct EPGProgramView: View {
    let program: EPGProgram
    let width: CGFloat

    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(Self.timeFormatter.string(from: program.startTime))
                Text("-")
                Text(Self.timeFormatter.string(from: program.stopTime))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if program.isCurrentlyAiring {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .frame(height: 3)
                        Capsule()
                            .fill(.accent)
                            .frame(width: geo.size.width * program.progress, height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(8)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(program.isCurrentlyAiring ?
                      Color.accentColor.opacity(0.2) :
                      Color.white.opacity(0.05))
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .help(program.desc.isEmpty ? program.title : program.desc)
    }
}
