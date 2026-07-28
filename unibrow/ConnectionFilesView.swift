import SwiftUI

struct ConnectionFilesView: View {
    @EnvironmentObject private var smbStore: SMBStore
    let connection: SavedConnection

    @State private var showGrid = true
    @State private var hasAttemptedConnect = false
    @State private var previewError = ""

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
                SMBDirectoryView(
                    path: "/",
                    title: connection.name,
                    showGrid: $showGrid
                )
            }
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
}

struct SMBDirectoryView: View {
    @EnvironmentObject private var smbStore: SMBStore

    let path: String
    let title: String
    @Binding var showGrid: Bool

    @State private var selectedVideoItem: SMBItem?
    @State private var previewError = ""
    @State private var selectedImageItem: SMBItem?

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 90, maximum: 120), spacing: 12, alignment: .top),
        count: 3
    )

    var body: some View {
        browserContent
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGrid.toggle()
                    } label: {
                        Image(systemName: showGrid ? "list.bullet" : "square.grid.3x3.fill")
                    }
                }
            }
            .fullScreenCover(item: $selectedImageItem) { tappedItem in
                ImageGalleryView(
                    smbStore: smbStore,
                    allItems: smbStore.items,
                    selectedItem: tappedItem
                )
            }
            .fullScreenCover(item: $selectedVideoItem) { tappedItem in
                VideoPlayerView(
                    smbStore: smbStore,
                    item: tappedItem
                )
            }
            .task(id: path) {
                do {
                    try await smbStore.loadDirectory(path: path)
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
                    ForEach(smbStore.items) { item in
                        if item.isDirectory {
                            NavigationLink {
                                SMBDirectoryView(
                                    path: item.path,
                                    title: item.name,
                                    showGrid: $showGrid
                                )
                            } label: {
                                gridCellContent(for: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                handleTap(on: item)
                            } label: {
                                gridCellContent(for: item)
                            }
                            .buttonStyle(.plain)
                        }
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
                ForEach(smbStore.items) { item in
                    if item.isDirectory {
                        NavigationLink {
                            SMBDirectoryView(
                                path: item.path,
                                title: item.name,
                                showGrid: $showGrid
                            )
                        } label: {
                            listRowContent(for: item)
                        }
                    } else {
                        Button {
                            handleTap(on: item)
                        } label: {
                            listRowContent(for: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if smbStore.isLoading {
                    ProgressView("Loading...")
                }
            }
        }
    }

    private func gridCellContent(for item: SMBItem) -> some View {
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
                            ZStack {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .clipped()

                                if smbStore.isVideoFile(item.name) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 4)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    } else if smbStore.isImageFile(item.name) || smbStore.isVideoFile(item.name) {
                        ZStack {
                            ProgressView()
                                .task {
                                    await smbStore.loadThumbnail(for: item)
                                }

                            if smbStore.isVideoFile(item.name) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 4)
                            }
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

    private func listRowContent(for item: SMBItem) -> some View {
        HStack {
            leadingIcon(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)

                Text(item.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func leadingIcon(for item: SMBItem) -> some View {
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)

        } else if let image = smbStore.thumbnails[item.path] {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if smbStore.isVideoFile(item.name) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }

        } else if smbStore.isImageFile(item.name) || smbStore.isVideoFile(item.name) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 40, height: 40)
                .overlay {
                    ZStack {
                        ProgressView()
                            .task {
                                await smbStore.loadThumbnail(for: item)
                            }

                        if smbStore.isVideoFile(item.name) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                    }
                }

        } else {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func handleTap(on item: SMBItem) {
        if smbStore.isImageFile(item.name) {
            selectedImageItem = item
            return
        }

        if smbStore.isVideoFile(item.name) {
            selectedVideoItem = item
            return
        }
    }
}
