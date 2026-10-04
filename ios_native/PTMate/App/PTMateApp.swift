import SwiftUI

@main
struct PTMateApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isInitialized {
                Text("PT Mate")
            } else {
                ProgressView()
            }
        }
    }
}
