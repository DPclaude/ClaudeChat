import SwiftUI

@main
struct ClaudeChatApp: App {
    @StateObject private var store = ChatStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.syncInBackground()
            }
        }
    }
}
