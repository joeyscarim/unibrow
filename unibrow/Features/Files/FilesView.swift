import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var savedConnectionsStore: SavedConnectionsStore
    @EnvironmentObject private var smbStore: SMBStore
    @State private var navigationPath = NavigationPath()
    @State private var connectionToEdit: SavedConnection?

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                            NavigationLink(value: connection) {
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

                                Button {
                                    connectionToEdit = connection
                                } label: {
                                    Label("Edit", systemImage: "pencil")
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
            .navigationDestination(for: SavedConnection.self) { connection in
                ConnectionFilesView(connection: connection)
            }
            .sheet(item: $connectionToEdit) { connection in
                NavigationStack {
                    AddConnectionView(connectionToEdit: connection)
                }
            }
        }
        .onChange(of: navigationPath.count) { _, count in
            if count == 0 {
                Task {
                    await smbStore.disconnect()
                }
            }
        }
    }
}
