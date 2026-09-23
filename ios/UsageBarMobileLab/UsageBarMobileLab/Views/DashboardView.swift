import SwiftUI
import UsageBarSync

struct DashboardView: View {
    @Bindable var store: AppSnapshotStore
    @State private var showingForgetConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = store.snapshot, !snapshot.providers.isEmpty {
                    List {
                        if store.lastRefreshFailed {
                            Section { OfflineBanner() }
                        }
                        ForEach(snapshot.providers, id: \.providerId) { provider in
                            Section {
                                ProviderCardView(provider: provider)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else if store.snapshot != nil {
                    ContentUnavailableView(
                        "No providers",
                        systemImage: "tray",
                        description: Text("The Mac reported no connected providers.")
                    )
                } else {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "arrow.clockwise",
                        description: Text("Pull to refresh once the Mac is awake.")
                    )
                }
            }
            .navigationTitle("UsageBar")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    // A second concurrent refresh would race the first for no
                    // benefit, so the control is disabled while one is running.
                    .disabled(store.isRefreshing)
                    .accessibilityLabel("Refresh")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Forget", role: .destructive) {
                        showingForgetConfirmation = true
                    }
                }
            }
            .confirmationDialog(
                "Forget this connection?",
                isPresented: $showingForgetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Forget Connection", role: .destructive) {
                    store.forgetConnection()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the saved hostname, the access key and the cached usage data from this iPhone.")
            }
        }
    }
}

/// Shown *beside* data that is still on screen, never in place of it.
private struct OfflineBanner: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing last known usage")
                    .font(.subheadline.weight(.medium))
                Text("Could not reach UsageBar. The Mac may be asleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
        }
    }
}
