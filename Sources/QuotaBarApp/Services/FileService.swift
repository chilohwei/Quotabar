import Foundation

struct FileService {
    func expand(path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: expand(path: path))
    }

    func directoryExists(at path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: expand(path: path), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func readText(at path: String) throws -> String {
        let expanded = expand(path: path)
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw ProviderError.missingFile(path: expanded)
        }
        return try String(contentsOfFile: expanded, encoding: .utf8)
    }

    func writeText(_ content: String, to path: String) throws {
        let expanded = expand(path: path)
        let url = URL(fileURLWithPath: expanded)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func createDirectoryIfNeeded(at path: String) throws {
        let expanded = expand(path: path)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: expanded), withIntermediateDirectories: true)
    }

    func removeItemIfExists(at path: String) throws {
        let expanded = expand(path: path)
        guard FileManager.default.fileExists(atPath: expanded) else { return }
        try FileManager.default.removeItem(at: URL(fileURLWithPath: expanded))
    }

    func copyItemReplacing(from sourcePath: String, to targetPath: String) throws {
        let sourceExpanded = expand(path: sourcePath)
        let targetExpanded = expand(path: targetPath)

        guard FileManager.default.fileExists(atPath: sourceExpanded) else {
            throw ProviderError.missingFile(path: sourceExpanded)
        }

        try removeItemIfExists(at: targetExpanded)

        let targetURL = URL(fileURLWithPath: targetExpanded)
        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourceExpanded), to: targetURL)
    }

}
