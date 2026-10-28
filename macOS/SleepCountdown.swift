import AppKit
import SwiftUI

/// iPhoneからスリープを指示されたとき、Macの画面にカウントダウンを出す。
/// Macの前にいる人は「キャンセル」で止められる。
@MainActor
final class SleepCountdown: ObservableObject {
    static let shared = SleepCountdown()

    @Published private(set) var remaining: Int = 0
    @Published private(set) var isActive = false
    /// 直前のカウントダウンがMac側でキャンセルされたか（iPhoneに伝える）
    @Published private(set) var lastCanceledByUser = false

    private var timer: Timer?
    private var panel: NSPanel?
    private var onFinish: (() -> Void)?

    /// カウントダウンを始める。0秒ならすぐ実行
    func start(seconds: Int, onFinish: @escaping () -> Void) {
        lastCanceledByUser = false
        guard seconds > 0 else { onFinish(); return }
        // 実行中なら残り時間だけ更新
        self.onFinish = onFinish
        remaining = seconds
        if isActive { return }
        isActive = true
        showPanel()
        NSSound(named: "Ping")?.play()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 3 && remaining > 0 { NSSound(named: "Tink")?.play() }
        if remaining <= 0 { finish() }
    }

    /// 今すぐ実行
    func finishNow() { finish() }

    /// 止める（byUser: Macの前の人が止めた）
    func cancel(byUser: Bool) {
        guard isActive else { return }
        lastCanceledByUser = byUser
        stop()
    }

    private func finish() {
        let action = onFinish
        stop()
        action?()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remaining = 0
        onFinish = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func showPanel() {
        let view = CountdownView(model: self)
        let hosting = NSHostingView(rootView: view)
        let size = NSSize(width: 360, height: 240)
        hosting.frame = NSRect(origin: .zero, size: size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow, .utilityWindow],
                        backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .screenSaver          // フルスクリーンのアプリより手前
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.contentView = hosting
        p.center()
        p.orderFrontRegardless()
        panel = p
    }
}

private struct CountdownView: View {
    @ObservedObject var model: SleepCountdown

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.fill")
                .font(.system(size: 26))
                .foregroundStyle(.indigo)
            Text("iPhoneからスリープが指示されました")
                .font(.headline)
            Text("\(model.remaining)")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: model.remaining)
            Text("秒後にこのMacをスリープします")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("キャンセル") { model.cancel(byUser: true) }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("今すぐスリープ") { model.finishNow() }
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 360, height: 240)
    }
}
