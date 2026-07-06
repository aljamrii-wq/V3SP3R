import SwiftUI

/// Renders a unified diff string (lines prefixed with `+ ` / `- `).
struct DiffView: View {
    let diff: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(background(for: line))
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 220)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var lines: [String] { diff.components(separatedBy: "\n") }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .secondary
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") { return .green.opacity(0.12) }
        if line.hasPrefix("-") { return .red.opacity(0.12) }
        return .clear
    }
}
