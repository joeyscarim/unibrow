import SwiftUI

struct FilesView: View {
    let smbStore: SMBStore

    var body: some View {
        NavigationStack {
            List {
                Section("Saved Connections") {
                    // Temporary: your current/single saved connection row
                    NavigationLink {
                        ConnectionFilesView(smbStore: smbStore)
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("My SMB Connection")

                                Text(smbStore.currentPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if smbStore.isConnected {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Files")
        }
    }
}
