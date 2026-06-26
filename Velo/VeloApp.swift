import SwiftUI

@main
struct VeloApp: App {
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
        }
    }
}
