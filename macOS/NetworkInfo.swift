import Foundation
import Darwin

/// このMacのMACアドレス・IPv4・サブネットマスクを取得する
struct NetworkInfo: Equatable {
    let interface: String
    let mac: String
    let ip: String
    let mask: String

    static func current() -> NetworkInfo? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var macs: [String: String] = [:]
        var ipv4: [(name: String, ip: String, mask: String)] = []

        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let addr = ifa.ifa_addr else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue } // Wi‑Fi / Ethernet のみ
            let flags = Int32(ifa.ifa_flags)

            switch Int32(addr.pointee.sa_family) {
            case AF_LINK:
                addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdl in
                    guard sdl.pointee.sdl_alen == 6,
                          let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) else { return }
                    let base = UnsafeRawPointer(sdl).advanced(by: dataOffset + Int(sdl.pointee.sdl_nlen))
                    let bytes = (0..<6).map { base.load(fromByteOffset: $0, as: UInt8.self) }
                    macs[name] = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
                }
            case AF_INET:
                guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                      let nm = ifa.ifa_netmask,
                      let ip = ipv4String(addr), let mask = ipv4String(nm) else { continue }
                ipv4.append((name, ip, mask))
            default:
                break
            }
        }

        // en0（多くの場合 内蔵Wi‑Fi or Ethernet）を優先。有線を挿していればそちらが先に来ることもある
        let sorted = ipv4.sorted { $0.name < $1.name }
        for v in sorted {
            if let mac = macs[v.name] {
                return NetworkInfo(interface: v.name, mac: mac, ip: v.ip, mask: v.mask)
            }
        }
        return nil
    }

    private static func ipv4String(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            var addr = sin.pointee.sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buf)
        }
    }
}
