import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: MacStore
    @EnvironmentObject var browser: MacBrowser
    @State private var showAdd = false

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddMacView() }
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
    let mac: SavedMac
    let large: Bool
    @State private var confirmDelete = false

    private var status: MacStatus { store.status[mac.id] ?? .unknown }

    var body: some View {
        VStack(spacing: large ? 28 : 14) {
            Text(mac.name)
                .font(large ? .title2.bold() : .headline)

            Button {
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.impactOccurred()
                Task { await store.wake(mac) }
            } label: {
                ZStack {
                    Circle()
                        .fill(buttonColor.opacity(0.18))
                    Circle()
                        .strokeBorder(buttonColor, lineWidth: large ? 4 : 3)
                    if status == .waking {
                        ProgressView().controlSize(.large).tint(buttonColor)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: large ? 72 : 36, weight: .semibold))
                            .foregroundStyle(buttonColor)
                    }
                }
                .frame(width: large ? 200 : 96, height: large ? 200 : 96)
            }
            .buttonStyle(.plain)
            .disabled(status == .waking)
            .accessibilityLabel("\(mac.name)を起動")

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Button("状態を確認") { Task { await store.check(mac) } }
                Button("スリープ") { Task { await store.sleep(mac) } }
                    .disabled(status != .online)
            }
            .font(.footnote)

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

    private var buttonColor: Color {
        switch status {
        case .online: return .green
        case .offline: return .orange
        default: return .accentColor
        }
    }

    private var statusText: String {
        switch status {
        case .unknown: return "ボタンを押すと起動します"
        case .checking: return "確認中…"
        case .waking: return "起動信号を送信中…"
        case .online: return "起動しています"
        case .offline: return "応答がありません"
        }
    }
}
