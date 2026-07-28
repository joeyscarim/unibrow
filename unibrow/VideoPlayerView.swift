import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let smbStore: SMBStore
    let item: SMBItem

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage = ""
    @State private var preparedURL: URL?

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
                        cleanupPreparedVideo()
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
                cleanupPreparedVideo()
            }
        }
    }

    private func loadVideo() async {
        do {
            let url = try await smbStore.prepareVideoForPlayback(for: item)

            await MainActor.run {
                preparedURL = url
                player = AVPlayer(url: url)
                player?.play()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cleanupPreparedVideo() {
        guard let preparedURL else { return }
        smbStore.cleanupPreparedVideo(at: preparedURL)
        self.preparedURL = nil
    }
}
