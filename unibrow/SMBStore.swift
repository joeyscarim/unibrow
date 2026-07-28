import Foundation
import AMSMB2
import UIKit
import Combine
import AVFoundation

struct SMBConnection {
    let host: String
    let share: String
    let username: String
    let password: String
}

struct SMBItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
}

enum SMBStoreError: LocalizedError {
    case invalidServerURL
    case emptyShare
    case couldNotCreateClient
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid server address, such as 192.168.1.50 or mac-mini.local."
        case .emptyShare:
            return "Enter an SMB share name."
        case .couldNotCreateClient:
            return "Could not create an SMB connection."
        case .notConnected:
            return "Not connected to an SMB share."
        }
    }
}

@MainActor
final class SMBStore: ObservableObject {
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var connectionSummary = ""
    @Published var currentPath = "/"
    @Published var items: [SMBItem] = []
    @Published var thumbnails: [String: UIImage] = [:]

    private var client: SMB2Manager?

    private let thumbnailMemoryCache = NSCache<NSString, UIImage>()
    private var loadingThumbnailPaths = Set<String>()
    private let thumbnailFileManager = FileManager.default

    private var thumbnailCacheDirectory: URL {
        let url = URL.cachesDirectory.appendingPathComponent("SMBThumbnailCache", isDirectory: true)
        if !thumbnailFileManager.fileExists(atPath: url.path) {
            try? thumbnailFileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func connect(using savedConnection: SavedConnection) async throws {
        let cleanedHost = savedConnection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedShare = savedConnection.share.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedUsername = savedConnection.username.trimmingCharacters(in: .whitespacesAndNewlines)

        let keychainAccount = "\(cleanedHost)|\(cleanedShare)|\(cleanedUsername)"
        let resolvedPassword = KeychainService.loadPassword(account: keychainAccount)

        let connection = SMBConnection(
            host: cleanedHost,
            share: cleanedShare,
            username: cleanedUsername,
            password: resolvedPassword
        )

        try await connect(connection)
    }

    func connect(_ connection: SMBConnection) async throws {
        let cleanedHost = connection.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "smb://", with: "")

        guard !cleanedHost.isEmpty,
              let serverURL = URL(string: "smb://\(cleanedHost)") else {
            throw SMBStoreError.invalidServerURL
        }

        let cleanedShare = connection.share
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedShare.isEmpty else {
            throw SMBStoreError.emptyShare
        }

        let cleanedUsername = connection.username
            .trimmingCharacters(in: .whitespacesAndNewlines)

        await disconnect()

        let credential = URLCredential(
            user: cleanedUsername,
            password: connection.password,
            persistence: .forSession
        )

        guard let newClient = SMB2Manager(url: serverURL, credential: credential) else {
            throw SMBStoreError.couldNotCreateClient
        }

        isLoading = true
        defer { isLoading = false }

        try await newClient.connectShare(name: cleanedShare)

        client = newClient
        isConnected = true
        currentPath = "/"
        connectionSummary = "\(cleanedHost)/\(cleanedShare)"
        thumbnails = [:]

        try await loadDirectory(path: "/")
    }

    func disconnect() async {
        do {
            try await client?.disconnectShare()
        } catch {
        }

        client = nil
        isConnected = false
        currentPath = "/"
        connectionSummary = ""
        items = []
        thumbnails = [:]
        loadingThumbnailPaths.removeAll()
    }

    func loadDirectory(path: String) async throws {
        guard let client else {
            throw SMBStoreError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        let results = try await client.contentsOfDirectory(atPath: path)

        let mapped: [SMBItem] = results.compactMap { entry in
            guard let name = entry[.nameKey] as? String,
                  let entryPath = entry[.pathKey] as? String,
                  let resourceType = entry[.fileResourceTypeKey] as? URLFileResourceType
            else {
                return nil
            }

            if name == "." || name == ".." {
                return nil
            }

            return SMBItem(
                id: entryPath,
                name: name,
                path: entryPath,
                isDirectory: resourceType == .directory,
                size: entry[.fileSizeKey] as? Int64
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        items = mapped
        currentPath = path
    }

    func open(_ item: SMBItem) async throws {
        guard item.isDirectory else { return }
        thumbnails = [:]
        try await loadDirectory(path: item.path)
    }

    func goUp() async throws {
        guard currentPath != "/" else { return }

        let normalized = currentPath.hasSuffix("/") ? String(currentPath.dropLast()) : currentPath
        let parent = (normalized as NSString).deletingLastPathComponent
        let nextPath = parent.isEmpty ? "/" : parent

        thumbnails = [:]
        try await loadDirectory(path: nextPath)
    }

    func loadFileData(path: String) async throws -> Data {
        guard let client else {
            throw SMBStoreError.notConnected
        }

        return try await client.contents(atPath: path)
    }

    func loadThumbnail(for item: SMBItem) async {
        guard thumbnails[item.path] == nil else { return }
        guard !loadingThumbnailPaths.contains(item.path) else { return }

        loadingThumbnailPaths.insert(item.path)
        defer { loadingThumbnailPaths.remove(item.path) }

        let memoryKey = item.path as NSString

        if let cachedImage = thumbnailMemoryCache.object(forKey: memoryKey) {
            thumbnails[item.path] = cachedImage
            return
        }

        if let diskImage = cachedThumbnailFromDisk(for: item) {
            thumbnailMemoryCache.setObject(diskImage, forKey: memoryKey)
            thumbnails[item.path] = diskImage
            return
        }

        if isImageFile(item.name) {
            do {
                let data = try await loadFileData(path: item.path)
                if let image = UIImage(data: data) {
                    thumbnailMemoryCache.setObject(image, forKey: memoryKey)
                    saveThumbnailToDisk(image, for: item)
                    thumbnails[item.path] = image
                }
            } catch {
            }
            return
        }

        if isVideoFile(item.name) {
            var tempURL: URL?

            do {
                let data = try await loadFileData(path: item.path)
                let fileExtension = (item.name as NSString).pathExtension

                let localTempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension.isEmpty ? "mp4" : fileExtension)

                tempURL = localTempURL
                try data.write(to: localTempURL, options: .atomic)

                let asset = AVURLAsset(url: localTempURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 400)

                let cgImage = try generator.copyCGImage(
                    at: CMTime(seconds: 1, preferredTimescale: 600),
                    actualTime: nil
                )

                let image = UIImage(cgImage: cgImage)

                thumbnailMemoryCache.setObject(image, forKey: memoryKey)
                saveThumbnailToDisk(image, for: item)
                thumbnails[item.path] = image
            } catch {
            }

            if let tempURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }

    func isImageFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".png")
            || lower.hasSuffix(".jpg")
            || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".gif")
            || lower.hasSuffix(".webp")
    }

    func isVideoFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".mp4")
            || lower.hasSuffix(".mov")
            || lower.hasSuffix(".m4v")
    }
    
    func clearThumbnailCache() {
        thumbnails = [:]
        loadingThumbnailPaths.removeAll()
        thumbnailMemoryCache.removeAllObjects()

        if thumbnailFileManager.fileExists(atPath: thumbnailCacheDirectory.path) {
            try? thumbnailFileManager.removeItem(at: thumbnailCacheDirectory)
        }

        try? thumbnailFileManager.createDirectory(
            at: thumbnailCacheDirectory,
            withIntermediateDirectories: true
        )
    }
    
    func thumbnailCacheSizeInBytes() -> Int64 {
        let url = thumbnailCacheDirectory

        guard thumbnailFileManager.fileExists(atPath: url.path),
              let enumerator = thumbnailFileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return 0
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                  values.isDirectory != true
            else {
                continue
            }

            totalSize += Int64(values.fileSize ?? 0)
        }

        return totalSize
    }

    func formattedThumbnailCacheSize() -> String {
        ByteCountFormatter.string(
            fromByteCount: thumbnailCacheSizeInBytes(),
            countStyle: .file
        )
    }

    private func thumbnailCacheKey(for item: SMBItem) -> String {
        let raw = "\(item.path.lowercased())|\(item.size ?? 0)"
        return Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    private func thumbnailCacheURL(for item: SMBItem) -> URL {
        thumbnailCacheDirectory
            .appendingPathComponent(thumbnailCacheKey(for: item))
            .appendingPathExtension("jpg")
    }

    private func cachedThumbnailFromDisk(for item: SMBItem) -> UIImage? {
        let url = thumbnailCacheURL(for: item)
        guard thumbnailFileManager.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func saveThumbnailToDisk(_ image: UIImage, for item: SMBItem) {
        let url = thumbnailCacheURL(for: item)
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
