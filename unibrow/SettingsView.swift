import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var smbStore: SMBStore

    @State private var showingClearThumbnailCacheConfirmation = false
    @State private var thumbnailCacheSize = "—"
    @State private var isClearingCache = false

    var body: some View {
        NavigationStack {
            List {
                Section("Browsing") {
                    Toggle(isOn: Binding(
                        get: { smbStore.hideHiddenFiles },
                        set: { smbStore.hideHiddenFiles = $0 }
                    )) {
                        Label("Hide Hidden Files", systemImage: "eye.slash")
                    }
                }

                Section("Storage") {
                    HStack {
                        Label("Thumbnail Cache", systemImage: "internaldrive")
                        Spacer()
                        if isClearingCache {
                            ProgressView()
                        } else {
                            Text(thumbnailCacheSize)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showingClearThumbnailCacheConfirmation = true
                    } label: {
                        Label("Clear Thumbnail Cache", systemImage: "trash")
                    }
                    .disabled(isClearingCache)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .task {
                await refreshCacheSize()
            }
            .alert("Clear Thumbnail Cache?", isPresented: $showingClearThumbnailCacheConfirmation) {
                Button("Clear Cache", role: .destructive) {
                    Task {
                        isClearingCache = true
                        await smbStore.clearThumbnailCache()
                        await refreshCacheSize()
                        isClearingCache = false
                    }
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes cached image and video thumbnails. They will be regenerated as needed.")
            }
        }
    }

    private func refreshCacheSize() async {
        thumbnailCacheSize = await smbStore.formattedThumbnailCacheSize()
    }
}
