import AppKit
import ApplicationServices
import CoreGraphics

final class KeyCatcher {
    var isActive: () -> Bool = { false }
    var onArrow: (Int) -> Void = { _ in }
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}
    /// Set while the wheel panel is key. A global monitor would also see those keys
    /// and step the selection twice.
    var suppressGlobalMonitor = false

    private var machPort: CFMachPort?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var didPrompt = false
    private var lastDelivery: (code: UInt16, timestamp: TimeInterval)?

    func start() {
        if !installTap() {
            promptForAccessibilityIfNeeded()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handle(keyCode: event.keyCode, timestamp: event.timestamp) == true {
                return nil
            }
            return event
        }
        maintain()
    }

    /// Menu tracking and the blocking Finder AppleScript stall the main run loop.
    /// The system then disables the session tap and the disable callback never runs.
    /// Shift-drag never hits that stall, so its keys keep arriving. Poll the tap and,
    /// while it is off, listen globally for keys that are going to other apps.
    func maintain() {
        if let port = machPort, !CGEvent.tapIsEnabled(tap: port) {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        let tapOn = machPort.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        if tapOn || suppressGlobalMonitor {
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
            return
        }
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(keyCode: event.keyCode, timestamp: event.timestamp)
        }
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let catcher = Unmanaged<KeyCatcher>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = catcher.machPort {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let timestamp = Double(event.timestamp) / 1_000_000_000
                if catcher.handle(keyCode: keyCode, timestamp: timestamp) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        machPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func promptForAccessibilityIfNeeded() {
        guard !didPrompt else { return }
        didPrompt = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func handle(keyCode: UInt16, timestamp: TimeInterval) -> Bool {
        guard isActive(), let action = WheelKeyAction.from(keyCode: keyCode) else { return false }
        if let lastDelivery, lastDelivery.code == keyCode, abs(lastDelivery.timestamp - timestamp) < 0.001 {
            return true
        }
        lastDelivery = (keyCode, timestamp)
        switch action {
        case .cancel:
            onEscape()
        case .confirm:
            onReturn()
        case .arrow(let step):
            onArrow(step)
        }
        return true
    }
}
