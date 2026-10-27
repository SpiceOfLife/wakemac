import Foundation

/// iOSアプリとMacエージェントで共有する定数
enum WakeProtocol {
    /// Bonjourサービスタイプ。Macがスリープ中もBonjour Sleep Proxyが代理広告する
    static let serviceType = "_wakemac._tcp"
    /// Macエージェントが待ち受けるTCPポート（固定にしておくとBonjourが無くても到達できる）
    static let agentPort: UInt16 = 52700
    /// Wake-on-LANの送信先UDPポート（一般的に 9 か 7）
    static let wolPorts: [UInt16] = [9, 7]

    // TXTレコードのキー
    static let keyMAC = "mac"
    static let keyIP = "ip"
    static let keyMask = "mask"
    static let keyName = "name"

    // TCPコマンド
    static let cmdPing = "PING"
    static let cmdPong = "PONG"
    static let cmdSleep = "SLEEP"
}
