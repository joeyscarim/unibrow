import SwiftUI

struct SMBDirectoryDestination: Hashable {
    let path: String
    let title: String
}

struct SMBDirectoryView: View {
    @EnvironmentObject private var smbStore: SMBStore

    let path: String
    let title: String
    @Binding var showGrid: Bool

    @State private var directoryItems: [SMBItem] = []
    @State private var isContentReady = false
    @State private var selectedVideoItem: SMBItem?
    @State private var previewError = ""
    @State private var selectedImageItem: SMBItem?

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 90, maximum: 120), spacing: 12, alignment: .top),
        count: 3
    )

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isContentReady {
                browserContent
            }
        }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "viewMode", placement: .topBarTrailing) {
                    ViewModeToolbarButton(showGrid: $showGrid)
                }
            }
            .fullScreenCover(item: $selectedImageItem) { tappedItem in
                ImageGalleryView(
                    smbStore: smbStore,
                    allItems: directoryItems,
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
                await loadDirectory()
            }
            .onChange(of: smbStore.hideHiddenFiles) { _, _ in
                Task {
                    await loadDirectory()
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
                    ForEach(directoryItems) { item in
                        gridRow(for: item)
                    }
                }
                .padding(12)
            }
        } else {
            List(directoryItems) { item in
                listRow(for: item)
            }
        }
    }

    private func loadDirectory() async {
        isContentReady = false

        do {
            let items = try await smbStore.directoryItems(at: path)
            guard !Task.isCancelled else { return }

            await smbStore.loadFolderItemCounts(for: items)
            guard !Task.isCancelled else { return }

            directoryItems = items
            isContentReady = true
        } catch {
            guard !Task.isCancelled else { return }
            previewError = error.localizedDescription
            isContentReady = true
        }
    }

    @ViewBuilder
    private func gridRow(for item: SMBItem) -> some View {
        if item.isDirectory {
            NavigationLink(value: SMBDirectoryDestination(path: item.path, title: item.name)) {
                gridCellContent(for: item)
            }
            .buttonStyle(.plain)
            .task(id: item.id) {
                await smbStore.loadFolderItemCount(for: item)
            }
        } else {
            Button {
                handleTap(on: item)
            } label: {
                gridCellContent(for: item)
            }
            .buttonStyle(.plain)
            .task(id: item.id) {
                guard smbStore.isImageFile(item.name) || smbStore.isVideoFile(item.name) else { return }
                await smbStore.loadThumbnail(for: item)
            }
        }
    }

    @ViewBuilder
    private func listRow(for item: SMBItem) -> some View {
        if item.isDirectory {
            NavigationLink(value: SMBDirectoryDestination(path: item.path, title: item.name)) {
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

    @ViewBuilder
    private func gridCellContent(for item: SMBItem) -> some View {
        if item.isDirectory {
            VStack(spacing: 4) {
                filesAppFolderIcon(for: item, size: 76)
                    .padding(.top, 8)

                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                FolderItemCountLabel(item: item)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                thumbnailContent(for: item, style: .grid)

                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func listRowContent(for item: SMBItem) -> some View {
        HStack {
            thumbnailContent(for: item, style: .list)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)

                if item.isDirectory {
                    FolderItemCountLabel(item: item)
                } else {
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .task(id: item.id) {
            if item.isDirectory {
                await smbStore.loadFolderItemCount(for: item)
            } else if smbStore.isImageFile(item.name) || smbStore.isVideoFile(item.name) {
                await smbStore.loadThumbnail(for: item)
            }
        }
    }

    private enum ThumbnailStyle {
        case grid
        case list

        var maxWidth: CGFloat {
            switch self {
            case .grid: 120
            case .list: 40
            }
        }

        var maxHeight: CGFloat {
            switch self {
            case .grid: 120
            case .list: 40
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .grid: 12
            case .list: 8
            }
        }

        var playButtonSize: CGFloat {
            switch self {
            case .grid: 28
            case .list: 14
            }
        }
    }

    @ViewBuilder
    private func thumbnailContent(for item: SMBItem, style: ThumbnailStyle) -> some View {
        if item.isDirectory {
            filesAppFolderIcon(for: item, size: style == .grid ? 76 : 34)

        } else if let image = smbStore.thumbnail(for: item) {
            AspectFitThumbnail(
                image: image,
                maxWidth: style.maxWidth,
                maxHeight: style.maxHeight,
                cornerRadius: style.cornerRadius,
                showsPlayButton: smbStore.isVideoFile(item.name),
                playButtonSize: style.playButtonSize
            )
            .frame(maxWidth: style == .grid ? .infinity : nil)

        } else if smbStore.isImageFile(item.name) || smbStore.isVideoFile(item.name) {
            ZStack {
                ProgressView()

                if smbStore.isVideoFile(item.name) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: style.playButtonSize))
                        .foregroundStyle(.white)
                        .shadow(radius: style == .grid ? 4 : 2)
                }
            }
            .frame(maxWidth: style.maxWidth, maxHeight: style.maxHeight)
            .frame(maxWidth: style == .grid ? .infinity : nil)

        } else {
            Image(systemName: "doc.fill")
                .font(.system(size: style == .grid ? 30 : 20))
                .foregroundStyle(.secondary)
        }
    }

    private func filesAppFolderIcon(for item: SMBItem, size: CGFloat) -> some View {
        let count = smbStore.folderItemCounts[item.path]
        let isFull = (count ?? 0) > 0

        return Image(isFull ? "FolderIconFull" : "FolderIconEmpty")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.15), value: isFull)
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

private struct AspectFitThumbnail: View {
    let image: UIImage
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let cornerRadius: CGFloat
    let showsPlayButton: Bool
    let playButtonSize: CGFloat

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            if showsPlayButton {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: playButtonSize))
                    .foregroundStyle(.white)
                    .shadow(radius: playButtonSize > 20 ? 4 : 2)
            }
        }
    }
}

private struct ViewModeToolbarButton: View {
    @Binding var showGrid: Bool

    var body: some View {
        Button {
            showGrid.toggle()
        } label: {
            Image(systemName: showGrid ? "list.bullet" : "square.grid.2x2")
        }
        .accessibilityLabel(showGrid ? "Show list view" : "Show grid view")
    }
}

private struct FolderItemCountLabel: View {
    @EnvironmentObject private var smbStore: SMBStore
    let item: SMBItem

    private var label: String? {
        smbStore.folderItemCountLabel(for: item.path)
    }

    var body: some View {
        Text(label ?? "0 items")
            .font(.caption)
            .foregroundStyle(label == nil ? .clear : .secondary)
            .accessibilityLabel(label ?? "Loading item count")
    }
}
