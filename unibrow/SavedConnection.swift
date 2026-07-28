import Foundation

struct SavedConnection: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var share: String
    var username: String
    var password: String
    var useEncryption: Bool

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        share: String,
        username: String,
        password: String,
        useEncryption: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.share = share
        self.username = username
        self.password = password
        self.useEncryption = useEncryption
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        share = try container.decode(String.self, forKey: .share)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        useEncryption = try container.decodeIfPresent(Bool.self, forKey: .useEncryption) ?? false
    }
}
