import AppKit

@MainActor
enum AppMain {
    static func run() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

await AppMain.run()
