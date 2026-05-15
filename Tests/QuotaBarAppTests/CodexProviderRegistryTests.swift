import Foundation
import Testing
@testable import QuotaBarApp

@Suite("Codex registry")
struct CodexProviderRegistryTests {
    @Test("prepareAccount keeps registry active account unchanged")
    func prepareAccountDoesNotChangeActiveSelection() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = tempRoot.appendingPathComponent("codex-home", isDirectory: true)
        let managedHome = tempRoot.appendingPathComponent("managed-home", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        setenv("CODEX_HOME", codexHome.path, 1)
        defer {
            unsetenv("CODEX_HOME")
            try? fileManager.removeItem(at: tempRoot)
        }

        let provider = CodexProvider()
        var account = Account(tool: .codex, name: "Added account")
        account.settings.codexHomePath = managedHome.path

        let secret = codexSecret(
            email: "added@example.com",
            userID: "user-123",
            accountID: "acct-456"
        )

        let prepared = try await provider.prepareAccount(account, secret: secret)
        let registryURL = codexHome.appendingPathComponent("accounts/registry.json")
        let registry = try jsonDictionary(at: registryURL)

        #expect(prepared.settings.codexHomePath == managedHome.path)
        #expect((registry["active_account_key"] as? String) == nil)

        let accounts = registry["accounts"] as? [[String: Any]] ?? []
        #expect(accounts.count == 1)
        #expect(accounts.first?["account_key"] as? String == "user-123::acct-456")

        try await provider.activate(account: prepared, secret: secret)
        let activatedRegistry = try jsonDictionary(at: registryURL)
        #expect((activatedRegistry["active_account_key"] as? String) == "user-123::acct-456")
    }

    private func codexSecret(email: String, userID: String, accountID: String) -> String {
        let idToken = jwt(payload: [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID,
                "chatgpt_user_id": userID
            ]
        ])

        return """
        {
          "tokens": {
            "access_token": "access-token",
            "id_token": "\(idToken)"
          },
          "last_refresh": "2026-05-15T00:00:00Z"
        }
        """
    }

    private func jwt(payload: [String: Any]) -> String {
        let header = base64URL(#"{"alg":"none"}"#)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let payloadText = String(data: payloadData, encoding: .utf8)!
        return "\(header).\(base64URL(payloadText)).signature"
    }

    private func base64URL(_ text: String) -> String {
        Data(text.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func jsonDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return json as? [String: Any] ?? [:]
    }
}
