import Foundation
import Network

struct SavedMac: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var mac: String
    var ip: String
    var mask: String

    var macKey: String { mac.lowercased() }
}

enum MacStatus: Equatable {
    case unknown           // まだ確認していない
    case checking          // 確認中
    case connectingVPN     // 自宅にVPN接続中
    case waking            // 起こしている
    case sleeping          // スリープの命令を送っている／眠りに入るところ
    case sleepPending(Int) // Macでカウントダウン中（残り秒）
    case canceledOnMac     // Macの前でキャンセルされた（起きている）
    case online            // 起きている
    case asleep            // 寝ている
    case failed(String)    // つながらなかった等
}

/// どの経路でMacに届いているか
enum Route: Equatable { case none, local, vpn }

/// Macへの問い合わせ結果
enum Probe: Equatable {
    case awake          // 起きていて応答した
    case dozing         // 応答したが、システムはスリープ中（通信で一時的に目覚めただけ）
    case noReply        // 応答なし（寝ている／届かない）

    init(reply: String?) {
        guard let r = reply else { self = .noReply; return }
        self = r.contains(WakeProtocol.replySleeping) ? .dozing : .awake
    }
}

@MainActor
final class MacStore: ObservableObject {
    @Published var macs: [SavedMac] = [] { didSet { save() } }
    @Published var status: [UUID: MacStatus] = [:]
    @Published private(set) var route: Route = .none
    @Published private(set) var lastChecked: Date?

    private let key = "savedMacs.v1"
    private let vpn = VPNController.shared
    private var sleepCanceled: Set<UUID> = []
    private var autoRefresh: Task<Void, Never>?

    /// Bonjour で見えている各Macの状態（MACアドレス → "awake"/"asleep"）。
    /// 受け取るだけなので、寝ているMacを起こさない
    private var advertised: [String: String] = [:]
    private var browser: NWBrowser?

