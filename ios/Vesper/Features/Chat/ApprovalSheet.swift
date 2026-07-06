import SwiftUI

/// Presents a MEDIUM/HIGH action for the user to approve. HIGH actions require a 1.5s hold.
struct ApprovalSheet: View {
    let pending: PendingApproval
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    riskHeader
                    detailRows
                    if let diff = pending.diff, !diff.isEmpty {
                        Text("Changes")
                            .font(.headline)
                        DiffView(diff: diff)
                    }
                }
                .padding()
            }
            .navigationTitle("Approve action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reject", role: .cancel) { onReject() }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
    }

    private var riskHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pending.riskLevel.displayName) risk")
                    .font(.headline)
                Text(pending.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .foregroundStyle(riskColor)
        .padding()
        .background(riskColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Action", pending.command.action.displayName)
            if let path = pending.command.args.path { row("Path", path) }
            if let command = pending.command.args.command { row("Command", command) }
            if !pending.command.justification.isEmpty { row("Why", pending.command.justification) }
            if !pending.command.expectedEffect.isEmpty { row("Effect", pending.command.expectedEffect) }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        VStack {
            if pending.requiresHoldToConfirm {
                HoldToConfirmButton(title: "Hold to confirm", action: onApprove)
            } else {
                Button(action: onApprove) {
                    Text("Approve")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .background(.bar)
    }

    private var iconName: String {
        pending.riskLevel == .high ? "exclamationmark.octagon.fill" : "pencil.and.outline"
    }

    private var riskColor: Color {
        switch pending.riskLevel {
        case .high: return .red
        case .medium: return .orange
        default: return .blue
        }
    }
}

/// A press-and-hold button that fires only after being held for `duration`.
struct HoldToConfirmButton: View {
    let title: String
    let action: () -> Void
    var duration: Double = 1.5

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                Capsule().fill(Color.red.opacity(0.25))
                Capsule()
                    .fill(Color.red)
                    .frame(width: geo.size.width * progress)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 50)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40, pressing: { pressing in
            withAnimation(.linear(duration: pressing ? duration : 0.2)) {
                progress = pressing ? 1 : 0
            }
        }, perform: {
            action()
        })
        .accessibilityLabel(title)
    }
}
