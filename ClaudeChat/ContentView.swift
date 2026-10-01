import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ChatStore
    @State private var selection: UUID?
    @State private var search = ""
    @State private var showSettings = false
    @State private var renaming: Conversation?
    @State private var renameText = ""

    private var filtered: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.conversations }
        return store.conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query)
                || conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if !store.syncStatus.isEmpty && store.settings.syncConfigured {
                    Text(store.syncStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { conversation in
                    NavigationLink(value: conversation.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conversation.title).lineLimit(1)
                                if store.isStreaming(conversation.id) {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                            Text("\(conversation.model) · \(conversation.updatedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteConversation(conversation.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            renameText = conversation.title
                            renaming = conversation
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button {
                            renameText = conversation.title
                            renaming = conversation
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteConversation(conversation.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索对话")
            .refreshable { await store.sync() }
            .navigationTitle("对话")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        selection = store.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .overlay {
                if store.conversations.isEmpty {
                    VStack(spacing: 12) {
                        Text("还没有对话").foregroundStyle(.secondary)
                        Button("开始新对话") { selection = store.newConversation() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        } detail: {
            if let id = selection, store.conversation(id) != nil {
                ChatView(conversationID: id)
                    .id(id)
            } else {
                Text("选择或新建一个对话").foregroundStyle(.secondary)
            }
        }
        .onChange(of: selection) { [previous = selection] _ in
            if let previous { store.discardIfEmpty(previous) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .alert("重命名对话", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("标题", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("确定") {
                if let conversation = renaming { store.rename(conversation.id, to: renameText) }
                renaming = nil
            }
        }
        .onAppear {
            if store.settings.apiKey.isEmpty { showSettings = true }
        }
    }

    private func deleteConversation(_ id: UUID) {
        if selection == id { selection = nil }
        store.delete(id)
    }
}
