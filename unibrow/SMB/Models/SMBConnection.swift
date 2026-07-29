import Foundation

struct SMBConnection {
    let host: String
    let share: String
    let username: String
    let password: String
    var useEncryption: Bool = false
}
