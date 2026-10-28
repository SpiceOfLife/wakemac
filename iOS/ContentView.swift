import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: MacStore
    @EnvironmentObject var browser: MacBrowser
    @State private var showAdd = false
    @State private var showVPN = false

    var body: some View {
        NavigationStack {
            Group {
                if store.macs.isEmpty {
                    emptyState
                } else if store.macs.count == 1, let m = store.macs.first {
                    // 1台だけならボタン1つの画面
                    WakeCard(mac: m, large: true)
                        .frame(maxHeight: .infinity)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(store.macs) { WakeCard(mac: $0, large: false) }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("WakeMac")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showVPN = true } label: { Image(systemName: "lock.shield") }
                        .accessibilityLabel("外出先から使う（VPN）")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddMacView() }
            .sheet(isPresented: $showVPN) { VPNSettingsView() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Macが登録されていません")
                .font(.headline)
            Text("Macで「WakeMac Agent」を起動した状態で、\n同じWi‑Fiから追加してください。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Macを追加") { showAdd = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct WakeCard: View {
    @EnvironmentObject var store: MacStore
    @ObservedObject private var vpn = VPNController.shared
    let mac: SavedMac
    let large: Bool
    @State private var confirmDelete = false

    private var status: MacStatus { store.status[mac.id] ?? .unknown }
    private var busy: Bool { store.isBusy(mac) }
    private var isOn: Bool { status == .online }

    var body: some View {
        VStack(spacing: large ? 28 : 14) {
            VStack(spacing: 6) {
                Text(mac.name)
                    .font(large ? .title2.bold() : .headline)
                routeBadge
            }

            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                Task { await store.toggle(mac) }
            } label: {
                ZStack {
                    Circle().fill(buttonColor.opacity(0.18))
                    Circle().strokeBorder(buttonColor, lineWidth: large ? 4 : 3)
                    if busy {
                        ProgressView().controlSize(.large).tint(buttonColor)
                    } else {
                        Image(systemName: isOn ? "moon.fill" : "power")
                            .font(.system(size: large ? 72 : 36, weight: .semibold))
                            .foregroundStyle(buttonColor)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: large ? 200 : 96, height: large ? 200 : 96)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel(isOn ? "\(mac.name)をスリープ" : "\(mac.name)を起動")

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(statusIsError ? Color.orange : Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("状態を確認") { Task { await store.refreshAll() } }
                .font(.footnote)
                .disabled(busy)

            Text("\(mac.ip)  ·  \(mac.mac)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(large ? 24 : 16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
        .contextMenu {
            Button("削除", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("\(mac.name)を削除しますか？", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) {
                if let i = store.macs.firstIndex(of: mac) { store.remove(at: IndexSet(integer: i)) }
            }
        }
    }

    @ViewBuilder private var routeBadge: some View {
        switch store.route {
        case .vpn:
            Label("VPN経由（外出先）", systemImage: "lock.shield.fill")
                .font(.caption).foregroundStyle(.blue)
        case .local:
            Label("家のネットワーク", systemImage: "house.fill")
                .font(.caption).foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }

    private var statusIsError: Bool {
        if case .failed = status { return true }
        return false
    }

    private var buttonColor: Color {
        switch status {
        case .online: return .indigo
        case .asleep: return .orange
        case .failed: return .gray
        default: return .accentColor
        }
    }

    private var statusText: String {
        switch status {
        case .unknown: return "ボタンを押すと起動します"
        case .checking: return "確認中…"
        case .connectingVPN: return "自宅にVPN接続しています…"
        case .waking: return "起動しています…"
        case .sleeping: return "スリープさせています…"
        case .online: return "起きています。押すとスリープします"
        case .asleep: return "スリープ中です。押すと起動します"
        case .failed(let msg): return msg
        }
    }
}
