import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var smbStore: SMBStore

    @State private var showingClearThumbnailCacheConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Connections") {
                    NavigationLink {
                        AddConnectionView()
                    } label: {
                        Label("Add Connection", systemImage: "plus.circle")
                    }
                }

                Section("Storage") {
                    Button(role: .destructive) {
                        showingClearThumbnailCacheConfirmation = true
                    } label: {
                        Label("Clear Thumbnail Cache", systemImage: "trash")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Clear thumbnail cache?",
                isPresented: $showingClearThumbnailCacheConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Cache", role: .destructive) {
                    smbStore.clearThumbnailCache()
                }

                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text("This removes cached image and video thumbnails. They will be regenerated as needed.")
            }
        }
    }
}