    static let autoRefreshInterval: UInt64 = 10

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
        if let i = macs.firstIndex(where: { $0.macKey == m.macKey }) {
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
        case .checking, .connectingVPN, .waking, .sleeping, .sleepPending: return true
        default: return false
        }
    }

    // MARK: - アプリの表示中だけ動かす

    /// 表示中：Bonjour の監視と、10秒ごとの状態確認
    func appDidBecomeActive() {
        startBrowsing()
        autoRefresh?.cancel()
        autoRefresh = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll(auto: true)
                try? await Task.sleep(nanoseconds: Self.autoRefreshInterval * 1_000_000_000)
            }
        }
    }

    /// 閉じたら：確認を止め、アプリがつないだVPNを切る
    func appDidLeave() {
        autoRefresh?.cancel()
        autoRefresh = nil
        browser?.cancel()
        browser = nil
        vpn.disconnectIfStartedByApp()
        route = .none
    }

    private func startBrowsing() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: WakeProtocol.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            var map: [String: String] = [:]
            var ips: [String: String] = [:]
            for r in results {
                guard case let .bonjour(txt) = r.metadata, let mac = txt[WakeProtocol.keyMAC] else { continue }
                map[mac.lowercased()] = txt[WakeProtocol.keyState] ?? WakeProtocol.stateAwake
                if let ip = txt[WakeProtocol.keyIP] { ips[mac.lowercased()] = ip }
            }
            Task { @MainActor in self?.applyAdvertised(map, ips: ips) }
        }
        b.start(queue: .main)
        browser = b
    }

    /// Macが広告を更新したら、すぐ画面に反映する（寝た／起きた）
    private func applyAdvertised(_ map: [String: String], ips: [String: String]) {
        advertised = map
        for i in macs.indices {
            let m = macs[i]
            // IPが変わっていたら追従
            if let ip = ips[m.macKey], ip != m.ip { macs[i].ip = ip }
            guard !isBusy(m), let st = map[m.macKey] else { continue }
            if st == WakeProtocol.stateAsleep {
                status[m.id] = .asleep
            } else if status[m.id] == .asleep || status[m.id] == .unknown {
                status[m.id] = .online
            }
        }
    }

    // MARK: - 経路の確保（家ならそのまま、外ならVPN）

    private func ensureRoute(for m: SavedMac) async -> Route {
        if vpn.isConnected { route = .vpn; return .vpn }
        if advertised[m.macKey] != nil || Waker.isOnSameSubnet(as: m) {
            route = .local   // Bonjourで見える／同じサブネット＝家にいる
            return .local
        }
        if Probe(reply: await Waker.request(WakeProtocol.cmdPing, host: m.ip, timeout: 0.8)) != .noReply {
            route = .local
            return .local
        }
        guard vpn.settings.enabled, vpn.settings.isComplete else {
            route = .local   // VPN未設定なら家にいる前提で続ける
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

    // MARK: - 状態確認

    /// 状態を確認する。
    /// auto（10秒ごと）では、寝ているとわかっているMacに問い合わせない（問い合わせで起こしてしまうため）
    func refreshAll(auto: Bool = false) async {
        for m in macs where !isBusy(m) {
            if let st = advertised[m.macKey] {
                // 家のネットワーク：Macが広告している状態をそのまま使う（通信しない）
                if st == WakeProtocol.stateAsleep { status[m.id] = .asleep; continue }
                if auto, status[m.id] == .online { continue }
            } else if auto, status[m.id] == .asleep {
                continue   // 外出先など広告が見えないとき、寝ているMacには触らない
            }
            if !auto { status[m.id] = .checking }
            guard await ensureRoute(for: m) != .none else { continue }
            if isBusy(m), status[m.id] != .checking { continue }
            switch Probe(reply: await Waker.request(WakeProtocol.cmdPing, host: m.ip, timeout: 1.5)) {
            case .awake: status[m.id] = .online
            case .dozing, .noReply: status[m.id] = .asleep
            }
        }
        lastChecked = Date()
    }

    // MARK: - 操作

    /// 電源ボタン：起きていればスリープ、寝ていれば起こす
    func toggle(_ m: SavedMac) async {
        status[m.id] = .checking
        guard await ensureRoute(for: m) != .none else { return }
        if advertised[m.macKey] == WakeProtocol.stateAsleep {
            await wakeNow(m)
            return
        }
        switch Probe(reply: await Waker.request(WakeProtocol.cmdPing, host: m.ip)) {
        case .awake:
            await sleepNow(m)
        case .dozing, .noReply:
            await wakeNow(m)
        }
    }

    /// 起動: マジックパケット＋起こす用ポートへの接続。応答したら「完全に起きて」と頼む
    private func wakeNow(_ m: SavedMac) async {
        status[m.id] = .waking
        await Waker.wake(m)
        for i in 0..<20 {
            switch Probe(reply: await Waker.request(WakeProtocol.cmdPing, host: m.ip, timeout: 1.5)) {
            case .awake:
                status[m.id] = .online
                return
            case .dozing:
                // 通信で一時的に目覚めている → 画面をつけて完全に起こす
                _ = await Waker.request(WakeProtocol.cmdWake, host: m.ip)
            case .noReply:
                if i % 2 == 1 { await Waker.wake(m) }  // 届かなかったときのため繰り返す
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        status[m.id] = .failed(route == .vpn
            ? "起きませんでした。外からの起動には、家にApple TV / HomePodがあるか、Macの有線接続が必要です"
            : "起きませんでした。Macの「ネットワークアクセスによるスリープ解除」を確認してください")
    }

    /// スリープ前にMacで表示するカウントダウン（秒）。設定画面で変更
    static var sleepDelay: Int {
        let v = UserDefaults.standard.object(forKey: "sleepDelay") as? Int
        return v ?? WakeProtocol.defaultSleepDelay
    }

    /// スリープ: Macにカウントダウンを出させ、眠るまで見守る
    private func sleepNow(_ m: SavedMac) async {
        status[m.id] = .sleeping
        sleepCanceled.remove(m.id)
        let delay = Self.sleepDelay
        guard let reply = await Waker.request("\(WakeProtocol.cmdSleep) \(delay)", host: m.ip) else {
            status[m.id] = .failed("スリープの命令が届きませんでした")
            return
        }
        // 古いエージェントは "OK" を返してすぐ寝る
        var secs = delay
        let parts = reply.split(separator: " ")
        if parts.first == Substring(WakeProtocol.replyCountdown), parts.count > 1, let n = Int(parts[1]) { secs = n }
        else if reply == "OK" { secs = 0 }
        if secs > 0 { status[m.id] = .sleepPending(secs) }

        let deadline = Date().addingTimeInterval(TimeInterval(secs) + 30)
        var misses = 0
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if sleepCanceled.contains(m.id) { return }   // iPhoneで中止した
            // 眠りに入ると Bonjour の広告が asleep に変わる
            if advertised[m.macKey] == WakeProtocol.stateAsleep { status[m.id] = .asleep; return }
            let r = await Waker.request(WakeProtocol.cmdPing, host: m.ip, timeout: 1.2)
            if sleepCanceled.contains(m.id) { return }
            guard let r else {
                misses += 1
                if misses >= 2 { status[m.id] = .asleep; return }   // 応答がなくなった＝寝た
                continue
            }
            misses = 0
            let p = r.split(separator: " ")
            if r.contains(WakeProtocol.replySleeping) {
                status[m.id] = .asleep
                return
            } else if p.count >= 3, p[1] == Substring(WakeProtocol.replyPending), let n = Int(p[2]) {
                status[m.id] = .sleepPending(n)
            } else if p.count >= 2, p[1] == Substring(WakeProtocol.replyCanceled) {
                status[m.id] = .canceledOnMac
                return
            } else {
                status[m.id] = .sleeping    // カウントダウンが終わり、眠りに入るところ
            }
        }
        // 時間内に眠らなかった（スリープを妨げるアプリなど）
        status[m.id] = .failed("スリープしませんでした。Macでスリープを妨げているアプリがないか確認してください")
    }

    /// iPhoneからスリープを中止
    func cancelSleep(_ m: SavedMac) async {
        sleepCanceled.insert(m.id)
        status[m.id] = .online
        _ = await Waker.request(WakeProtocol.cmdCancel, host: m.ip)
    }
}
