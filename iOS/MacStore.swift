import Foundation

struct SavedMac: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var mac: String
    var ip: String
    var mask: String
}

enum MacStatus: Equatable {
    case unknown        // まだ確認していない
    case checking       // 確認中
    case connectingVPN  // 自宅にVPN接続中
    case waking         // 起こしている
    case sleeping       // スリープさせている
    case online         // 起きている
    case asleep         // 寝ている（応答なし）
    case failed(String) // つながらなかった等
}

/// どの経路でMacに届いているか
enum Route: Equatable { case none, local, vpn }

@MainActor
final class MacStore: ObservableObject {
    @Published var macs: [SavedMac] = [] { didSet { save() } }
    @Published var status: [UUID: MacStatus] = [:]
    @Published private(set) var route: Route = .none

    private let key = "savedMacs.v1"
    private let vpn = VPNController.shared
    private var idleDisconnect: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([SavedMac].self, from: data) {
            macs = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(macs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 同じMACアドレスなら上書き（IP変更に追従）
    func upsert(_ m: SavedMac) {
        if let i = macs.firstIndex(where: { $0.mac.lowercased() == m.mac.lowercased() }) {
            var updated = m
            updated.id = macs[i].id
            macs[i] = updated
        } else {
            macs.append(m)
        }
    }

    func remove(at offsets: IndexSet) {
        for i in offsets.sorted(by: >) { macs.remove(at: i) }
    }

    func isBusy(_ m: SavedMac) -> Bool {
        switch status[m.id] ?? .unknown {
        case .checking, .connectingVPN, .waking, .sleeping: return true
        default: return false
        }
    }

    // MARK: - 経路の確保（家ならそのまま、外ならVPN）

    /// Macに届く経路を用意する。家のWi‑Fiで届けば .local、届かなければVPNをつなぐ
    private func ensureRoute(for m: SavedMac) async -> Route {
        if vpn.isConnected {
            route = .vpn
            return .vpn
        }
        // 家のネットワークにいるか：同じサブネットのMacに直接届くか / Bonjourで見えているか
        if await Waker.ping(host: m.ip, timeout: 0.8) {
            route = .local
            return .local
        }
        guard vpn.settings.enabled, vpn.settings.isComplete else {
            route = .local   // VPN未設定なら家にいる前提で続ける
            return .local
        }
        if Waker.isOnSameSubnet(as: m) {
            route = .local   // 同じサブネットにいる＝家。Macが寝ているだけ
            return .local
        }
        status[m.id] = .connectingVPN
        do {
            try await vpn.connect()
            route = .vpn
            return .vpn
        } catch {
            status[m.id] = .failed(error.localizedDescription)
            route = .none
            return .none
        }
    }

    /// 操作が終わってしばらく使われなければ、アプリがつないだVPNを切る
    private func scheduleIdleDisconnect(after seconds: UInt64 = 90) {
        idleDisconnect?.cancel()
        guard vpn.startedByApp else { return }
        idleDisconnect = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.vpn.disconnectIfStartedByApp()
            self?.route = .none
        }
    }

    /// アプリがバックグラウンドに回ったらすぐ切る
    func appDidLeave() {
        idleDisconnect?.cancel()
        vpn.disconnectIfStartedByApp()
        route = .none
    }

    // MARK: - 操作

    /// 画面を開いたとき：全Macの状態を確認する（外出先ならVPNをつないで確認）
    func refreshAll() async {
        for m in macs where !isBusy(m) {
            status[m.id] = .checking
            guard await ensureRoute(for: m) != .none else { continue }
            status[m.id] = await Waker.ping(host: m.ip) ? .online : .asleep
        }
        scheduleIdleDisconnect()
    }

    /// 電源ボタン：起きていればスリープ、寝ていれば起こす
    func toggle(_ m: SavedMac) async {
        idleDisconnect?.cancel()
        status[m.id] = .checking
        guard await ensureRoute(for: m) != .none else { scheduleIdleDisconnect(); return }
        if await Waker.ping(host: m.ip) {
            await sleepNow(m)
        } else {
            await wakeNow(m)
        }
        scheduleIdleDisconnect()
    }

    /// 起動: マジックパケット送信 → 起動確認を最大40秒ポーリング
    private func wakeNow(_ m: SavedMac) async {
        status[m.id] = .waking
        await Waker.wake(m)
        for i in 0..<20 {
            if await Waker.ping(host: m.ip) {
                status[m.id] = .online
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if i % 2 == 1 { await Waker.wake(m) }  // 届かなかったときのため繰り返す
        }
        status[m.id] = .failed(route == .vpn
            ? "起きませんでした。外からの起動には、家にApple TV / HomePodがあるか、Macの有線接続が必要です"
            : "起きませんでした。Macの「ネットワークアクセスによるスリープ解除」を確認してください")
    }

    /// スリープ: エージェントに命令 → 応答がなくなるまで確認
    private func sleepNow(_ m: SavedMac) async {
        status[m.id] = .sleeping
        guard await Waker.sendCommand(WakeProtocol.cmdSleep, host: m.ip) else {
            status[m.id] = .failed("スリープの命令が届きませんでした")
            return
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        for _ in 0..<10 {
            if !(await Waker.ping(host: m.ip, timeout: 1.0)) {
                status[m.id] = .asleep
                return
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        status[m.id] = .online
    }
}
