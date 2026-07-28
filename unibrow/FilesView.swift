import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var savedConnectionsStore: SavedConnectionsStore

    var body: some View {
        NavigationStack {
            List {
                Section("Saved Connections") {
                    if savedConnectionsStore.connections.isEmpty {
                        ContentUnavailableView(
                            "No Connections",
                            systemImage: "externaldrive.badge.questionmark",
                            description: Text("Add a connection in Settings first.")
                        )
                    } else {
                        ForEach(savedConnectionsStore.connections) { connection in
                            NavigationLink {
                                ConnectionFilesView(connection: connection)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(connection.name)

                                    Text("\(connection.host)/\(connection.share)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Files")
        }
    }
}
