import Foundation
import Network
import Darwin

/// Wake-on-LAN とエージェントとの通信
enum Waker {
    private static let queue = DispatchQueue(label: "waker")

    /// FF×6 + MACアドレス×16 のマジックパケット
    static func magicPacket(mac: String) -> Data? {
        let hex = mac.replacingOccurrences(of: "[:\\-\\.\\s]", with: "", options: .regularExpression)
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += bytes }
        return Data(packet)
    }

    /// 起動シーケンス
    /// 1. 最後に分かっているIPへユニキャストでマジックパケット
    /// 2. サブネットのブロードキャストへマジックパケット（multicast entitlementがある場合のみ届く）
    /// 3. エージェントのTCPポートへ接続 → Bonjour Sleep Proxy がいればMacが起こされる
    static func wake(_ m: SavedMac) async {
        await sendMagicPackets(m)
        _ = await sendCommand(WakeProtocol.cmdPing, host: m.ip, port: WakeProtocol.agentPort, timeout: 1.0)
    }

    static func sendMagicPackets(_ m: SavedMac) async {
        guard let packet = magicPacket(mac: m.mac) else { return }
        var targets = [m.ip]
        if let bcast = broadcastAddress(ip: m.ip, mask: m.mask) { targets.append(bcast) }
        targets.append("255.255.255.255")
        for host in targets {
            for port in WakeProtocol.wolPorts {
                await udpSend(packet, host: host, port: port)
            }
        }
    }

    static func broadcastAddress(ip: String, mask: String) -> String? {
        let i = ip.split(separator: ".").compactMap { UInt8($0) }
        let m = mask.split(separator: ".").compactMap { UInt8($0) }
        guard i.count == 4, m.count == 4 else { return nil }
        return zip(i, m).map { String($0 | ~$1) }.joined(separator: ".")
    }

    static func udpSend(_ data: Data, host: String, port: UInt16) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let conn = NWConnection(host: NWEndpoint.Host(host),
                                    port: NWEndpoint.Port(rawValue: port)!,
                                    using: .udp)
            var finished = false
            let finish = {
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume()
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: data, completion: .contentProcessed { _ in finish() })
                case .failed, .cancelled:
                    finish()
                default:
                    break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1.0) { finish() }
        }
    }

    /// 起きているか確認（広告していない制御ポートを使うので、寝ているMacを起こさない）
    static func ping(host: String, timeout: TimeInterval = 1.5) async -> Bool {
        await sendCommand(WakeProtocol.cmdPing, host: host, port: WakeProtocol.controlPort, timeout: timeout)
    }

    /// iPhoneが今、Macと同じサブネット（家のWi‑Fi）にいるか
    static func isOnSameSubnet(as m: SavedMac) -> Bool {
        guard let target = ipv4(m.ip), let mask = ipv4(m.mask) else { return false }
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(head) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }   // Wi‑Fi / 有線のみ（VPNの ipsec / utun は除く）
            let mine = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if mine & mask == target & mask { return true }
        }
        return false
    }

    private static func ipv4(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return parts.reduce(0) { ($0 << 8) | $1 }
    }

    /// エージェントにコマンドを送り、応答があれば true
    static func sendCommand(_ cmd: String, host: String, port: UInt16 = WakeProtocol.controlPort, timeout: TimeInterval = 2.0) async -> Bool {
        await request(cmd, host: host, port: port, timeout: timeout) != nil
    }

    /// エージェントにコマンドを送り、応答の1行を返す（応答なしは nil）
    static func request(_ cmd: String, host: String, port: UInt16 = WakeProtocol.controlPort, timeout: TimeInterval = 2.0) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let conn = NWConnection(host: NWEndpoint.Host(host),
                                    port: NWEndpoint.Port(rawValue: port)!,
                                    using: .tcp)
            var finished = false
            let finish = { (reply: String?) in
                queue.async {
                    guard !finished else { return }
                    finished = true
                    conn.cancel()
                    cont.resume(returning: reply)
                }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: Data((cmd + "\n").utf8), completion: .contentProcessed { _ in })
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 128) { data, _, _, _ in
                        guard let data, !data.isEmpty else { finish(nil); return }
                        finish(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}
