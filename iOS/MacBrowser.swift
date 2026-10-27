import Foundation
import Network

/// 同じネットワーク上で WakeMac Agent が動いているMacを探す
@MainActor
final class MacBrowser: ObservableObject {
    @Published private(set) var found: [SavedMac] = []
    @Published private(set) var isBrowsing = false

    private var browser: NWBrowser?

    func start() {
        stop()
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: WakeProtocol.serviceType, domain: nil),
                          using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let macs: [SavedMac] = results.compactMap { r in
                guard case let .bonjour(txt) = r.metadata,
                      let mac = txt[WakeProtocol.keyMAC],
                      let ip = txt[WakeProtocol.keyIP] else { return nil }
                var name = txt[WakeProtocol.keyName] ?? "Mac"
                if case let .service(n, _, _, _) = r.endpoint { name = n }
                return SavedMac(name: name, mac: mac, ip: ip, mask: txt[WakeProtocol.keyMask] ?? "255.255.255.0")
            }
            Task { @MainActor in self?.found = macs }
        }
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.isBrowsing = true
                case .failed, .cancelled: self?.isBrowsing = false
                default: break
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }
}
