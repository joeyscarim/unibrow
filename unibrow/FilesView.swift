import SwiftUI
import UIKit

struct FilesView: View {
    let smbStore: SMBStore

    @State private var previewError = ""
    @State private var showGrid = true
    @State private var selectedImageItem: SMBItem?

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 90, maximum: 120), spacing: 12, alignment: .top),
        count: 3
    )

    var body: some View {
        Group {
            if !smbStore.isConnected {
                ContentUnavailableView(
                    "Not Connected",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text("Go to Settings and connect to your SMB share first.")
                )
            } else {
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
        }
        .navigationTitle("Files")
        .toolbar {
            if smbStore.isConnected {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showGrid.toggle()
                    } label: {
                        Image(systemName: showGrid ? "list.bullet" : "square.grid.3x3.fill")
                    }

                    Button {
                        Task {
                            do {
                                try await smbStore.loadDirectory(path: smbStore.currentPath)
                            } catch {
                                previewError = error.localizedDescription
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
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
        .alert("Error", isPresented: Binding(
            get: { !previewError.isEmpty },
            set: { if !$0 { previewError = "" } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(previewError)
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
                squareTile {
                    Image(systemName: "arrowshape.turn.up.backward.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                }

                Text("..")
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    private func gridCell(for item: SMBItem) -> some View {
        Button {
            handleTap(on: item)
        } label: {
            VStack(spacing: 8) {
                squareTile {
                    if item.isDirectory {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.blue)
                    } else if let image = smbStore.thumbnails[item.path] {
                        GeometryReader { proxy in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height
                                )
                                .clipped()
                        }
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
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
    }

    private func squareTile<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .clipped()
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

struct ImageGalleryView: View {
    let smbStore: SMBStore
    let allItems: [SMBItem]
    let selectedItem: SMBItem

    @Environment(\.dismiss) private var dismiss
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var selectedIndex: Int = 0

    private var imageItems: [SMBItem] {
        allItems.filter { !$0.isDirectory && smbStore.isImageFile($0.name) }
    }

    private var safeSelectedIndex: Int {
        guard !imageItems.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), imageItems.count - 1)
    }

    private var currentItem: SMBItem? {
        guard imageItems.indices.contains(safeSelectedIndex) else { return nil }
        return imageItems[safeSelectedIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if imageItems.isEmpty {
                    ContentUnavailableView(
                        "No Images",
                        systemImage: "photo",
                        description: Text("There are no images to display.")
                    )
                    .foregroundStyle(.white)
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(imageItems.enumerated()), id: \.element.id) { index, item in
                            ZStack {
                                if let image = loadedImages[item.path] {
                                    ZoomableImageView(image: image)
                                } else {
                                    ProgressView()
                                        .tint(.white)
                                        .task {
                                            await loadImage(for: item)
                                        }
                                }
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .background(Color.black)
                    .onAppear {
                        if let index = imageItems.firstIndex(where: { $0.path == selectedItem.path }) {
                            selectedIndex = index
                        } else {
                            selectedIndex = 0
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(currentItem?.name ?? "Image")
                            .foregroundStyle(.white)
                            .font(.headline)
                            .lineLimit(1)

                        Text(imageItems.isEmpty ? "0 of 0" : "\(safeSelectedIndex + 1) of \(imageItems.count)")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func loadImage(for item: SMBItem) async {
        if loadedImages[item.path] != nil { return }

        do {
            let data = try await smbStore.loadFileData(path: item.path)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    loadedImages[item.path] = image
                }
            }
        } catch {
        }
    }
}

struct ZoomableImageView: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let fittedImage = Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(
                    width: max(proxy.size.width, 1),
                    height: max(proxy.size.height, 1)
                )
                .contentShape(Rectangle())
                .background(Color.black)
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1 {
                            resetZoom()
                        } else {
                            scale = 2
                            baseScale = 2
                        }
                    }
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(baseScale * value, 1), 5)
                        }
                        .onEnded { value in
                            baseScale = min(max(baseScale * value, 1), 5)

                            if baseScale <= 1.01 {
                                withAnimation(.spring()) {
                                    resetZoom()
                                }
                            } else {
                                scale = baseScale
                            }
                        }
                )

            if scale > 1.01 {
                fittedImage.simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            baseOffset = offset
                        }
                )
            } else {
                fittedImage
                    .onChange(of: scale) { _, newValue in
                        if newValue <= 1.01 {
                            offset = .zero
                            baseOffset = .zero
                            scale = 1
                            baseScale = 1
                        }
                    }
            }
        }
    }

    private func resetZoom() {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
    }
}
