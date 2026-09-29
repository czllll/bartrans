import AppKit

@MainActor
enum AppMain {
    static func run() {
        // 必须在任何读取 UserDefaults 的对象（设置、历史）创建之前完成
        AppSettings.migrateSandboxDefaultsIfNeeded()

        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

await AppMain.run()
