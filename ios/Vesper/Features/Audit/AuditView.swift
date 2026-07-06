import SwiftUI

struct AuditView: View {
    @Environment(AuditService.self) private var audit

    var body: some View {
        NavigationStack {
            Group {
                if audit.recentEntries.isEmpty {
                    ContentUnavailableView("No activity yet",
                                           systemImage: "list.bullet.rectangle",
                                           description: Text("Actions the agent takes appear here."))
                } else {
                    List(audit.recentEntries) { entry in
                        AuditRow(entry: entry)
                    }
                }
            }
            .navigationTitle("Audit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: audit.exportJSON()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(audit.recentEntries.isEmpty)
                }
            }
        }
    }
}

private struct AuditRow: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.actionType.rawValue)
                    .font(.caption.bold())
                Spacer()
                if let risk = entry.riskLevel {
                    Text(risk.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(riskColor(risk).opacity(0.15), in: Capsule())
                        .foregroundStyle(riskColor(risk))
                }
                if let success = entry.success {
                    Image(systemName: success ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(success ? .green : .red)
                        .font(.caption)
                }
            }
            if !entry.summary.isEmpty {
                Text(entry.summary).font(.footnote).foregroundStyle(.secondary)
            }
            Text(entry.timestamp, style: .time)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func riskColor(_ risk: RiskLevel) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        case .blocked: return .purple
        }
    }
}
