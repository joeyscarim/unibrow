import Foundation

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
