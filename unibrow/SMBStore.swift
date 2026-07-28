import Foundation
import AMSMB2
import UIKit
import Combine

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
        guard isImageFile(item.name) else { return }

        do {
            let data = try await loadFileData(path: item.path)
            if let image = UIImage(data: data) {
                thumbnails[item.path] = image
            }
        } catch {
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
}
