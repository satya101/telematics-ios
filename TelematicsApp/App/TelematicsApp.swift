import SwiftUI

@main
struct TelematicsApp: App {
    @State private var store = TrackerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                // CSVs shared from Files, Mail or AirDrop ("Open in Telematics").
                .onOpenURL { url in Task { await store.load(url: url) } }
        }
    }
}
