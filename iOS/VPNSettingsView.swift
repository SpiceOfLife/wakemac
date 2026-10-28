import SwiftUI
import NetworkExtension

/// 外出先から使うための、自宅ルーターの IKEv2 VPN 設定
struct VPNSettingsView: View {
    @ObservedObject private var vpn = VPNController.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draft = VPNSettings()
    @State private var password = ""
    @State private var sharedSecret = ""
    @State private var saving = false
    @State private var testing = false
    @State private var message: String?
    @State private var messageIsError = false
    @AppStorage("sleepDelay") private var sleepDelay = WakeProtocol.defaultSleepDelay

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $sleepDelay, in: 0...120, step: 5) {
                        LabeledContent("カウントダウン", value: sleepDelay == 0 ? "なし（すぐスリープ）" : "\(sleepDelay)秒")
                    }
                } header: {
                    Text("スリープするとき")
                } footer: {
                    Text("Macの画面にカウントダウンを出してからスリープします。Macの前にいる人は「キャンセル」で止められます。")
                }

                Section {
                    Toggle("外出先ではVPNで家につなぐ", isOn: $draft.enabled)
                } header: {
                    Text("外出先から使う")
                } footer: {
                    Text("家のWi‑Fiにいないときだけ、アプリを開いている間VPNで家のネットワークにつなぎ、閉じると切断します。")
                }

                if draft.enabled {
                    Section("ルーターのVPNサーバー（IKEv2）") {
                        LabeledContent("サーバー") {
                            TextField("例: myhome.aa0.netvolante.jp", text: $draft.server)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("リモートID") {
                            TextField("空欄ならサーバーと同じ", text: $draft.remoteID)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("ローカルID") {
                            TextField("任意", text: $draft.localID)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Section {
                        Picker("認証", selection: $draft.auth) {
                            ForEach(VPNSettings.Auth.allCases) { Text($0.label).tag($0) }
                        }
                        if draft.auth == .sharedSecret {
                            SecureField(vpn.hasSharedSecret ? "保存済み（変更するときだけ入力）" : "事前共有鍵", text: $sharedSecret)
                        }
                        TextField(draft.auth == .sharedSecret ? "ユーザー名（ルーターが求める場合のみ）" : "ユーザー名", text: $draft.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if draft.auth == .usernamePassword || !draft.username.isEmpty {
                            SecureField(vpn.hasPassword ? "保存済み（変更するときだけ入力）" : "パスワード", text: $password)
                        }
                    } header: {
                        Text("認証")
                    } footer: {
                        Text("パスワードと事前共有鍵は、このiPhoneのキーチェーンにだけ保存します。この機能をオフにして保存すると削除されます。")
                    }

                    Section {
                        LabeledContent("状態", value: vpn.statusText)
                        Button {
                            Task { await test() }
                        } label: {
                            HStack {
                                Text("接続テスト")
                                if testing { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(!draft.isComplete || testing || saving)
                    } footer: {
                        Text("初回は iOS の「VPN構成の追加」の確認が出るので「許可」を選んでください。")
                    }
                }

                if let message {
                    Section {
                        Text(message).foregroundStyle(messageIsError ? Color.orange : Color.green)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { if await save() { dismiss() } } }
                        .disabled(saving || (draft.enabled && !draft.isComplete))
                }
            }
            .onAppear { draft = vpn.settings }
        }
    }

    /// 入力内容を保存し、iOS の VPN 構成に反映する
    @discardableResult
    private func save() async -> Bool {
        saving = true
        defer { saving = false }
        if !password.isEmpty { vpn.setPassword(password); password = "" }
        if !sharedSecret.isEmpty { vpn.setSharedSecret(sharedSecret); sharedSecret = "" }
        vpn.settings = draft
        guard draft.enabled else {
            await vpn.removeAll()   // オフにしたら構成とパスワードを消す
            return true
        }
        do {
            try await vpn.apply()
            return true
        } catch {
            show(error.localizedDescription, error: true)
            return false
        }
    }

    private func test() async {
        guard await save() else { return }
        testing = true
        defer { testing = false }
        do {
            try await vpn.connect()
            show("つながりました。自宅のネットワークに入れています。", error: false)
            vpn.disconnectIfStartedByApp()
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}
