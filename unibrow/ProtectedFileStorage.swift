import Foundation

enum ProtectedFileStorage {
    static let fileProtection: FileProtectionType = .completeUnlessOpen
    static let tempVideoDirectoryName = "SMBTempVideos"
    static let thumbnailCacheDirectoryName = "SMBThumbnailCache"

    static func applyProtection(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: fileProtection],
            ofItemAtPath: url.path
        )
    }

    static func ensureDirectory(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try applyProtection(at: url)
    }

    static func writeProtectedData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try applyProtection(at: url)
    }

    static var tempVideoDirectory: URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempVideoDirectoryName, isDirectory: true)
        try? ensureDirectory(at: url)
        return url
    }

    static var thumbnailCacheDirectory: URL {
        let url = URL.cachesDirectory
            .appendingPathComponent(thumbnailCacheDirectoryName, isDirectory: true)
        try? ensureDirectory(at: url)
        return url
    }

    static func makeTempVideoURL(fileExtension: String) -> URL {
        tempVideoDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? "mp4" : fileExtension)
    }

    /// Removes leftover partial/full video files from prior sessions or crashes.
    static func sweepStaleTempVideos() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempVideoDirectoryName, isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
