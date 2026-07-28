import Foundation
import Combine
import SwiftUI
@MainActor
final class SavedConnectionsStore: ObservableObject {
    @Published var connections: [SavedConnection] = [] {
        didSet {
            save()
        }
    }

    private let storageKey = "saved_connections"

    init() {
        load()
    }

    func add(_ connection: SavedConnection) {
        connections.append(connection)
    }

    func update(_ connection: SavedConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
    }

    func delete(at offsets: IndexSet) {
        connections.remove(atOffsets: offsets)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    func delete(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        save()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([SavedConnection].self, from: data)
        else {
            connections = []
            return
        }

        connections = decoded
    }
}
