import SwiftUI
import UIKit

struct ImageGalleryView: View {
    let smbStore: SMBStore
    let allItems: [SMBItem]
    let selectedItem: SMBItem

    @Environment(\.dismiss) private var dismiss
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var selectedIndex: Int = 0
    @State private var dismissDragOffset: CGFloat = 0

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
                    PagingImageViewer(
                        items: imageItems,
                        selectedIndex: $selectedIndex,
                        loadedImages: $loadedImages,
                        smbStore: smbStore,
                        onDismissDrag: { offset in
                            dismissDragOffset = offset
                        },
                        onDismissDragEnded: { translation, predicted in
                            if translation > 120 || predicted > 220 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    dismissDragOffset = 0
                                }
                            }
                        }
                    )
                    .onAppear {
                        if let index = imageItems.firstIndex(where: { $0.path == selectedItem.path }) {
                            selectedIndex = index
                        } else {
                            selectedIndex = 0
                        }
                    }
                }
            }
            .offset(y: dismissDragOffset)
            .opacity(1 - min(dismissDragOffset / 500, 0.45))
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
}

private struct PagingImageViewer: View {
    let items: [SMBItem]
    @Binding var selectedIndex: Int
    @Binding var loadedImages: [String: UIImage]
    let smbStore: SMBStore
    let onDismissDrag: (CGFloat) -> Void
    let onDismissDragEnded: (_ translation: CGFloat, _ predicted: CGFloat) -> Void

    @State private var pageDragOffset: CGFloat = 0
    @State private var currentScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ZStack {
                        if let image = loadedImages[item.path] {
                            ZoomablePagedImageView(
                                image: image,
                                currentScale: scaleBinding(for: index),
                                onPageDrag: { translation in
                                    if currentScale <= 1.01 {
                                        pageDragOffset = translation
                                    }
                                },
                                onPageDragEnded: { translation, predicted in
                                    guard currentScale <= 1.01 else {
                                        pageDragOffset = 0
                                        return
                                    }

                                    let threshold = width * 0.2
                                    let predictedThreshold = width * 0.35
                                    var newIndex = selectedIndex

                                    if translation < -threshold || predicted < -predictedThreshold {
                                        newIndex = min(selectedIndex + 1, items.count - 1)
                                    } else if translation > threshold || predicted > predictedThreshold {
                                        newIndex = max(selectedIndex - 1, 0)
                                    }

                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                        selectedIndex = newIndex
                                        pageDragOffset = 0
                                    }
                                },
                                onDismissDrag: { translation in
                                    guard currentScale <= 1.01 else { return }
                                    pageDragOffset = 0
                                    onDismissDrag(translation)
                                },
                                onDismissDragEnded: { translation, predicted in
                                    guard currentScale <= 1.01 else { return }
                                    onDismissDragEnded(translation, predicted)
                                }
                            )
                        } else {
                            ProgressView()
                                .tint(.white)
                                .task {
                                    await loadImage(for: item)
                                }
                        }
                    }
                    .frame(width: width, height: proxy.size.height)
                }
            }
            .offset(x: -CGFloat(selectedIndex) * width + pageDragOffset)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedIndex)
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: pageDragOffset)
            .clipped()
        }
        .background(Color.black)
    }

    private func scaleBinding(for index: Int) -> Binding<CGFloat> {
        Binding(
            get: { index == selectedIndex ? currentScale : 1 },
            set: { newValue in
                if index == selectedIndex {
                    currentScale = newValue
                }
            }
        )
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

private struct ZoomablePagedImageView: View {
    let image: UIImage
    @Binding var currentScale: CGFloat
    let onPageDrag: (CGFloat) -> Void
    let onPageDragEnded: (_ translation: CGFloat, _ predicted: CGFloat) -> Void
    let onDismissDrag: (CGFloat) -> Void
    let onDismissDragEnded: (_ translation: CGFloat, _ predicted: CGFloat) -> Void

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(
                    width: max(proxy.size.width, 1),
                    height: max(proxy.size.height, 1)
                )
                .contentShape(Rectangle())
                .onAppear {
                    currentScale = scale
                }
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1 {
                            scale = 1
                            baseScale = 1
                            offset = .zero
                            baseOffset = .zero
                        } else {
                            scale = 2
                            baseScale = 2
                        }
                        currentScale = scale
                    }
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(baseScale * value, 1), 5)
                            currentScale = scale
                        }
                        .onEnded { value in
                            baseScale = min(max(baseScale * value, 1), 5)

                            if baseScale <= 1 {
                                withAnimation(.spring()) {
                                    scale = 1
                                    baseScale = 1
                                    offset = .zero
                                    baseOffset = .zero
                                }
                            } else {
                                scale = baseScale
                            }

                            currentScale = scale
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.01 {
                                offset = CGSize(
                                    width: baseOffset.width + value.translation.width,
                                    height: baseOffset.height + value.translation.height
                                )
                            } else if isDismissDrag(value.translation) {
                                onDismissDrag(value.translation.height)
                            } else {
                                onPageDrag(value.translation.width)
                            }
                        }
                        .onEnded { value in
                            if scale > 1.01 {
                                baseOffset = offset
                            } else if isDismissDrag(value.translation) {
                                onDismissDragEnded(
                                    value.translation.height,
                                    value.predictedEndTranslation.height
                                )
                            } else {
                                onPageDragEnded(
                                    value.translation.width,
                                    value.predictedEndTranslation.width
                                )
                            }
                        }
                )
                .background(Color.black)
        }
    }

    private func isDismissDrag(_ translation: CGSize) -> Bool {
        translation.height > 0 && abs(translation.height) > abs(translation.width)
    }
}
