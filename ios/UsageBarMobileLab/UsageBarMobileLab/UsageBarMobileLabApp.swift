import SwiftUI

@main
struct UsageBarMobileLabApp: App {
    @State private var store = AppSnapshotStore(
        store: KeychainConnectionStore(),
        cache: FileSnapshotCache(),
        client: UsageSyncAPIClient(),
        surfaces: UsageSurfaceReloader()
    )

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}

struct RootView: View {
    @Bindable var store: AppSnapshotStore

    var body: some View {
        switch store.phase {
        case .needsConnection:
            ConnectionSetupView(store: store)
        case .ready:
            DashboardView(store: store)
        }
    }
}
