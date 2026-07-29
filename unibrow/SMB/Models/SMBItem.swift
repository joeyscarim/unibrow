import Foundation

struct SMBItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
}
