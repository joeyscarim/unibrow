import Foundation
import AMSMB2
import UIKit
import Combine
import AVFoundation
import ImageIO

struct SMBConnection {
    let host: String
    let share: String
    let username: String
    let password: String
    var useEncryption: Bool = false
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
    case thumbnailGenerationFailed

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
        case .thumbnailGenerationFailed:
            return "Could not generate a thumbnail for this file."
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
    @Published private(set) var folderItemCounts: [String: Int] = [:]

    private var client: SMB2Manager?
    private(set) var activeConnectionID: UUID?

    private let thumbnailMemoryCache = NSCache<NSString, UIImage>()
    private var loadingThumbnailPaths = Set<String>()
    private var loadingFolderCountPaths = Set<String>()
    private let thumbnailLimiter = ThumbnailLoadLimiter()

    private static let thumbnailMaxPixelSize = 200
    private static let gifFullReadMaxBytes: Int64 = 5 * 1024 * 1024
    private static let imageFullReadMaxBytes: Int64 = 50 * 1024 * 1024

    private static let imageThumbnailChunkSizes: [Int64] = [
        256 * 1024,
        512 * 1024,
        1024 * 1024,
        2 * 1024 * 1024
    ]

    private static let videoThumbnailChunkSizes: [Int64] = [
        5 * 1024 * 1024,
        15 * 1024 * 1024,
        50 * 1024 * 1024
    ]

    private static let hideHiddenFilesKey = "hideHiddenFiles"

