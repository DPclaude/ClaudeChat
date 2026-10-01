import SwiftUI
import MarkdownUI

/// 基于正则的轻量代码高亮：注释、字符串、数字、关键字。
struct SimpleHighlighter: CodeSyntaxHighlighter {
    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "import", "class", "struct", "enum",
        "protocol", "extension", "switch", "case", "default", "break", "continue", "guard", "in", "do", "try",
        "catch", "throw", "throws", "async", "await", "self", "nil", "true", "false", "static", "private",
        "public", "def", "from", "as", "with", "lambda", "None", "True", "False", "and", "or", "not", "is",
        "pass", "yield", "elif", "function", "const", "new", "this", "null", "undefined", "typeof", "export",
        "interface", "type", "implements", "extends", "package", "go", "fn", "mut", "impl", "pub", "use",
        "match", "int", "void", "char", "float", "double", "bool", "string", "long", "using", "namespace",
        "select", "where", "insert", "update", "delete", "create", "table", "echo", "then", "fi", "done",
    ]

    private static let hashCommentLanguages: Set<String> = [
        "python", "py", "sh", "bash", "shell", "zsh", "ruby", "rb", "yaml", "yml", "toml", "r", "perl",
        "dockerfile", "makefile", "powershell", "ps1",
    ]

    private static let basePattern = ##"(//[^\n]*|/\*[\s\S]*?\*/)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`[^`]*`)|(\b\d+(?:\.\d+)?\b)|(\b[A-Za-z_][A-Za-z0-9_]*\b)"##
    private static let hashPattern = ##"(#[^\n]*|//[^\n]*|/\*[\s\S]*?\*/)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`[^`]*`)|(\b\d+(?:\.\d+)?\b)|(\b[A-Za-z_][A-Za-z0-9_]*\b)"##

    private static let baseRegex = try! NSRegularExpression(pattern: basePattern)
    private static let hashRegex = try! NSRegularExpression(pattern: hashPattern)

    func highlightCode(_ content: String, language: String?) -> Text {
        let lang = language?.lowercased() ?? ""
        let regex = Self.hashCommentLanguages.contains(lang) ? Self.hashRegex : Self.baseRegex
        let ns = content as NSString
        var result = AttributedString()
        var cursor = 0

        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let token = ns.substring(with: match.range)
            var piece = AttributedString(token)
            if match.range(at: 1).location != NSNotFound {
                piece.foregroundColor = Color.gray
            } else if match.range(at: 2).location != NSNotFound {
                piece.foregroundColor = Color(red: 0.77, green: 0.16, blue: 0.12)
            } else if match.range(at: 3).location != NSNotFound {
                piece.foregroundColor = Color(red: 0.11, green: 0.42, blue: 0.85)
            } else if Self.keywords.contains(token) {
                piece.foregroundColor = Color(red: 0.61, green: 0.15, blue: 0.69)
            }
            result += piece
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += AttributedString(ns.substring(from: cursor))
        }
        return Text(result)
    }
}

extension CodeSyntaxHighlighter where Self == SimpleHighlighter {
    static var simple: Self { SimpleHighlighter() }
}
