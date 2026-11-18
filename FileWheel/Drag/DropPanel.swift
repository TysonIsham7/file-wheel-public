import AppKit
import SwiftUI

final class WheelHostView: NSView {
    var onDragPerform: ((NSDraggingInfo) -> Bool)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onMouseUpScreen: ((NSPoint) -> Void)?

    var onKeyCode: ((UInt16, TimeInterval) -> Bool)?

    private let hosting: NSHostingView<WheelContainer>

    init(model: WheelModel) {
        hosting = InertHostingView(rootView: WheelContainer(model: model))
        super.init(frame: NSRect(x: 0, y: 0, width: WheelGeometry.panelSide, height: WheelGeometry.panelSide))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func keyDown(with event: NSEvent) {
        if onKeyCode?(event.keyCode, event.timestamp) == true { return }
        super.keyDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let window else { return }
        onMouseUpScreen?(window.convertPoint(toScreen: event.locationInWindow))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragMoved?(sender.draggingLocation)
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDragPerform?(sender) ?? false
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        true
    }
}

/// SwiftUI's hosting view would otherwise become first responder and eat arrows.
private final class InertHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }
    override func becomeFirstResponder() -> Bool { false }
}

final class DropPanel: NSPanel {
    /// Borderless windows cannot become key unless this is true. Shift-drag leaves it
    /// false so the panel does not steal the drag. Convert selection turns it on.
    var acceptsWheelKeyboard = false

    init(host: WheelHostView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: WheelGeometry.panelSide, height: WheelGeometry.panelSide),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = host
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        ignoresMouseEvents = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { acceptsWheelKeyboard }
    override var canBecomeMain: Bool { false }

    func claimKeyboard(firstResponder: NSView) {
        acceptsWheelKeyboard = true
        becomesKeyOnlyIfNeeded = false
        initialFirstResponder = firstResponder
        makeKey()
        makeFirstResponder(firstResponder)
    }

    func releaseKeyboard() {
        acceptsWheelKeyboard = false
        becomesKeyOnlyIfNeeded = true
        initialFirstResponder = nil
        if isKeyWindow { resignKey() }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard acceptsWheelKeyboard, event.type == .keyDown,
              let host = contentView as? WheelHostView,
              host.onKeyCode?(event.keyCode, event.timestamp) == true
        else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        guard acceptsWheelKeyboard, let host = contentView as? WheelHostView, host.onKeyCode?(53, ProcessInfo.processInfo.systemUptime) == true else {
            super.cancelOperation(sender)
            return
        }
    }
}
