import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var savedConnectionsStore: SavedConnectionsStore

    var body: some View {
        List {
                Section("Saved Connections") {
                    if savedConnectionsStore.connections.isEmpty {
                        ContentUnavailableView(
                            "No Connections",
                            systemImage: "externaldrive.badge.questionmark",
                            description: Text("Tap + to add an SMB connection.")
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    savedConnectionsStore.delete(connection)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AddConnectionView()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
    }
}
