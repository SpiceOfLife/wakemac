import Foundation

struct SavedMac: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var mac: String
    var ip: String
    var mask: String
}

enum MacStatus: Equatable {
    case unknown, checking, waking, online, offline
}

@MainActor
final class MacStore: ObservableObject {
    @Published var macs: [SavedMac] = [] { didSet { save() } }
    @Published var status: [UUID: MacStatus] = [:]

    private let key = "savedMacs.v1"

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

    /// 起動ボタン: マジックパケット送信 → 起動確認を最大30秒ポーリング
    func wake(_ m: SavedMac) async {
        status[m.id] = .waking
        await Waker.wake(m)
        for _ in 0..<15 {
            if await Waker.ping(host: m.ip) {
                status[m.id] = .online
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // 念のため途中でもう一度送る
            await Waker.sendMagicPackets(m)
        }
        status[m.id] = .offline
    }

    func sleep(_ m: SavedMac) async {
        status[m.id] = .checking
        let ok = await Waker.sendCommand(WakeProtocol.cmdSleep, host: m.ip)
        status[m.id] = ok ? .offline : .unknown
    }

    func check(_ m: SavedMac) async {
        status[m.id] = .checking
        status[m.id] = await Waker.ping(host: m.ip) ? .online : .offline
    }
}
