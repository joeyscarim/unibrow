import SwiftUI

struct SettingsView: View {
    let smbStore: SMBStore

    @AppStorage("smbHost") private var host = ""
    @AppStorage("smbShare") private var share = ""
    @AppStorage("smbUsername") private var username = ""

    @State private var password = ""
    @State private var resultMessage = ""
    @State private var resultIsError = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case host
        case share
        case username
        case password
    }

    var body: some View {
        Form {
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
            }

            Section {
                Button {
                    focusedField = nil
                    testConnection()
                } label: {
                    HStack {
                        Text(smbStore.isLoading ? "Connecting..." : "Test Connection")
                        Spacer()
                        if smbStore.isLoading { ProgressView() }
                    }
                }
                .disabled(
                    smbStore.isLoading ||
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
        .navigationTitle("Settings")
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
        .onAppear {
            password = KeychainService.loadPassword(account: keychainAccount)
        }
        .onChange(of: host) { _, _ in
            password = KeychainService.loadPassword(account: keychainAccount)
        }
        .onChange(of: share) { _, _ in
            password = KeychainService.loadPassword(account: keychainAccount)
        }
        .onChange(of: username) { _, _ in
            password = KeychainService.loadPassword(account: keychainAccount)
        }
    }

    private var keychainAccount: String {
        "\(host.trimmingCharacters(in: .whitespacesAndNewlines))|\(share.trimmingCharacters(in: .whitespacesAndNewlines))|\(username.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func testConnection() {
        resultMessage = ""

        let connection = SMBConnection(
            host: host,
            share: share,
            username: username,
            password: password
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
        SettingsView(smbStore: SMBStore())
    }
}
