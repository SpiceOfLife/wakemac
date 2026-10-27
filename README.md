# WakeMac

iPhoneのボタン1つで、スリープ中のMacを起こすアプリ。

- 紹介サイト: https://wakemac.ours-blanc.app/
- Mac版（WakeMac Agent）: [最新リリースをダウンロード](https://github.com/SpiceOfLife/wakemac/releases/latest/download/WakeMac-Agent-macOS.zip)
- iPhone版: App Store 公開準備中（下の手順でソースからビルドできます）
- プライバシーポリシー: https://wakemac.ours-blanc.app/privacy/

- **WakeMac（iOS）** … 大きな電源ボタン。押すとMacへ起動信号を送り、起動を確認すると緑に変わる
- **WakeMac Agent（macOS）** … メニューバー常駐。自分のMACアドレス/IPをBonjourで広告し、iPhoneからの確認・スリープ命令に応答

## ビルド

`WakeMac.xcodeproj` をそのまま Xcode で開けます（Xcode 16 以降）。
プロジェクトファイルは `design/genproj.py` から生成しています（ファイルを足したら `python3 design/genproj.py .` を再実行）。

1. `WakeMacAgent` スキームを選んで Mac で実行（メニューバーに電源アイコン）
2. メニューの「ログイン時に起動」をON
3. `WakeMac` スキームで iPhone に実行（Signing の Team を設定）
4. iPhoneで「+」→ 見つかったMacをタップして登録（Macが起きている間に1回だけ）

## Mac側の必須設定

システム設定 → バッテリー（デスクトップは「エネルギー」）→ オプション →
**「ネットワークアクセスによるスリープ解除」** を「常に」または「電源アダプタ接続時のみ」に。
Agentのメニューに現在の状態が表示されます。ターミナルなら `sudo pmset -a womp 1`。

## 起動の仕組み

ボタンを押すと次を順に試します。

1. 最後に分かっているMacのIPへ Wake-on-LAN マジックパケット（UDP 9/7）
2. サブネットのブロードキャストへマジックパケット
3. AgentのTCPポート（52700）へ接続 → 家に **Apple TV / HomePod** があれば Bonjour Sleep Proxy が代わりにMacを起こす

その後2秒おきに最大30秒、Agentに PING して起動を確認します。

## 起きない時のチェック

| 状況 | 対処 |
|---|---|
| **有線LAN接続のMac** | 最も確実。上の設定だけでOK |
| **Wi‑Fi接続のMac** | 深いスリープ中はWi‑Fiが切れるため、マジックパケット単体では届かないことが多い。Apple TV / HomePod（Sleep Proxy）があると③で起きる |
| ブロードキャストが届かない | iOSはブロードキャスト送信に `com.apple.developer.networking.multicast` エンタイトルメントが必要（Appleに申請）。無くても①③は動く |
| 初回だけ失敗する | iOSの「ローカルネットワーク」許可ダイアログで許可したか確認（設定 → プライバシー → ローカルネットワーク） |
| IPが変わった | Macが起きている時に「+」から追加し直すと上書き更新される。ルーターでDHCP固定割当にしておくと楽 |

## 注意

- Agentの `SLEEP` コマンドは同じLANの誰でも送れます。家庭内LANでの利用を想定しています
- 外出先からの起動は対象外（同じLAN内のみ）。必要ならVPN（Tailscale等）経由で同じLANに入る形が簡単です

## リリース

`VERSION` の版を上げて main に push すると、GitHub Actions が iOS アプリのビルド確認と、Mac エージェント（Universal・ad-hoc署名）の zip 作成を行い、その版のタグと GitHub Release を作って zip を添付します（同じ版がすでにあれば何もしません）。

## ライセンス

MIT
