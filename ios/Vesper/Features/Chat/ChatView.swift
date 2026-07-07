import SwiftUI

struct ChatView: View {
    @Environment(VesperAgent.self) private var agent
    @Environment(FlipperBLEManager.self) private var ble
    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionBanner
                messageList
                Divider()
                inputBar
            }
            .navigationTitle("Vesper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        agent.startNewSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(agent.isLoading)
                }
            }
            .sheet(isPresented: approvalBinding) {
                if let pending = agent.pendingApproval {
                    ApprovalSheet(pending: pending,
                                  onApprove: { agent.approvePending() },
                                  onReject: { agent.rejectPending() })
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var connectionBanner: some View {
        if !ble.connectionState.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Flipper not connected — connect in the Device tab.")
                    .font(.footnote)
                Spacer()
            }
            .foregroundStyle(.orange)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12))
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if agent.messages.isEmpty {
                        emptyState
                    }
                    ForEach(agent.messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if agent.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(agent.progress ?? "Working…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
            .onChange(of: agent.messages.count) {
                if let last = agent.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Talk to your Flipper")
                .font(.title3.bold())
            Text("Try: “What's on my SD card?”, “Show my SubGHz captures”, or “What's my battery level?”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 40)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message Vesper…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(agent.isLoading)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || agent.isLoading)
        }
        .padding()
    }

    private var approvalBinding: Binding<Bool> {
        Binding(
            get: { agent.pendingApproval != nil },
            set: { presented in
                if !presented && agent.pendingApproval != nil { agent.rejectPending() }
            }
        )
    }

    private func send() {
        let text = input
        input = ""
        Task { await agent.sendMessage(text) }
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            if let summary = message.toolCallSummary {
                Text(summary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(message.content)
                .font(bodyFont)
                .textSelection(.enabled)
                .padding(10)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(foreground)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var isUser: Bool { message.role == .user }
    private var isTool: Bool { message.role == .tool }

    private var alignment: HorizontalAlignment { isUser ? .trailing : .leading }
    private var frameAlignment: Alignment { isUser ? .trailing : .leading }
    private var bodyFont: Font { isTool ? .caption.monospaced() : .body }

    private var background: Color {
        switch message.role {
        case .user: return .accentColor
        case .tool: return Color(.secondarySystemBackground)
        default: return Color(.tertiarySystemBackground)
        }
    }

    private var foreground: Color { isUser ? .white : .primary }
}
