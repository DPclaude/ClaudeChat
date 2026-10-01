import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    let conversationID: UUID

    @State private var input = ""
    @State private var attachments: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var attachError: String?
    @FocusState private var inputFocused: Bool

    private var conversation: Conversation? { store.conversation(conversationID) }
    private var streaming: Bool { store.isStreaming(conversationID) }
    private var canSend: Bool {
        !streaming && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(conversation?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { modelMenu }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 5, matching: .images)
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let attachment = AttachmentFactory.image(from: data) {
                        attachments.append(attachment)
                    }
                }
                photoItems = []
            }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .image, .plainText, .text, .sourceCode, .json, .commaSeparatedText, .data],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                if let attachment = AttachmentFactory.file(at: url) {
                    attachments.append(attachment)
                } else {
                    attachError = "不支持的文件：\(url.lastPathComponent)（支持图片、PDF、文本文件）"
                }
            }
        }
        .alert("无法添加附件", isPresented: Binding(get: { attachError != nil }, set: { if !$0 { attachError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(attachError ?? "")
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(store.settings.models, id: \.self) { model in
                Button {
                    store.setModel(conversationID, model)
                } label: {
                    if model == conversation?.model {
                        Label(model, systemImage: "checkmark")
                    } else {
                        Text(model)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(conversation?.model ?? "").font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(.primary)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(conversation?.messages ?? []) { message in
                        MessageRow(message: message,
                                   streaming: streaming && message.id == conversation?.messages.last?.id)
                            .id(message.id)
                    }
                    if let last = conversation?.messages.last, !streaming,
                       last.role == .assistant || last.isError {
                        Button {
                            store.regenerate(conversationID)
                        } label: {
                            Label("重新生成", systemImage: "arrow.clockwise")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation?.messages.last?.text) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: conversation?.messages.count) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(attachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                attachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button { showPhotoPicker = true } label: { Label("照片", systemImage: "photo") }
                    Button { showFileImporter = true } label: { Label("文件", systemImage: "doc") }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                TextField("发消息…", text: $input, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                if streaming {
                    Button { store.stop(conversationID) } label: {
                        Image(systemName: "stop.circle.fill").font(.title)
                    }
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                    }
                    .disabled(!canSend)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func send() {
        guard canSend else { return }
        store.send(conversationID, text: input.trimmingCharacters(in: .whitespacesAndNewlines), attachments: attachments)
        input = ""
        attachments = []
    }
}

struct AttachmentChip: View {
    let attachment: Attachment
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            if attachment.kind == .image, let image = UIImage(data: attachment.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "doc.text")
                    .frame(width: 36, height: 36)
                Text(attachment.name).font(.caption).lineLimit(1).frame(maxWidth: 120)
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(6)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
