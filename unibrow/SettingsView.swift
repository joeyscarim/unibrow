import SwiftUI

struct SettingsView: View {
    let smbStore: SMBStore

    var body: some View {
        NavigationStack {
            List {
                Section("Connections") {
                    NavigationLink {
                        AddConnectionView()

                    } label: {
                        Label("Add Connection", systemImage: "plus.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }
}