    var hideHiddenFiles: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.hideHiddenFilesKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.hideHiddenFilesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hideHiddenFilesKey)
            folderItemCounts = [:]
            objectWillChange.send()
        }
    }

    init() {
        ProtectedFileStorage.sweepStaleTempVideos()
    }

    func connect(using savedConnection: SavedConnection) async throws {
        if isActiveConnection(savedConnection) {
            return
        }

        let cleanedHost = savedConnection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedShare = savedConnection.share.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedUsername = savedConnection.username.trimmingCharacters(in: .whitespacesAndNewlines)

        let keychainAccount = "\(cleanedHost)|\(cleanedShare)|\(cleanedUsername)"
        let resolvedPassword = KeychainService.loadPassword(account: keychainAccount)

        let connection = SMBConnection(
            host: cleanedHost,
            share: cleanedShare,
            username: cleanedUsername,
            password: resolvedPassword,
            useEncryption: savedConnection.useEncryption
        )

        try await connect(connection)
        activeConnectionID = savedConnection.id
        ensureThumbnailCacheDirectory()
    }

    func isActiveConnection(_ connection: SavedConnection) -> Bool {
        isConnected && activeConnectionID == connection.id
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

        try await newClient.connectShare(name: cleanedShare, encrypted: connection.useEncryption)

        client = newClient
        isConnected = true
        currentPath = "/"
        connectionSummary = "\(cleanedHost)/\(cleanedShare)"
    }

    func disconnect() async {
        let clientToDisconnect = client
        client = nil
        isConnected = false
        activeConnectionID = nil
        currentPath = "/"
        connectionSummary = ""
        items = []
        thumbnails = [:]
        folderItemCounts = [:]
        loadingThumbnailPaths.removeAll()
        loadingFolderCountPaths.removeAll()

        if let clientToDisconnect {
            do {
                try await clientToDisconnect.disconnectShare(gracefully: true)
            } catch {
            }
        }
    }

    func loadDirectory(path: String) async throws {
        let mapped = try await directoryItems(at: path)
        items = mapped
        currentPath = path
    }

    func directoryItems(at path: String) async throws -> [SMBItem] {
        guard let client else {
            throw SMBStoreError.notConnected
        }

        let results = try await client.contentsOfDirectory(atPath: path)
        return Self.mapDirectoryResults(results, hideHiddenFiles: hideHiddenFiles)
    }

    func folderItemCountLabel(for path: String) -> String? {
        guard let count = folderItemCounts[path] else { return nil }
        return count == 1 ? "1 item" : "\(count) items"
    }

    func loadFolderItemCount(for item: SMBItem) async {
        guard item.isDirectory else { return }
        guard folderItemCounts[item.path] == nil else { return }
        guard !loadingFolderCountPaths.contains(item.path) else { return }
        guard client != nil else { return }

        loadingFolderCountPaths.insert(item.path)
        defer { loadingFolderCountPaths.remove(item.path) }

        do {
            let items = try await directoryItems(at: item.path)
            folderItemCounts[item.path] = items.count
        } catch {
        }
    }

    private static func mapDirectoryResults(
        _ results: [[URLResourceKey: Any]],
        hideHiddenFiles: Bool
    ) -> [SMBItem] {
        results.compactMap { entry in
            guard let name = entry[.nameKey] as? String,
                  let entryPath = entry[.pathKey] as? String,
                  let resourceType = entry[.fileResourceTypeKey] as? URLFileResourceType
            else {
                return nil
            }

            if name == "." || name == ".." {
                return nil
            }

            if hideHiddenFiles {
                if name.hasPrefix(".") {
                    return nil
                }

                if let isHidden = entry[.isHiddenKey] as? Bool, isHidden {
                    return nil
                }
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
        guard client != nil else { return }

        loadingThumbnailPaths.insert(item.path)
        defer { loadingThumbnailPaths.remove(item.path) }

        let memoryKey = item.path as NSString

        if let cachedImage = thumbnailMemoryCache.object(forKey: memoryKey) {
            thumbnails[item.path] = cachedImage
            return
        }

        let cacheURL = thumbnailCacheURL(for: item)

        if let diskImage = await Self.loadThumbnailFromDisk(at: cacheURL) {
            thumbnailMemoryCache.setObject(diskImage, forKey: memoryKey)
            thumbnails[item.path] = diskImage
            return
        }

        await thumbnailLimiter.acquire()
        defer {
            Task { await thumbnailLimiter.release() }
        }

        guard client != nil else { return }

        ensureThumbnailCacheDirectory()

        if isImageFile(item.name) {
            do {
                let image = try await loadImageThumbnail(for: item, cacheURL: cacheURL)
                guard client != nil else { return }
                thumbnailMemoryCache.setObject(image, forKey: memoryKey)
                thumbnails[item.path] = image
            } catch {
            }
            return
        }

        if isVideoFile(item.name) {
            do {
                let image = try await loadVideoThumbnail(for: item, cacheURL: cacheURL)
                guard client != nil else { return }
                thumbnailMemoryCache.setObject(image, forKey: memoryKey)
                thumbnails[item.path] = image
            } catch {
            }

            return
        }
    }

    func prepareVideoForPlayback(for item: SMBItem) async throws -> URL {
        try await prepareLocalVideoFile(for: item)
    }

    func cleanupPreparedVideo(at url: URL) {
        try? FileManager.default.removeItem(at: url)
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

    private var thumbnailCacheDirectoryURL: URL {
        URL.cachesDirectory.appendingPathComponent(
            ProtectedFileStorage.thumbnailCacheDirectoryName,
            isDirectory: true
        )
    }

    private func ensureThumbnailCacheDirectory() {
        try? ProtectedFileStorage.ensureThumbnailCacheDirectory(at: thumbnailCacheDirectoryURL)
    }

    func clearThumbnailCache() async {
        thumbnails = [:]
        loadingThumbnailPaths.removeAll()
        thumbnailMemoryCache.removeAllObjects()

        let cacheURL = thumbnailCacheDirectoryURL

        await Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                try? FileManager.default.removeItem(at: cacheURL)
            }
            try? ProtectedFileStorage.ensureThumbnailCacheDirectory(at: cacheURL)
        }.value
    }

    func thumbnailCacheSizeInBytes() async -> Int64 {
        let cacheURL = thumbnailCacheDirectoryURL

        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: cacheURL.path),
                  let enumerator = FileManager.default.enumerator(
                    at: cacheURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                  )
            else {
                return Int64(0)
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
        }.value
    }

    func formattedThumbnailCacheSize() async -> String {
        let bytes = await thumbnailCacheSizeInBytes()
        return ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }

    private func prepareLocalVideoFile(for item: SMBItem) async throws -> URL {
        guard let client else {
            throw SMBStoreError.notConnected
        }

        let fileExtension = (item.name as NSString).pathExtension
        let tempFileURL = ProtectedFileStorage.makeTempVideoURL(fileExtension: fileExtension)

        try await client.downloadItem(
            atPath: item.path,
            to: tempFileURL,
            progress: nil
        )

        guard self.client != nil else {
            try? FileManager.default.removeItem(at: tempFileURL)
            throw SMBStoreError.notConnected
        }

        try ProtectedFileStorage.applyProtection(at: tempFileURL)

        return tempFileURL
    }

    private func partialFileData(for item: SMBItem, maxBytes: Int64) async throws -> Data {
        guard let client else {
            throw SMBStoreError.notConnected
        }

        let fileSize = item.size ?? 0
        let byteCount: UInt64

        if fileSize > 0 {
            byteCount = UInt64(min(maxBytes, fileSize))
        } else {
            byteCount = UInt64(maxBytes)
        }

        guard byteCount > 0 else {
            return Data()
        }

        return try await client.contents(atPath: item.path, range: 0..<byteCount)
    }

    private func loadImageThumbnail(for item: SMBItem, cacheURL: URL) async throws -> UIImage {
        if Self.imageRequiresFullFile(item.name) {
            return try await loadFullFileImageThumbnail(for: item, cacheURL: cacheURL)
        }

        let chunkSizes = Self.imageThumbnailChunkSizes(for: item)
        var lastError: Error?

        for chunkSize in chunkSizes {
            guard client != nil else {
                throw SMBStoreError.notConnected
            }

            do {
                let data = try await partialFileData(for: item, maxBytes: chunkSize)

                if let image = await Self.downsampleAndCacheImageThumbnail(from: data, cacheURL: cacheURL) {
                    return image
                }
            } catch {
                lastError = error
            }

            if let fileSize = item.size, fileSize > 0, chunkSize >= fileSize {
                break
            }
        }

        do {
            return try await loadFullFileImageThumbnail(for: item, cacheURL: cacheURL)
        } catch {
            throw lastError ?? error
        }
    }

    private func loadFullFileImageThumbnail(for item: SMBItem, cacheURL: URL) async throws -> UIImage {
        let data = try await fullFileImageData(for: item)

        if Self.isPNGFile(item.name), !Self.isCompletePNG(data) {
            throw SMBStoreError.thumbnailGenerationFailed
        }

        guard let image = await Self.downsampleAndCacheImageThumbnail(from: data, cacheURL: cacheURL) else {
            throw SMBStoreError.thumbnailGenerationFailed
        }

        return image
    }

    private func fullFileImageData(for item: SMBItem) async throws -> Data {
        if let fileSize = item.size, fileSize > 0 {
            guard fileSize <= Self.imageFullReadMaxBytes else {
                throw SMBStoreError.thumbnailGenerationFailed
            }

            return try await loadFileData(path: item.path)
        }

        return try await partialFileData(for: item, maxBytes: Self.imageFullReadMaxBytes)
    }

    private static func imageRequiresFullFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".png") || lower.hasSuffix(".webp")
    }

    private static func isPNGFile(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".png")
    }

    private nonisolated static func isCompletePNG(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }

        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard data.prefix(8) == pngSignature else { return true }

        let iendTrailer = Data([0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
        return data.suffix(12) == iendTrailer
    }

    private static func imageThumbnailChunkSizes(for item: SMBItem) -> [Int64] {
        let lower = item.name.lowercased()

        if lower.hasSuffix(".gif"),
           let fileSize = item.size,
           fileSize > 0,
           fileSize <= gifFullReadMaxBytes {
            return [fileSize]
        }

        if imageRequiresFullFile(item.name) {
            return []
        }

        return imageThumbnailChunkSizes
    }

    private func loadVideoThumbnail(for item: SMBItem, cacheURL: URL) async throws -> UIImage {
        let fileExtension = (item.name as NSString).pathExtension
        var lastError: Error?

        for chunkSize in Self.videoThumbnailChunkSizes {
            guard client != nil else {
                throw SMBStoreError.notConnected
            }

            do {
                let data = try await partialFileData(for: item, maxBytes: chunkSize)
                let image = try await Self.generateVideoThumbnail(
                    from: data,
                    fileExtension: fileExtension,
                    cacheURL: cacheURL
                )
                return image
            } catch {
                lastError = error

                if let fileSize = item.size, fileSize > 0, chunkSize >= fileSize {
                    break
                }
            }
        }

        throw lastError ?? SMBStoreError.thumbnailGenerationFailed
    }

    private static func loadThumbnailFromDisk(at url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            if let decrypted = try? ProtectedFileStorage.readEncryptedThumbnail(from: url),
               let image = UIImage(data: decrypted) {
                return image
            }

            // Legacy unencrypted JPEG cache entries.
            return UIImage(contentsOfFile: url.path)
        }.value
    }

    private static func downsampleAndCacheImageThumbnail(from data: Data, cacheURL: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            if data.count >= 8 {
                let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
                if data.prefix(8) == pngSignature, !isCompletePNG(data) {
                    return nil
                }
            }

            let sourceOptions = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ] as CFDictionary

            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
                  CGImageSourceGetCount(source) > 0
            else {
                return nil
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
            ] as CFDictionary

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
                return nil
            }

            let image = UIImage(cgImage: cgImage)

            if let jpegData = image.jpegData(compressionQuality: 0.8) {
                try? ProtectedFileStorage.writeEncryptedThumbnail(jpegData, to: cacheURL)
            }

            return image
        }.value
    }

    private static func generateVideoThumbnail(
        from data: Data,
        fileExtension: String,
        cacheURL: URL
    ) async throws -> UIImage {
        try await Task.detached(priority: .utility) {
            let tempURL = ProtectedFileStorage.makeTempVideoURL(fileExtension: fileExtension)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            try ProtectedFileStorage.writeProtectedData(data, to: tempURL)

            let asset = AVURLAsset(url: tempURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: thumbnailMaxPixelSize, height: thumbnailMaxPixelSize)

            let result = try await generator.image(
                at: CMTime(seconds: 1, preferredTimescale: 600)
            )

            let image = UIImage(cgImage: result.image)

            if let jpegData = image.jpegData(compressionQuality: 0.8) {
                try? ProtectedFileStorage.writeEncryptedThumbnail(jpegData, to: cacheURL)
            }

            return image
        }.value
    }

    private func thumbnailCacheKey(for item: SMBItem) -> String {
        let raw = "\(item.path.lowercased())|\(item.size ?? 0)"
        return Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-"
            )
    }

    private func thumbnailCacheURL(for item: SMBItem) -> URL {
        thumbnailCacheDirectoryURL
            .appendingPathComponent(thumbnailCacheKey(for: item))
            .appendingPathExtension("thumb")
    }
}

actor ThumbnailLoadLimiter {
    private var inFlight = 0
    private let limit = 3
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            inFlight = max(0, inFlight - 1)
        }
    }
}
