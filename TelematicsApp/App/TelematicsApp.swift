import SwiftUI

@main
struct TelematicsApp: App {
    @State private var store = TrackerStore()
    @State private var ilinkair = ILinkAirStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(ilinkair)
                .tint(Theme.accent)
                // CSVs shared from Files, Mail or AirDrop ("Open in AssetIQ").
                .onOpenURL { url in Task { await store.load(url: url) } }
        }
    }
}
