import Foundation
import Network

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
        _ = await sendCommand(WakeProtocol.cmdPing, host: m.ip, timeout: 1.0)
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

    static func ping(host: String) async -> Bool {
        await sendCommand(WakeProtocol.cmdPing, host: host, timeout: 1.5)
    }

    /// エージェントにコマンドを送り、応答があれば true
    static func sendCommand(_ cmd: String, host: String, timeout: TimeInterval = 2.0) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(host: NWEndpoint.Host(host),
                                    port: NWEndpoint.Port(rawValue: WakeProtocol.agentPort)!,
                                    using: .tcp)
            var finished = false
            let finish = { (ok: Bool) in
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: Data((cmd + "\n").utf8), completion: .contentProcessed { _ in })
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
                        finish(!(data ?? Data()).isEmpty)
                    }
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}
