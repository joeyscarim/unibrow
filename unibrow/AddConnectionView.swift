import SwiftUI

struct AddConnectionView: View {
    @EnvironmentObject private var savedConnectionsStore: SavedConnectionsStore
    @EnvironmentObject private var smbStore: SMBStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var host = ""
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""
    @State private var useEncryption = false

    @State private var resultMessage = ""
    @State private var resultIsError = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name
        case host
        case share
        case username
        case password
    }

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Connection Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .host }
            }

            Section("SMB Server") {
                TextField("Host or IP address", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .host)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .share }

                TextField("Share name", text: $share)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .share)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: $password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }

                Toggle("Use SMB3 Encryption", isOn: $useEncryption)
            }

            Section {
                Button {
                    focusedField = nil
                    testConnection()
                } label: {
                    HStack {
                        Text(smbStore.isLoading ? "Connecting..." : "Test Connection")
                        Spacer()
                        if smbStore.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(
                    smbStore.isLoading ||
                    host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    share.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button {
                    focusedField = nil
                    saveConnection()
                } label: {
                    Label("Save Connection", systemImage: "square.and.arrow.down")
                }
                .disabled(
                    host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    share.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if !resultMessage.isEmpty {
                Section("Connection Result") {
                    Label(
                        resultMessage,
                        systemImage: resultIsError ? "xmark.circle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(resultIsError ? .red : .green)
                }
            }
        }
        .navigationTitle("Add Connection")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    focusedField = nil
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
        }
    }

    private var keychainAccount: String {
        "\(trimmedHost)|\(trimmedShare)|\(trimmedUsername)"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedShare: String {
        share.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedConnectionName: String {
        if !trimmedName.isEmpty {
            return trimmedName
        }

        if trimmedHost.isEmpty {
            return ""
        }

        if trimmedShare.isEmpty {
            return trimmedHost
        }

        return "\(trimmedHost)/\(trimmedShare)"
    }

    private func saveConnection() {
        guard !trimmedHost.isEmpty, !trimmedShare.isEmpty else {
            resultMessage = "Host and share are required."
            resultIsError = true
            return
        }

        let connection = SavedConnection(
            name: resolvedConnectionName,
            host: trimmedHost,
            share: trimmedShare,
            username: trimmedUsername,
            password: password,
            useEncryption: useEncryption
        )

        KeychainService.savePassword(password, account: keychainAccount)
        savedConnectionsStore.add(connection)
        dismiss()
    }

    private func testConnection() {
        resultMessage = ""

        let connection = SMBConnection(
            host: trimmedHost,
            share: trimmedShare,
            username: trimmedUsername,
            password: password,
            useEncryption: useEncryption
        )

        Task {
            do {
                try await smbStore.connect(connection)
                KeychainService.savePassword(password, account: keychainAccount)

                await MainActor.run {
                    resultMessage = "Connected successfully. Credentials saved securely."
                    resultIsError = false
                }
            } catch {
                await MainActor.run {
                    resultMessage = error.localizedDescription
                    resultIsError = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddConnectionView()
            .environmentObject(SMBStore())
            .environmentObject(SavedConnectionsStore())
    }
}
