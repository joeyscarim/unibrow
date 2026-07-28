import SwiftUI
import UIKit

struct FilesView: View {
    let smbStore: SMBStore

    @State private var previewImage: UIImage?
    @State private var previewTitle = ""
    @State private var previewError = ""
    @State private var showGrid = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

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
                        .padding()
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
                                Label("..", systemImage: "arrow.up.backward.folder")
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
        .sheet(isPresented: Binding(
            get: { previewImage != nil },
            set: { if !$0 { previewImage = nil } }
        )) {
            if let previewImage {
                NavigationStack {
                    VStack {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                    .navigationTitle(previewTitle)
                    .navigationBarTitleDisplayMode(.inline)
                }
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
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 90)

                    Image(systemName: "arrow.up.backward.folder.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.blue)
                }

                Text("..")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func gridCell(for item: SMBItem) -> some View {
        Button {
            handleTap(on: item)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 90)

                    if item.isDirectory {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.blue)
                    } else if let image = smbStore.thumbnails[item.path] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 90)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if smbStore.isImageFile(item.name) {
                        ProgressView()
                            .task {
                                await smbStore.loadThumbnail(for: item)
                            }
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
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

        if smbStore.isImageFile(item.name) {
            Task {
                do {
                    let data = try await smbStore.loadFileData(path: item.path)

                    guard let image = UIImage(data: data) else {
                        previewError = "Could not decode image data."
                        return
                    }

                    previewTitle = item.name
                    previewImage = image
                } catch {
                    previewError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FilesView(smbStore: SMBStore())
    }
}
