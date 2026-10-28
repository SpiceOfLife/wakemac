import SwiftUI

@main
struct WakeMacApp: App {
    @StateObject private var store = MacStore()
    @StateObject private var browser = MacBrowser()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(browser)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await store.refreshAll() }   // 開いたら状態を確認（外出先ならVPNで）
            case .background:
                store.appDidLeave()                  // 閉じたらVPNを切る
            default:
                break
            }
        }
    }
}
