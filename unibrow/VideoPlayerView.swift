import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let smbStore: SMBStore
    let item: SMBItem

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage = ""
    @State private var tempURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onAppear {
                            player.play()
                        }
                } else if !errorMessage.isEmpty {
                    ContentUnavailableView(
                        "Unable to Play Video",
                        systemImage: "video.slash",
                        description: Text(errorMessage)
                    )
                    .foregroundStyle(.white)
                } else {
                    ProgressView("Loading Video...")
                        .tint(.white)
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        player?.pause()
                        cleanupTempFile()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .task {
                await loadVideo()
            }
            .onDisappear {
                player?.pause()
                cleanupTempFile()
            }
        }
    }

    private func loadVideo() async {
        do {
            let data = try await smbStore.loadFileData(path: item.path)

            let fileExtension = (item.name as NSString).pathExtension
            let tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension.isEmpty ? "mp4" : fileExtension)

            try data.write(to: tempFileURL, options: .atomic)

            await MainActor.run {
                tempURL = tempFileURL
                player = AVPlayer(url: tempFileURL)
                player?.play()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cleanupTempFile() {
        guard let tempURL else { return }
        try? FileManager.default.removeItem(at: tempURL)
        self.tempURL = nil
    }
}
