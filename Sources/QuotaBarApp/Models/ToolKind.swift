import Foundation

enum ToolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case cursor
    case claudeCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .cursor:
            return "Cursor"
        case .claudeCode:
            return "Claude Code"
        }
    }
}
