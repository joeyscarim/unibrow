import SwiftUI

struct ConnectionFilesView: View {
    @EnvironmentObject private var smbStore: SMBStore
    let connection: SavedConnection

    @State private var showGrid = true
    @State private var phase: ConnectionPhase = .connecting

    private enum ConnectionPhase: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .connecting:
                ProgressView("Connecting...")

            case .connected:
                SMBDirectoryView(
                    path: "/",
                    title: connection.name,
                    showGrid: $showGrid
                )
                .navigationDestination(for: SMBDirectoryDestination.self) { destination in
                    SMBDirectoryView(
                        path: destination.path,
                        title: destination.title,
                        showGrid: $showGrid
                    )
                }

            case .failed(let message):
                ContentUnavailableView(
                    "Not Connected",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text(message)
                )
            }
        }
        .task(id: connection.id) {
            if smbStore.isActiveConnection(connection) {
                phase = .connected
                return
            }

            phase = .connecting

            do {
                try await smbStore.connect(using: connection)
                guard !Task.isCancelled else { return }
                phase = .connected
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
