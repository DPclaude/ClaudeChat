import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var newModel = ""
    @State private var testResult = ""
    @State private var testing = false

    private let efforts = ["", "low", "medium", "high", "xhigh", "max"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://你的中转站地址", text: $store.settings.apiHost)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $store.settings.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        testing = true
                        testResult = ""
                        Task {
                            testResult = await store.testConnection()
                            testing = false
                        }
                    } label: {
                        HStack {
                            Text("测试连接")
                            if testing { ProgressView().padding(.leading, 4) }
                        }
                    }
                    .disabled(testing || store.settings.apiKey.isEmpty)
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(testResult.hasPrefix("连接成功") ? .green : .red)
                    }
                } header: {
                    Text("API（Anthropic 格式）")
                } footer: {
                    Text("只填域名即可，App 会自动补全 /v1/messages。")
                }

                Section("模型") {
                    Picker("新对话默认模型", selection: $store.settings.defaultModel) {
                        ForEach(store.settings.models, id: \.self) { Text($0).tag($0) }
                    }
                    ForEach(store.settings.models, id: \.self) { model in
                        Text(model).font(.callout.monospaced())
                    }
                    .onDelete { offsets in
                        guard store.settings.models.count > offsets.count else { return }
                        store.settings.models.remove(atOffsets: offsets)
                        if !store.settings.models.contains(store.settings.defaultModel) {
                            store.settings.defaultModel = store.settings.models[0]
                        }
                    }
                    HStack {
                        TextField("添加模型 ID", text: $newModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("添加") {
                            let model = newModel.trimmingCharacters(in: .whitespaces)
                            if !model.isEmpty && !store.settings.models.contains(model) {
                                store.settings.models.append(model)
                            }
                            newModel = ""
                        }
                        .disabled(newModel.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Picker("思考强度（effort）", selection: $store.settings.effort) {
                        ForEach(efforts, id: \.self) { Text($0.isEmpty ? "默认" : $0).tag($0) }
                    }
                    Stepper("最大输出：\(store.settings.maxTokens)", value: $store.settings.maxTokens,
                            in: 1000...128000, step: 1000)
                    TextField("系统提示词（可选）", text: $store.settings.systemPrompt, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("生成参数")
                } footer: {
                    Text("如果中转站不支持 effort 参数而报错，改回“默认”。")
                }

                Section {
                    TextField("WebDAV 地址", text: $store.settings.webdavURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("账号", text: $store.settings.webdavUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("应用密码", text: $store.settings.webdavPassword)
                    Toggle("自动同步", isOn: $store.settings.autoSync)
                    Button {
                        Task { await store.sync() }
                    } label: {
                        HStack {
                            Text("立即同步")
                            if store.isSyncing { ProgressView().padding(.leading, 4) }
                        }
                    }
                    .disabled(store.isSyncing || !store.settings.syncConfigured)
                    if !store.syncStatus.isEmpty {
                        Text(store.syncStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("多设备同步（WebDAV）")
                } footer: {
                    Text("坚果云：账户信息 → 安全选项 → 第三方应用管理 → 添加应用，生成应用密码。对话保存在网盘的 ClaudeChat 文件夹。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
