import Foundation

/// iOSアプリとMacエージェントで共有する定数
enum WakeProtocol {
    /// Bonjourサービスタイプ。Macがスリープ中もBonjour Sleep Proxyが代理広告する
    static let serviceType = "_wakemac._tcp"
    /// Bonjourで広告する「起こす用」ポート。
    /// Macが寝ている間、Apple TV / HomePod（Bonjour Sleep Proxy）がこのポートへの接続を見てMacを起こす
    static let agentPort: UInt16 = 52700
    /// 状態確認・スリープ命令用ポート（広告しない）。
    /// 広告しないので、寝ているMacに問い合わせても Sleep Proxy に起こされない
    static let controlPort: UInt16 = 52701
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
