import SwiftUI

@main
struct AfterglowApp: App {
    init() { BackgroundController.shared.register() }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
