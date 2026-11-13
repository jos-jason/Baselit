import SwiftUI

/// Signs in to a PocketBase server and shows how sync is going.
struct SyncSettingsView: View {
    @Environment(SyncService.self) private var sync
    @State private var serverURL = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var askFirstSync = false

    var body: some View {
        Form {
            if sync.isSignedIn {
                Section("Server") {
                    LabeledContent("Address", value: sync.serverURL ?? "")
                    LabeledContent("Signed In As", value: sync.email ?? "")
                    HStack {
                        if sync.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: sync.lastError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(sync.lastError == nil ? .green : .orange)
                        }
                        Text(Self.status(of: sync))
                    }
                }
                Section {
                    Button {
                        Task { await sync.sync() }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(sync.isSyncing)
                    Button(role: .destructive) {
                        sync.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("Changes sync a few seconds after you make them, every minute while Baselit is open, and when you come back to it. Signing out keeps everything on this device.")
                }
            } else {
                Section {
                    // Verbatim, so the example address isn't styled as a link
                    TextField(text: $serverURL, prompt: Text(verbatim: "https://pb.example.com")) {
                        Text("Server Address")
                    }
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("PocketBase Server")
                } footer: {
                    Text("Sign in with a user from your server's users collection. Every Baselit app signed in to the same user keeps the same inventory, photos included.")
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text("Sign In")
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isWorking || serverURL.isEmpty || email.isEmpty || password.isEmpty)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if serverURL.isEmpty { serverURL = sync.serverURL ?? "" }
            if email.isEmpty { email = sync.email ?? "" }
        }
        .alert("Server Already Has Data", isPresented: $askFirstSync) {
            Button("Use Server's") { Task { await sync.firstSync(.useServer) } }
            Button("Merge") { Task { await sync.firstSync(.merge) } }
        } message: {
            Text("Use Server's replaces everything on this device with what's on the server. Merge keeps both, which can make duplicates if this device was set up from a backup of the same inventory.")
        }
    }

    private func signIn() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let bothHaveData = try await sync.signIn(url: serverURL, email: email, password: password)
            password = ""
            if bothHaveData {
                askFirstSync = true
            } else {
                await sync.firstSync(.merge)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// One line describing where sync stands.
    static func status(of sync: SyncService) -> String {
        guard sync.isSignedIn else { return "Off" }
        if sync.isSyncing { return "Syncing…" }
        if let error = sync.lastError { return error }
        guard let last = sync.lastSynced else { return "Signed in" }
        return "Last synced \(last.formatted(.relative(presentation: .named)))"
    }
}
