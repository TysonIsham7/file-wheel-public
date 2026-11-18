import AppKit
import FileWheelKit

@MainActor
final class StatusItemController: NSObject {
    var onConvertSelection: () -> Void
    var onShowQueue: () -> Void
    var onAbout: () -> Void
    var onTogglePause: () -> Void
    var onSettings: () -> Void

    private let queue: ConversionQueue
    private var statusItem: NSStatusItem?

    init(
        queue: ConversionQueue,
        onConvertSelection: @escaping () -> Void,
        onShowQueue: @escaping () -> Void,
        onAbout: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.queue = queue
        self.onConvertSelection = onConvertSelection
        self.onShowQueue = onShowQueue
        self.onAbout = onAbout
        self.onTogglePause = onTogglePause
        self.onSettings = onSettings
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.icon()
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "File Wheel"
        let menu = NSMenu()
        menu.addItem(make(MenuBarSpec.convertSelection, #selector(convertSelection(_:))))
        menu.addItem(make(queue.isPaused ? MenuBarSpec.resumeQueue : MenuBarSpec.pauseQueue, #selector(togglePause(_:))))
        menu.addItem(make(MenuBarSpec.showQueue, #selector(showQueue(_:))))
        menu.addItem(.separator())
        menu.addItem(make(MenuBarSpec.settings, #selector(showSettings(_:))))
        menu.addItem(make(MenuBarSpec.about, #selector(showAbout(_:))))
        menu.addItem(.separator())
        let quit = make(MenuBarSpec.quit, #selector(quit(_:)))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        queue.onChange = { [weak self] in
            self?.updateCount()
            self?.rebuildPauseTitle()
        }
        updateCount()
    }

    private func rebuildPauseTitle() {
        guard let menu = statusItem?.menu, menu.items.count > 1 else { return }
        menu.items[1].title = queue.isPaused ? MenuBarSpec.resumeQueue : MenuBarSpec.pauseQueue
    }

    private func make(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func updateCount() {
        let count = queue.queueCount
        statusItem?.button?.title = count > 0 ? " \(count)" : ""
    }

    @objc private func convertSelection(_ sender: Any?) { onConvertSelection() }
    @objc private func showQueue(_ sender: Any?) { onShowQueue() }
    @objc private func showAbout(_ sender: Any?) { onAbout() }
    @objc private func togglePause(_ sender: Any?) { onTogglePause() }
    @objc private func showSettings(_ sender: Any?) { onSettings() }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private static func icon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect.insetBy(dx: 2, dy: 2))
            let center = CGPoint(x: rect.midX, y: rect.midY)
            for index in 0..<4 {
                let angle = CGFloat(index) * (.pi / 2)
                context.move(to: CGPoint(x: center.x + cos(angle) * 2.4, y: center.y + sin(angle) * 2.4))
                context.addLine(to: CGPoint(x: center.x + cos(angle) * 6.0, y: center.y + sin(angle) * 6.0))
            }
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
