import SwiftUI
import ServiceManagement
import AppKit

@main
struct WakeMacAgentApp: App {
    @StateObject private var server = AgentServer()

    var body: some Scene {
        MenuBarExtra {
            AgentMenu().environmentObject(server)
        } label: {
            Image(systemName: server.isRunning ? "power.circle.fill" : "power.circle")
                .task { server.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

struct AgentMenu: View {
    @EnvironmentObject var server: AgentServer
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(server.isRunning ? "iPhoneから起動できます" : "停止中")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    row("名前", server.macName)
                    row("IP", server.info?.ip ?? "—")
                    row("MAC", server.info?.mac ?? "—")
                    row("IF", server.info?.interface ?? "—")
                }
                .font(.system(.caption, design: .monospaced))
            }

            wakeSettingView

            if let err = server.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Toggle("ログイン時に起動", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Divider()
            HStack {
                Button("再読み込み") { server.publish(); server.refreshWakeSetting() }
                Spacer()
                Button("終了") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    @ViewBuilder private var wakeSettingView: some View {
        switch server.wakeForNetworkEnabled {
        case .some(true):
            Label("ネットワーク経由のスリープ解除: 有効", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.green)
        case .some(false):
            VStack(alignment: .leading, spacing: 6) {
                Label("ネットワーク経由のスリープ解除が無効です", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                Button("システム設定を開く") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
            }
        case .none:
            Text("スリープ解除設定を確認できませんでした").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            Text(v).textSelection(.enabled)
        }
    }
}
