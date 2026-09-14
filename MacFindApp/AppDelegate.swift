import AppKit

/// 单实例兜底:即使有人直接执行可执行文件(绕过 LaunchServices),
/// 第二个实例也会主动激活已有实例并退出。
/// 系统级保护见 Info.plist 的 `LSMultipleInstancesProhibited`。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }

        if let existing = others.first {
            existing.activate(options: [])
            NSApp.terminate(nil)
        }
    }

    /// 点 Dock 图标时把窗口重新带到前台。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
