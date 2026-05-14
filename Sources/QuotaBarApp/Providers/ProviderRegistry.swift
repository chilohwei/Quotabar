import Foundation

struct ProviderRegistry: Sendable {
    let supportedTools: [ToolKind] = [.codex, .cursor, .claudeCode]

    func provider(for tool: ToolKind) -> any Provider {
        switch tool {
        case .codex:
            return CodexProvider()
        case .cursor:
            return CursorProvider()
        case .claudeCode:
            return ClaudeCodeProvider()
        }
    }
}
