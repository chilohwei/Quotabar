import Foundation

protocol Provider: Sendable {
    var tool: ToolKind { get }
    var treatsImportedCredentialsAsActiveSelection: Bool { get }
    func importCurrentCredentials() async throws -> String
    func updateCurrentCredentials(_ secret: String) async throws
    func authenticateViaBrowser() async throws -> String
    func prepareAccount(_ account: Account, secret: String) async throws -> Account
    func activate(account: Account, secret: String) async throws
    func fetchQuota(secret: String) async throws -> QuotaSnapshot
    func fetchQuota(account: Account, secret: String) async throws -> QuotaSnapshot
    func fetchQuota(account: Account, secret: String, forceRefresh: Bool) async throws -> QuotaSnapshot
    func refreshSecretIfNeeded(_ secret: String) async throws -> String
    func refreshSecretAfterAuthenticationFailure(_ secret: String) async throws -> String?
    func persistRefreshedSecret(_ secret: String, for account: Account, isActive: Bool) async throws
    func isAuthenticationFailure(_ error: Error) -> Bool
    func recoverSecret(for account: Account) async throws -> String?
    func accountIdentity(from secret: String) -> String?
    func accountIdentityAliases(from secret: String) -> [String]
    func suggestAccountName(from secret: String) -> String?
    func deleteAccountArtifacts(account: Account) async throws
}

extension Provider {
    var treatsImportedCredentialsAsActiveSelection: Bool {
        true
    }

    func updateCurrentCredentials(_ secret: String) async throws {
        _ = secret
    }

    func authenticateViaBrowser() async throws -> String {
        throw ProviderError.unsupported("当前工具暂不支持浏览器登录导入")
    }

    func prepareAccount(_ account: Account, secret: String) async throws -> Account {
        _ = secret
        return account
    }

    func recoverSecret(for account: Account) async throws -> String? {
        _ = account
        return nil
    }

    func fetchQuota(account: Account, secret: String) async throws -> QuotaSnapshot {
        _ = account
        return try await fetchQuota(secret: secret)
    }

    func fetchQuota(account: Account, secret: String, forceRefresh: Bool) async throws -> QuotaSnapshot {
        _ = forceRefresh
        return try await fetchQuota(account: account, secret: secret)
    }

    func refreshSecretIfNeeded(_ secret: String) async throws -> String {
        secret
    }

    func refreshSecretAfterAuthenticationFailure(_ secret: String) async throws -> String? {
        _ = secret
        return nil
    }

    func persistRefreshedSecret(_ secret: String, for account: Account, isActive: Bool) async throws {
        _ = secret
        _ = account
        _ = isActive
    }

    func isAuthenticationFailure(_ error: Error) -> Bool {
        _ = error
        return false
    }

    func accountIdentity(from secret: String) -> String? {
        suggestAccountName(from: secret)
    }

    func accountIdentityAliases(from secret: String) -> [String] {
        accountIdentity(from: secret).map { [$0] } ?? []
    }

    func suggestAccountName(from secret: String) -> String? {
        _ = secret
        return nil
    }

    func deleteAccountArtifacts(account: Account) async throws {
        _ = account
    }
}

enum ProviderError: LocalizedError {
    case missingFile(path: String)
    case invalidCredentials
    case unsupported(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let path):
            return "缺少文件: \(path)"
        case .invalidCredentials:
            return "凭据格式无效"
        case .unsupported(let message):
            return message
        case .network(let message):
            return message
        }
    }
}
