import Foundation
import SwiftUI

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published private(set) var streamingIDs: Set<UUID> = []
    @Published private(set) var isSyncing = false
    @Published var syncStatus = ""

    private var tombstones: [UUID: Date] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let folder: URL
    private let tombstoneURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("conversations", isDirectory: true)
        tombstoneURL = docs.appendingPathComponent("tombstones.json")
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: tombstoneURL),
           let saved = try? JSONDecoder().decode([UUID: Date].self, from: data) {
            tombstones = saved
        }
        loadConversations()
    }

    // MARK: - 对话管理

    func conversation(_ id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func isStreaming(_ id: UUID) -> Bool {
        streamingIDs.contains(id)
    }

    func newConversation() -> UUID {
        let conversation = Conversation(model: settings.defaultModel)
        conversations.insert(conversation, at: 0)
        return conversation.id
    }

    /// 离开一个从未发过消息的对话时丢弃它，避免列表里堆满空对话。
    func discardIfEmpty(_ id: UUID) {
        guard let conversation = conversation(id), conversation.messages.isEmpty else { return }
        removeLocal(id)
    }

    func delete(_ id: UUID) {
        removeLocal(id)
        tombstones[id] = Date()
        saveTombstones()
        syncInBackground()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed }
        persist(id)
    }

    func setModel(_ id: UUID, _ model: String) {
        update(id) { $0.model = model }
        persist(id)
    }

    // MARK: - 发送消息

    func send(_ id: UUID, text: String, attachments: [Attachment]) {
        guard !isStreaming(id) else { return }
        update(id) { conversation in
            conversation.messages.append(ChatMessage(role: .user, text: text, attachments: attachments))
            if conversation.title == "新对话" {
                let source = text.isEmpty ? (attachments.first?.name ?? "新对话") : text
                conversation.title = String(source.replacingOccurrences(of: "\n", with: " ").prefix(24))
            }
        }
        persist(id)
        startReply(id)
    }

    func regenerate(_ id: UUID) {
        guard !isStreaming(id) else { return }
        update(id) { conversation in
            while conversation.messages.last?.role == .assistant {
                conversation.messages.removeLast()
            }
        }
        startReply(id)
    }

    func stop(_ id: UUID) {
        tasks[id]?.cancel()
    }

    private func startReply(_ id: UUID) {
        guard let conversation = conversation(id), conversation.messages.last?.role == .user else { return }
        let model = conversation.model
        let history = conversation.messages
        let reply = ChatMessage(role: .assistant, text: "", model: model)
        let replyID = reply.id
        update(id) { $0.messages.append(reply) }
        streamingIDs.insert(id)

        let stream = makeClient().stream(model: model, system: settings.systemPrompt,
                                         maxTokens: settings.maxTokens, effort: settings.effort,
                                         messages: history)
        tasks[id] = Task { [weak self] in
            var pending = ""
            var lastFlush = Date()
            var failure: Error?
            do {
                for try await chunk in stream {
                    pending += chunk
                    if Date().timeIntervalSince(lastFlush) > 0.05 {
                        self?.appendText(pending, to: replyID, in: id)
                        pending = ""
                        lastFlush = Date()
                    }
                }
            } catch {
                if !Task.isCancelled { failure = error }
            }
            self?.appendText(pending, to: replyID, in: id)
            self?.finishReply(id, replyID, error: failure)
        }
    }

    private func appendText(_ text: String, to messageID: UUID, in id: UUID) {
        guard !text.isEmpty else { return }
        update(id, touch: false) { conversation in
            if let j = conversation.messages.firstIndex(where: { $0.id == messageID }) {
                conversation.messages[j].text += text
            }
        }
    }

    private func finishReply(_ id: UUID, _ messageID: UUID, error: Error?) {
        update(id) { conversation in
            guard let j = conversation.messages.firstIndex(where: { $0.id == messageID }) else { return }
            if let error {
                if conversation.messages[j].text.isEmpty {
                    conversation.messages[j].isError = true
                    conversation.messages[j].text = "请求失败：\(error.localizedDescription)"
                } else {
                    conversation.messages[j].text += "\n\n（中断：\(error.localizedDescription)）"
                }
            } else if conversation.messages[j].text.isEmpty {
                conversation.messages.remove(at: j)
            }
        }
        streamingIDs.remove(id)
        tasks[id] = nil
        persist(id)
        syncInBackground()
    }

    func testConnection() async -> String {
        let probe = ChatMessage(role: .user, text: "hi")
        do {
            var reply = ""
            for try await chunk in makeClient().stream(model: settings.defaultModel, system: "",
                                                       maxTokens: 64, effort: "", messages: [probe]) {
                reply += chunk
            }
            return "连接成功（\(settings.defaultModel)）\(reply.isEmpty ? "" : "：" + reply.prefix(40))"
        } catch {
            return "连接失败：\(error.localizedDescription)"
        }
    }

    private func makeClient() -> AnthropicClient {
        AnthropicClient(host: settings.apiHost, apiKey: settings.apiKey)
    }

    // MARK: - WebDAV 同步

    func syncInBackground() {
        guard settings.autoSync, settings.syncConfigured else { return }
        Task { await sync() }
    }

    func sync() async {
        guard !isSyncing else { return }
        guard settings.syncConfigured,
              let dav = WebDAVClient(urlString: settings.webdavURL, user: settings.webdavUser,
                                     password: settings.webdavPassword) else {
            syncStatus = "未配置 WebDAV"
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await dav.ensureFolder()
            var index = try await dav.fetchIndex()
            var indexChanged = false
            var uploaded = 0
            var downloaded = 0

            // 1. 其他设备删除的对话 → 本地删除
            for (key, entry) in index.entries where entry.deleted {
                guard let id = UUID(uuidString: key),
                      let local = conversation(id),
                      local.updatedAt <= entry.updatedAt,
                      !isStreaming(id) else { continue }
                removeLocal(id)
                tombstones[id] = entry.updatedAt
            }

            // 2. 本地删除的对话 → 远端标记删除
            for (id, deletedAt) in tombstones {
                let key = id.uuidString
                if let entry = index.entries[key], entry.updatedAt >= deletedAt { continue }
                index.entries[key] = SyncEntry(updatedAt: deletedAt, deleted: true)
                try? await dav.delete("\(key).json")
                indexChanged = true
            }

            // 3. 本地较新的 → 上传
            for conversation in conversations where !conversation.messages.isEmpty && !isStreaming(conversation.id) {
                let key = conversation.id.uuidString
                if let entry = index.entries[key], entry.updatedAt >= conversation.updatedAt { continue }
                try await dav.put("\(key).json", data: JSONEncoder().encode(conversation))
                index.entries[key] = SyncEntry(updatedAt: conversation.updatedAt, deleted: false)
                indexChanged = true
                uploaded += 1
            }

            // 4. 远端较新的 → 下载
            for (key, entry) in index.entries where !entry.deleted {
                guard let id = UUID(uuidString: key), !isStreaming(id) else { continue }
                if let local = conversation(id), local.updatedAt >= entry.updatedAt { continue }
                if let deletedAt = tombstones[id], deletedAt > entry.updatedAt { continue }
                guard let data = try await dav.get("\(key).json") else { continue }
                let remote = try JSONDecoder().decode(Conversation.self, from: data)
                tombstones[id] = nil
                upsertLocal(remote)
                downloaded += 1
            }

            if indexChanged { try await dav.putIndex(index) }
            saveTombstones()
            let time = Date().formatted(date: .omitted, time: .shortened)
            syncStatus = "\(time) 已同步：上传 \(uploaded)，下载 \(downloaded)"
        } catch {
            syncStatus = "同步失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 本地存储

    private func update(_ id: UUID, touch: Bool = true, _ change: (inout Conversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[i])
        if touch { conversations[i].updatedAt = Date() }
    }

    private func fileURL(_ id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    private func persist(_ id: UUID) {
        guard let conversation = conversation(id),
              let data = try? JSONEncoder().encode(conversation) else { return }
        try? data.write(to: fileURL(id), options: .atomic)
    }

    private func upsertLocal(_ conversation: Conversation) {
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[i] = conversation
        } else {
            conversations.append(conversation)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist(conversation.id)
    }

    private func removeLocal(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        streamingIDs.remove(id)
        conversations.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    private func loadConversations() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        conversations = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Conversation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "settings")
        }
    }

    private func saveTombstones() {
        if let data = try? JSONEncoder().encode(tombstones) {
            try? data.write(to: tombstoneURL, options: .atomic)
        }
    }
}
