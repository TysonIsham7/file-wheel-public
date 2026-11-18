import AppKit

@main
enum FileWheelMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.delegate = AppDelegate.shared
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
