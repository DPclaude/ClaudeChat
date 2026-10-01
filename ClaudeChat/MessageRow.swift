import SwiftUI
import MarkdownUI

struct MessageRow: View {
    let message: ChatMessage
    let streaming: Bool
    @State private var copied = false

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    if !message.attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(message.attachments) { AttachmentChip(attachment: $0) }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .contextMenu { copyButton }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if message.isError {
                    Label(message.text, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else if message.text.isEmpty && streaming {
                    ProgressView()
                } else {
                    Markdown(message.text)
                        .markdownCodeSyntaxHighlighter(.simple)
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            CodeBlockView(configuration: configuration)
                        }
                        .textSelection(.enabled)
                }
                if !streaming && !message.isError {
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = message.text
                            copied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                copied = false
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        if let model = message.model {
                            Text(model)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu { copyButton }
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
    }
}

struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.language ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = configuration.content
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))

            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .relativeLineSpacing(.em(0.25))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding(12)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .markdownMargin(top: 4, bottom: 12)
    }
}
