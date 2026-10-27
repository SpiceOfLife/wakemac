# WakeMac — App Store 提出用メモ

## 基本情報

| 項目 | 内容 |
|---|---|
| アプリ名 | WakeMac |
| サブタイトル（30文字以内） | ボタン1つでMacをスリープから起動 |
| バンドルID | app.oursblanc.wakemac |
| SKU | wakemac-ios |
| プライマリカテゴリ | ユーティリティ |
| セカンダリカテゴリ | 仕事効率化 |
| 価格 | 無料 |
| 年齢制限 | 4+（該当項目すべて「なし」） |
| 著作権 | 2026 ours-blanc |
| サポートURL | https://wakemac.ours-blanc.app/ |
| マーケティングURL | https://wakemac.ours-blanc.app/ |
| プライバシーポリシーURL | https://wakemac.ours-blanc.app/privacy/ |

## プロモーション用テキスト（170文字以内）

寝ているMacのところまで行かなくていい。iPhoneのボタンを1回押すと、スリープ中のMacが立ち上がります。無料・オープンソース。

## 説明文

WakeMac は、iPhone のボタンを1回押すだけで、スリープしている Mac を起こせるアプリです。

【使い方】
1. Mac に無料の「WakeMac Agent」を入れる（wakemac.ours-blanc.app からダウンロード）
2. 同じ Wi‑Fi で「＋」を押し、見つかった Mac をタップして登録
3. あとは大きな電源ボタンを押すだけ。起動を確認するとボタンが緑に変わります

【できること】
・スリープ中の Mac を起動（Wake-on-LAN）
・Apple TV や HomePod がある家では、Wi‑Fi 接続の Mac も起こせます（Bonjour Sleep Proxy）
・Mac が起きているかの確認
・iPhone から Mac をスリープ
・複数の Mac を登録

【必要なもの】
・Mac に WakeMac Agent（macOS 13 以降）
・Mac の「ネットワークアクセスによるスリープ解除」をオン
・iPhone と Mac が同じネットワークにあること

【プライバシー】
データは一切収集しません。通信は家のネットワークの中だけで行います。

## キーワード（100文字以内・カンマ区切り）

Mac,起動,スリープ,解除,Wake on LAN,WOL,リモート,電源,MacBook,iMac,Mac mini,ネットワーク,ウェイク

## App プライバシー（App Store Connect の質問への回答）

- データの収集：**収集しない（Data Not Collected）**
- トラッキング：しない

## 輸出コンプライアンス

`ITSAppUsesNonExemptEncryption = false` を Info.plist に設定済み（独自暗号なし）。

## 審査メモ（App Review への説明）

This app wakes a Mac on the same local network using Wake-on-LAN. To test it, install the free companion app "WakeMac Agent" on a Mac (https://github.com/SpiceOfLife/wakemac/releases/latest), open it, then tap "+" in the iOS app to add the Mac. The app needs Local Network permission to discover the Mac via Bonjour (_wakemac._tcp) and to send the wake packet. No account or login is required, and no data leaves the local network.

## スクリーンショット

必要サイズ：6.9インチ（1320×2868）。iPad も対象なら 13インチ（2064×2752）も。
Xcode のシミュレーター（iPhone 17 Pro Max など）でアプリを起動し、⌘S で保存。

1. Mac が1台登録された画面（大きな電源ボタン）
2. 起動して緑になった画面
3. 「Macを追加」で見つかった Mac が並んでいる画面
4. 複数の Mac を登録した一覧

## アイコン

`iOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png`（1024×1024・透過なし）
