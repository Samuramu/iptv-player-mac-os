import SwiftUI

struct EPGTimelineView: View {
    let channel: Channel
    let programs: [EPGProgram]

    private let hourWidth: CGFloat = 200
    private let rowHeight: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                Text("Program Guide")
                    .font(.headline)
            }
            .foregroundStyle(.secondary)

            if programs.isEmpty {
                Text("No EPG data available")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 2) {
                        ForEach(programs) { program in
                            EPGProgramView(
                                program: program,
                                width: programWidth(for: program)
                            )
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func programWidth(for program: EPGProgram) -> CGFloat {
        let duration = program.stopTime.timeIntervalSince(program.startTime)
        let hours = duration / 3600
        return max(CGFloat(hours) * hourWidth, 80)
    }
}
