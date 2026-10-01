import Foundation

enum Role: String, Codable {
    case user
    case assistant
}

struct Attachment: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case image
        case pdf
        case text
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var mediaType: String
    var data: Data
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var role: Role
    var text: String
    var attachments: [Attachment] = []
    var model: String? = nil
    var isError = false
    var createdAt = Date()
}

struct Conversation: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = "新对话"
    var model: String
    var messages: [ChatMessage] = []
    var createdAt = Date()
    var updatedAt = Date()
}

struct AppSettings: Codable, Equatable {
    var apiHost = "https://api.anthropic.com"
    var apiKey = ""
    var models = ["claude-opus-5-5", "claude-sonnet-5-5"]
    var defaultModel = "claude-sonnet-5-5"
    var systemPrompt = ""
    var maxTokens = 16000
    var effort = ""
    var webdavURL = "https://dav.jianguoyun.com/dav/"
    var webdavUser = ""
    var webdavPassword = ""
    var autoSync = true

    var syncConfigured: Bool {
        !webdavURL.isEmpty && !webdavUser.isEmpty && !webdavPassword.isEmpty
    }
}
