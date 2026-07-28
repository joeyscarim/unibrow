import Foundation

struct SavedConnection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var share: String
    var username: String
    var password: String

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        share: String,
        username: String,
        password: String
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.share = share
        self.username = username
        self.password = password
    }
}
