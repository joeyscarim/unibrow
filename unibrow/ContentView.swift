import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                FilesView()
            }
            .tabItem {
                Label("Files", systemImage: "folder")
            }

            NavigationStack {
                SettingsView()
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
