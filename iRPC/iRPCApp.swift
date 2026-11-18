import SwiftUI

@main
struct AfterglowApp: App {
    @StateObject private var store: PresenceStore
    init() {
        BackgroundController.shared.register()
        let store = PresenceStore()
        _store = StateObject(wrappedValue: store)
        BackgroundRefreshController.shared.register { [weak store] in
            try await store?.performBackgroundRefresh()
        }
    }
    var body: some Scene {
        WindowGroup { ContentView(store: store) }
    }
}
