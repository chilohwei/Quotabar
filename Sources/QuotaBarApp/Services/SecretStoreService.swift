import Foundation

enum SecretStoreError: LocalizedError {
    case dataEncoding
    case missingData

    var errorDescription: String? {
        switch self {
        case .dataEncoding:
            return "凭据编码失败"
        case .missingData:
            return "本地凭据不存在，请重新导入或手动添加账号"
        }
    }
}

struct SecretStoreService {
    private let fileManager = FileManager.default

    func saveSecret(_ secret: String, accountKey: String) throws {
        guard secret.data(using: .utf8) != nil else {
            throw SecretStoreError.dataEncoding
        }
        var store = try loadLegacyStore()
        store[accountKey] = secret
        try saveLegacyStore(store)
    }

    func readSecret(accountKey: String) throws -> String {
        let store = try loadLegacyStore()
        if let secret = store[accountKey] {
            return secret
        }
        throw SecretStoreError.missingData
    }

    func deleteSecret(accountKey: String) throws {
        try removeLegacySecret(accountKey: accountKey)
    }

    private func loadLegacyStore() throws -> [String: String] {
        try AppPaths.ensureDirectories()
        guard fileManager.fileExists(atPath: AppPaths.secretsFile.path) else {
            return [:]
        }
        let data = try Data(contentsOf: AppPaths.secretsFile)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func saveLegacyStore(_ store: [String: String]) throws {
        try AppPaths.ensureDirectories()
        let data = try JSONEncoder().encode(store)
        try data.write(to: AppPaths.secretsFile, options: .atomic)

        // Best effort: keep secrets file private to current user.
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.secretsFile.path)
    }

    private func removeLegacySecret(accountKey: String) throws {
        guard fileManager.fileExists(atPath: AppPaths.secretsFile.path) else {
            return
        }
        var legacy = try loadLegacyStore()
        guard legacy.removeValue(forKey: accountKey) != nil else {
            return
        }
        if legacy.isEmpty {
            try fileManager.removeItem(at: AppPaths.secretsFile)
            return
        }
        try saveLegacyStore(legacy)
    }
}
