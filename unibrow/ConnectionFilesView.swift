import SwiftUI

struct ConnectionFilesView: View {
    @EnvironmentObject private var smbStore: SMBStore
    let connection: SavedConnection

    @State private var previewError = ""
    @State private var showGrid = true
    @State private var hasAttemptedConnect = false
    @State private var selectedImageItem: SMBItem?

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 90, maximum: 120), spacing: 12, alignment: .top),
        count: 3
    )

    var body: some View {
        Group {
            if smbStore.isLoading && !hasAttemptedConnect {
                ProgressView("Connecting...")
            } else if !smbStore.isConnected {
                ContentUnavailableView(
                    "Not Connected",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text(
                        previewError.isEmpty
                        ? "Connecting to \(connection.name)…"
                        : previewError
                    )
                )
            } else {
                browserContent
            }
        }
        .navigationTitle(connection.name)
        .fullScreenCover(item: $selectedImageItem) { tappedItem in
            ImageGalleryView(
                smbStore: smbStore,
                allItems: smbStore.items,
                selectedItem: tappedItem
            )
        }
        .task {
            guard !hasAttemptedConnect else { return }
            hasAttemptedConnect = true

            do {
                try await smbStore.connect(using: connection)
            } catch {
                previewError = error.localizedDescription
            }
        }
        .alert("Error", isPresented: Binding(
            get: { !previewError.isEmpty },
            set: { if !$0 { previewError = "" } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(previewError)
        }
    }

    @ViewBuilder
    private var browserContent: some View {
        if showGrid {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    if smbStore.currentPath != "/" {
                        upCell
                    }

                    ForEach(smbStore.items) { item in
                        gridCell(for: item)
                    }
                }
                .padding(12)
            }
            .overlay {
                if smbStore.isLoading {
                    ProgressView("Loading...")
                }
            }
        } else {
            List {
                if smbStore.currentPath != "/" {
                    Button {
                        Task {
                            do {
                                try await smbStore.goUp()
                            } catch {
                                previewError = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("..", systemImage: "arrowshape.turn.up.backward.fill")
                    }
                }

                ForEach(smbStore.items) { item in
                    Button {
                        handleTap(on: item)
                    } label: {
                        HStack {
                            leadingIcon(for: item)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)

                                Text(item.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if item.isDirectory {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if smbStore.isLoading {
                    ProgressView("Loading...")
                }
            }
        }
    }

    private var upCell: some View {
        Button {
            Task {
                do {
                    try await smbStore.goUp()
                } catch {
                    previewError = error.localizedDescription
                }
            }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "arrowshape.turn.up.backward.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                    }

                Text("..")
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }

    private func gridCell(for item: SMBItem) -> some View {
        Button {
            handleTap(on: item)
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if item.isDirectory {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.blue)
                        } else if let image = smbStore.thumbnails[item.path] {
                            GeometryReader { proxy in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .clipped()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if smbStore.isImageFile(item.name) {
                            ProgressView()
                                .task {
                                    await smbStore.loadThumbnail(for: item)
                                }
                        } else {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                        }
                    }

                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func leadingIcon(for item: SMBItem) -> some View {
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
        } else if let image = smbStore.thumbnails[item.path] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if smbStore.isImageFile(item.name) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 40, height: 40)
                .overlay {
                    ProgressView()
                        .task {
                            await smbStore.loadThumbnail(for: item)
                        }
                }
        } else {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func handleTap(on item: SMBItem) {
        if item.isDirectory {
            Task {
                do {
                    try await smbStore.open(item)
                } catch {
                    previewError = error.localizedDescription
                }
            }
            return
        }

        guard smbStore.isImageFile(item.name) else { return }
        selectedImageItem = item
    }
}
