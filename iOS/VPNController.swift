import Foundation
import NetworkExtension
import Security

/// 自宅ルーターの IKEv2 VPN 設定（パスワード類はキーチェーンに保存）
struct VPNSettings: Codable, Equatable {
    enum Auth: String, Codable, CaseIterable, Identifiable {
        case usernamePassword   // EAP（ユーザー名＋パスワード）
        case sharedSecret       // 事前共有鍵（PSK）
        var id: String { rawValue }
        var label: String { self == .usernamePassword ? "ユーザー名とパスワード" : "事前共有鍵（PSK）" }
    }

    var enabled = false
    var server = ""          // 例: home.example.com（DDNS）
    var remoteID = ""        // 空ならサーバー名と同じ
    var localID = ""
    var auth: Auth = .usernamePassword
    var username = ""

    var isComplete: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        (auth == .sharedSecret || !username.isEmpty)
    }
}

enum VPNError: LocalizedError {
    case notConfigured, timeout, failed(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "VPNが設定されていません"
        case .timeout: return "VPNにつながりませんでした"
        case .failed(let s): return s
        }
    }
}

/// 外出先から使うときだけ自宅にVPN接続し、終わったら切る
@MainActor
final class VPNController: ObservableObject {
    static let shared = VPNController()

    @Published var settings: VPNSettings { didSet { saveSettings() } }
    @Published private(set) var status: NEVPNStatus = .invalid
    /// このアプリが自分でつないだ接続か（自分でつないだものだけ自分で切る）
    @Published private(set) var startedByApp = false

    private let settingsKey = "vpnSettings.v1"
    private let manager = NEVPNManager.shared()
    private var observer: NSObjectProtocol?

    private init() {
        if let d = UserDefaults.standard.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(VPNSettings.self, from: d) {
            settings = s
        } else {
            settings = VPNSettings()
        }
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.status = NEVPNManager.shared().connection.status }
        }
        Task { try? await load(); status = manager.connection.status }
    }

    private func saveSettings() {
        if let d = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(d, forKey: settingsKey)
        }
    }

    var isConnected: Bool { status == .connected }

    var statusText: String {
        switch status {
        case .connected: return "接続中"
        case .connecting: return "接続しています…"
        case .disconnecting: return "切断しています…"
        case .reasserting: return "再接続しています…"
        case .disconnected: return "未接続"
        case .invalid: return "未設定"
        @unknown default: return "—"
        }
    }

    // MARK: - 秘密情報（キーチェーン）

    func setPassword(_ value: String) { Keychain.set(value, account: "vpn.password") }
    func setSharedSecret(_ value: String) { Keychain.set(value, account: "vpn.sharedSecret") }
    var hasPassword: Bool { Keychain.persistentRef(account: "vpn.password") != nil }
    var hasSharedSecret: Bool { Keychain.persistentRef(account: "vpn.sharedSecret") != nil }

    // MARK: - iOS の VPN 設定に保存

    private func load() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { e in e.map { c.resume(throwing: $0) } ?? c.resume() }
        }
    }

    /// 設定を iOS に登録する（初回は「VPN構成の追加」の確認が出る）
    func apply() async throws {
        try await load()
        let s = settings
        guard s.isComplete else { throw VPNError.notConfigured }

        let p = NEVPNProtocolIKEv2()
        p.serverAddress = s.server.trimmingCharacters(in: .whitespaces)
        p.remoteIdentifier = s.remoteID.isEmpty ? p.serverAddress : s.remoteID
        p.localIdentifier = s.localID.isEmpty ? nil : s.localID
        p.disconnectOnSleep = true
        switch s.auth {
        case .usernamePassword:
            p.authenticationMethod = .none
            p.useExtendedAuthentication = true
            p.username = s.username
            p.passwordReference = Keychain.persistentRef(account: "vpn.password")
        case .sharedSecret:
            p.authenticationMethod = .sharedSecret
            p.useExtendedAuthentication = !s.username.isEmpty
            if !s.username.isEmpty {
                p.username = s.username
                p.passwordReference = Keychain.persistentRef(account: "vpn.password")
            }
            p.sharedSecretReference = Keychain.persistentRef(account: "vpn.sharedSecret")
        }

        manager.protocolConfiguration = p
        manager.localizedDescription = "WakeMac（自宅）"
        manager.isEnabled = true
        manager.isOnDemandEnabled = false   // 使うときだけ。常時接続はしない

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { e in e.map { c.resume(throwing: $0) } ?? c.resume() }
        }
        try await load()
        status = manager.connection.status
    }

    /// VPNをつないで、つながるまで待つ
    func connect(timeout: TimeInterval = 20) async throws {
        guard settings.enabled, settings.isComplete else { throw VPNError.notConfigured }
        if manager.connection.status == .connected { return }
        if manager.protocolConfiguration == nil { try await apply() } else { try await load() }
        do {
            try manager.connection.startVPNTunnel()
        } catch {
            // 設定が古い・無効になっている場合は保存し直して再試行
            try await apply()
            try manager.connection.startVPNTunnel()
        }
        startedByApp = true
        let deadline = Date().addingTimeInterval(timeout)
        var sawConnecting = false
        while Date() < deadline {
            switch manager.connection.status {
            case .connected:
                status = .connected
                return
            case .connecting, .reasserting:
                sawConnecting = true
            case .disconnected, .invalid:
                // 接続を試みたあとで切れた＝認証やサーバー名の誤り
                if sawConnecting {
                    startedByApp = false
                    throw VPNError.failed("VPNにつながりませんでした。サーバー名・ID・パスワードを確認してください")
                }
            default: break
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        disconnectIfStartedByApp()
        throw VPNError.timeout
    }

    /// 外出先機能をオフにしたとき：VPN構成とキーチェーンの秘密情報を消す
    func removeAll() async {
        disconnectIfStartedByApp()
        Keychain.set("", account: "vpn.password")
        Keychain.set("", account: "vpn.sharedSecret")
        try? await load()
        if manager.protocolConfiguration != nil {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                manager.removeFromPreferences { _ in c.resume() }
            }
        }
        status = .invalid
    }

    func disconnectIfStartedByApp() {
        guard startedByApp else { return }
        startedByApp = false
        manager.connection.stopVPNTunnel()
    }
}

/// キーチェーンの汎用パスワード。NEVPNProtocol には「永続参照」で渡す必要がある
enum Keychain {
    private static let service = "app.oursblanc.wakemac.vpn"

    static func set(_ value: String, account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func persistentRef(account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnPersistentRef as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}
