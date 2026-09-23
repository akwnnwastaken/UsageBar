import AVFoundation
import SwiftUI
import UsageBarPairing

/// First launch. Nothing is pre-filled from source: the host and the access key
/// are runtime configuration that only the owner can supply.
///
/// Scanning the Mac's QR is the normal path — it carries a one-time code rather
/// than a durable credential, and it removes the step where a 43-character
/// bearer has to travel between two devices by hand. The manual fields remain
/// as an operator fallback for when the Mac cannot show a QR.
struct ConnectionSetupView: View {
    @Bindable var store: AppSnapshotStore

    @State private var hostText = ""
    @State private var accessKey = ""
    @State private var errorMessage: String?
    @State private var isScanning = false
    @State private var isPairing = false
    @FocusState private var focusedField: Field?

    private let pairingClient: any PairingExchanging

    init(store: AppSnapshotStore, pairingClient: any PairingExchanging = UsageSyncPairingClient()) {
        self.store = store
        self.pairingClient = pairingClient
    }

    private enum Field { case host, key }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        errorMessage = nil
                        isScanning = true
                    } label: {
                        HStack {
                            Label("Scan Mac Pairing QR", systemImage: "qrcode.viewfinder")
                            Spacer()
                            if isPairing { ProgressView() }
                        }
                    }
                    .disabled(isPairing || store.isRefreshing)
                } header: {
                    Text("Pair")
                } footer: {
                    Text("On the Mac, open UsageBar Mobile Host and choose Pair iPhone.")
                }

                Section {
                    TextField("your-mac.your-tailnet.ts.net", text: $hostText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .host)
                } header: {
                    Text("Tailscale Serve Host")
                } footer: {
                    Text("The MagicDNS name of the Mac running UsageBar. Hostname only — no https:// and no path.")
                }

                Section {
                    SecureField("Access key", text: $accessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .key)
                } header: {
                    Text("Access Key")
                } footer: {
                    Text("Stored in the iPhone keychain on this device only.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Text("Save & Test")
                            Spacer()
                            if store.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(store.isRefreshing || hostText.isEmpty || accessKey.isEmpty)
                }
            }
            .navigationTitle("Connect")
            .fullScreenCover(isPresented: $isScanning) {
                NavigationStack {
                    PairingScannerView(
                        onScan: { payload in
                            isScanning = false
                            Task { await pair(with: payload) }
                        },
                        onFailure: { _ in
                            isScanning = false
                            errorMessage = "The camera is not available."
                        }
                    )
                    .ignoresSafeArea()
                    .navigationTitle("Scan Pairing Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isScanning = false }
                        }
                    }
                }
            }
        }
    }

    /// Exchanges the scanned code, then proves the credential before it is
    /// stored. Nothing reaches the keychain until a real snapshot has come back
    /// and validated.
    private func pair(with payload: UsageBarPairingPayload) async {
        errorMessage = nil
        isPairing = true
        defer { isPairing = false }
        do {
            let paired = try await pairingClient.exchange(payload: payload)
            if case .failure = await store.completePairing(paired) {
                errorMessage = PairingError.refused.description
            }
        } catch {
            // One generic sentence. A pairing failure must not describe which
            // part of the exchange failed.
            errorMessage = (error as? PairingError)?.description
                ?? PairingError.transportFailure.description
        }
    }

    private func save() async {
        errorMessage = nil
        let host: UsageSyncHost
        do {
            host = try UsageSyncHost(validating: hostText)
        } catch let error as UsageSyncHost.ValidationError {
            errorMessage = error.description
            return
        } catch {
            errorMessage = "That is not a valid hostname."
            return
        }

        let result = await store.connect(host: host, accessKey: accessKey)
        if case .failure(let error) = result {
            // Only our own generic sentence reaches the screen — never a server
            // body, a TLS message or an underlying error description.
            errorMessage = (error as? SnapshotFetchError)?.description
                ?? "Could not reach UsageBar."
            return
        }
        accessKey = ""
    }
}
