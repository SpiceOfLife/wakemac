import SwiftUI

@main
struct WakeMacApp: App {
    @StateObject private var store = MacStore()
    @StateObject private var browser = MacBrowser()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(browser)
                .preferredColorScheme(.dark)
        }
    }
}
