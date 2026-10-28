import Foundation
import Network
import AppKit
import IOKit.pwr_mgt

/// Bonjourで自分を広告し、iPhoneからの PING / SLEEP を受け付ける小さなTCPサーバー
@MainActor
final class AgentServer: ObservableObject {
    static let shared = AgentServer()

    @Published private(set) var info: NetworkInfo?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var wakeForNetworkEnabled: Bool?
    /// システムがスリープに入ってから、完全に起きる（画面がつく）までの間 true。
    /// この間に通信で一時的に目覚めても（ダークウェイク）「スリープ中」と答える
    @Published private(set) var systemAsleep = false
    private var activityAssertion: IOPMAssertionID = 0

    private var listener: NWListener?
    private var controlListener: NWListener?
    private let pathMonitor = NWPathMonitor()

    var macName: String { Host.current().localizedName ?? "Mac" }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        refreshWakeSetting()
        observeSleep()
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: WakeProtocol.agentPort)!)
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.isRunning = true; self?.lastError = nil
                    case .failed(let e): self?.isRunning = false; self?.lastError = e.localizedDescription
                    case .cancelled: self?.isRunning = false
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            listener = l
            publish()
            l.start(queue: .main)

            // 状態確認・スリープ用（Bonjour では広告しない）
            let cparams = NWParameters.tcp
            cparams.allowLocalEndpointReuse = true
            let c = try NWListener(using: cparams, on: NWEndpoint.Port(rawValue: WakeProtocol.controlPort)!)
            c.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            controlListener = c
            c.start(queue: .main)
        } catch {
            lastError = error.localizedDescription
        }

        // IPアドレスが変わったらTXTレコードを更新
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.publish() }
        }
        pathMonitor.start(queue: .main)
    }

    /// スリープ／起動の通知を受けて、状態とBonjourの広告を更新する
    private func observeSleep() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                AgentServer.shared.systemAsleep = true
                AgentServer.shared.publish()   // 眠る直前に「asleep」を広告（Sleep Proxy にも引き継がれる）
            }
        }
        // didWake は画面がつく「完全な起動」のときだけ届く（通信によるダークウェイクでは届かない）
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                AgentServer.shared.systemAsleep = false
                AgentServer.shared.publish()
            }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                guard AgentServer.shared.systemAsleep else { return }
                AgentServer.shared.systemAsleep = false
                AgentServer.shared.publish()
            }
        }
    }

    /// ダークウェイク中でも、ユーザー操作があったことにして画面をつけ、完全に起こす
    func wakeFully() {
        IOPMAssertionDeclareUserActivity("WakeMac: iPhoneからの起動" as CFString, kIOPMUserActiveLocal, &activityAssertion)
        systemAsleep = false
        publish()
    }

    /// 現在のネットワーク情報をTXTレコードに載せて広告し直す
    func publish() {
        let newInfo = NetworkInfo.current()
        info = newInfo
        guard let listener else { return }
        var txt = NWTXTRecord()
        txt[WakeProtocol.keyName] = macName
        txt[WakeProtocol.keyState] = systemAsleep ? WakeProtocol.stateAsleep : WakeProtocol.stateAwake
        if let i = newInfo {
            txt[WakeProtocol.keyMAC] = i.mac
            txt[WakeProtocol.keyIP] = i.ip
            txt[WakeProtocol.keyMask] = i.mask
        }
        listener.service = NWListener.Service(name: macName, type: WakeProtocol.serviceType, domain: nil, txtRecord: txt)
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
            let line = String(decoding: data ?? Data(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = line.split(separator: " ")
            let cmd = parts.first.map(String.init) ?? ""
            Task { @MainActor in
                let countdown = SleepCountdown.shared
                switch cmd {
                case WakeProtocol.cmdPing:
                    if AgentServer.shared.systemAsleep {
                        Self.reply(conn, "\(WakeProtocol.cmdPong) \(WakeProtocol.replySleeping)")
                    } else if countdown.isActive {
                        Self.reply(conn, "\(WakeProtocol.cmdPong) \(WakeProtocol.replyPending) \(countdown.remaining)")
                    } else if countdown.lastCanceledByUser {
                        Self.reply(conn, "\(WakeProtocol.cmdPong) \(WakeProtocol.replyCanceled)")
                    } else {
                        Self.reply(conn, WakeProtocol.cmdPong)
                    }
                case WakeProtocol.cmdSleep:
                    let secs = parts.count > 1 ? max(0, min(600, Int(parts[1]) ?? WakeProtocol.defaultSleepDelay))
                                               : WakeProtocol.defaultSleepDelay
                    Self.reply(conn, "\(WakeProtocol.replyCountdown) \(secs)")
                    // 返事が届いてから始める
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        countdown.start(seconds: secs) { Self.sleepNow() }
                    }
                case WakeProtocol.cmdWake:
                    AgentServer.shared.wakeFully()
                    Self.reply(conn, "OK")
                case WakeProtocol.cmdCancel:
                    countdown.cancel(byUser: false)
                    Self.reply(conn, WakeProtocol.replyCanceled)
                default:
                    conn.cancel()
                }
            }
        }
    }

    nonisolated private static func reply(_ conn: NWConnection, _ text: String) {
        conn.send(content: Data((text + "\n").utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    nonisolated static func sleepNow() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["sleepnow"]
        try? p.run()
    }

    /// 「ネットワークアクセスによってスリープを解除」(womp) が有効か確認
    func refreshWakeSetting() {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if let line = out.split(separator: "\n").first(where: { $0.contains("womp") }) {
                wakeForNetworkEnabled = line.split(separator: " ").last == "1"
            } else {
                wakeForNetworkEnabled = nil
            }
        } catch {
            wakeForNetworkEnabled = nil
        }
    }
}
