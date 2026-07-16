import Foundation

/// Resolves `~/Library/Application Support/Arkeys` and its subdirectories.
public enum AppSupportPaths {
    public static let directoryName = "Arkeys"

    public static func rootDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let root = base.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    public static func keymapsDirectory(fileManager: FileManager = .default) -> URL {
        let dir = rootDirectory(fileManager: fileManager).appendingPathComponent("Keymaps", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
