import SwiftUI

struct AddMacView: View {
    @EnvironmentObject var store: MacStore
    @EnvironmentObject var browser: MacBrowser
    @Environment(\.dismiss) private var dismiss

    @State private var manualName = ""
    @State private var manualMAC = ""
    @State private var manualIP = ""
    @State private var manualMask = "255.255.255.0"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if browser.found.isEmpty {
                        HStack {
                            ProgressView()
                            Text("WakeMac Agent を探しています…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(browser.found, id: \.mac) { m in
                        Button {
                            store.upsert(m)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(m.name).foregroundStyle(.primary)
                                Text("\(m.ip) · \(m.mac)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("見つかったMac")
                } footer: {
                    Text("Macが起きている間に一度追加すれば、以降はスリープ中でも起動できます。")
                }

                Section("手動で追加") {
                    TextField("名前", text: $manualName)
                    TextField("MACアドレス (aa:bb:cc:dd:ee:ff)", text: $manualMAC)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField("IPアドレス", text: $manualIP)
                        .keyboardType(.decimalPad)
                        .font(.body.monospaced())
                    TextField("サブネットマスク", text: $manualMask)
                        .keyboardType(.decimalPad)
                        .font(.body.monospaced())
                    Button("追加") {
                        store.upsert(SavedMac(name: manualName.isEmpty ? "Mac" : manualName,
                                              mac: manualMAC, ip: manualIP, mask: manualMask))
                        dismiss()
                    }
                    .disabled(Waker.magicPacket(mac: manualMAC) == nil || manualIP.isEmpty)
                }
            }
            .navigationTitle("Macを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear { browser.start() }
            .onDisappear { browser.stop() }
        }
    }
}
