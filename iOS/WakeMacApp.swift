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
                store.appDidBecomeActive()   // 表示中は10秒ごとに状態を確認（外出先ならVPNで）
            case .background:
                store.appDidLeave()          // 閉じたら確認を止め、VPNを切る
            default:
                break
            }
        }
    }
}
