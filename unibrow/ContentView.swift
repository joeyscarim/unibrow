import SwiftUI

struct ContentView: View {
    @State private var smbStore = SMBStore()

    var body: some View {
        TabView {
            NavigationStack {
                FilesView(smbStore: smbStore)
            }
            .tabItem {
                Label("Files", systemImage: "folder")
            }

            NavigationStack {
                SettingsView(smbStore: smbStore)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    ContentView()
}
