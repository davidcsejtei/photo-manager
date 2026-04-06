import SwiftUI

/// Beállítások ablak — Google Drive API hitelesítő adatok + csatlakozás.
struct SettingsView: View {

    @EnvironmentObject var drive: GoogleDriveService

    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var isConnecting: Bool = false
    @State private var statusKind: StatusKind = .none
    @State private var statusText: String = ""

    enum StatusKind { case none, success, failure, info }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Google Drive API") {
                    TextField("Client ID", text: $clientID, prompt: Text("xxxxxxxx.apps.googleusercontent.com"))
                    SecureField("Client Secret", text: $clientSecret, prompt: Text("GOCSPX-…"))

                    HStack {
                        Button("Mentés") {
                            drive.saveCredentials(clientID: clientID, clientSecret: clientSecret)
                            setStatus(.info, "Hitelesítő adatok elmentve a Keychain-be.")
                        }
                        .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  clientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                    }
                }

                Section("Kapcsolódás") {
                    HStack {
                        Image(systemName: drive.isSignedIn ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(drive.isSignedIn ? Color.green : Color.secondary)
                        Text(drive.isSignedIn ? "Csatlakoztatva" : "Nincs csatlakoztatva")
                        Spacer()
                        if drive.isSignedIn {
                            Button("Kijelentkezés", role: .destructive) {
                                drive.signOut()
                                setStatus(.info, "Kijelentkeztél.")
                            }
                        } else {
                            Button(action: connect) {
                                HStack {
                                    if isConnecting {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(isConnecting ? "Csatlakozás…" : "Csatlakozás Google-fiókkal")
                                }
                            }
                            .disabled(!drive.hasCredentials || isConnecting)
                        }
                    }
                    if !drive.hasCredentials {
                        Text("Előbb mentsd el a Client ID és Client Secret mezőket.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if statusKind != .none {
                    Section {
                        Label(statusText, systemImage: iconForStatus)
                            .foregroundStyle(colorForStatus)
                            .font(.callout)
                    }
                }

                Section("Útmutató") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Nyisd meg a Google Cloud Console-t → **APIs & Services → Credentials**").font(.caption)
                        Text("2. **Create Credentials → OAuth client ID → Desktop app**").font(.caption)
                        Text("3. Másold be a Client ID-t és Client Secret-et ide, majd nyomj Mentést").font(.caption)
                        Text("4. **APIs & Services → Library → Google Drive API → Enable**").font(.caption)
                        Text("5. Nyomj **Csatlakozás**-t — böngészőben bejelentkezel, a Photo Manager automatikusan megkapja a tokeneket").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 620)
        .onAppear {
            clientID = drive.clientID
            clientSecret = drive.clientSecret
        }
    }

    // MARK: - Actions

    private func connect() {
        isConnecting = true
        // Mentés, hogy a legfrissebb mezők legyenek használva.
        drive.saveCredentials(clientID: clientID, clientSecret: clientSecret)

        Task {
            do {
                try await drive.signIn()
                await MainActor.run {
                    isConnecting = false
                    setStatus(.success, "Sikeres csatlakozás — a feltöltés most már élesben működik.")
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    setStatus(.failure, error.localizedDescription)
                }
            }
        }
    }

    private func setStatus(_ kind: StatusKind, _ text: String) {
        statusKind = kind
        statusText = text
    }

    private var iconForStatus: String {
        switch statusKind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        case .none: return ""
        }
    }

    private var colorForStatus: Color {
        switch statusKind {
        case .success: return .green
        case .failure: return .red
        case .info: return .secondary
        case .none: return .clear
        }
    }
}
