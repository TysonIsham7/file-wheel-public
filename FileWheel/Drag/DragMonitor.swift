import AppKit
import FileWheelKit
import Foundation

struct WheelEnvironment {
    var capabilities: FFmpegCapabilities
    var imageIO: ImageIOCapabilities
    var ffmpegURL: URL?
}

@MainActor
final class DragMonitor {
    var environment: () -> WheelEnvironment = {
        WheelEnvironment(capabilities: .missing, imageIO: .current(), ffmpegURL: nil)
    }
    var onConvert: ([URL], CatalogEntry) -> Void = { _, _ in }
    var onBlocked: ([URL], String, String) -> Void = { _, _, _ in }

    private let model = WheelModel()
    private let keys = KeyCatcher()
    private let panel: DropPanel
    private let host: WheelHostView
    private var timer: Timer?
    private var session: DragSession?
    private var files: [URL] = []
    private var convertItems: [WheelItem] = []
    private var toolItems: [WheelItem] = []
    private var centerPrimary = ""
    private var centerSecondary: String?
    private var anchor: CGPoint?
    private var resolved = false
    private var consumedDrop = false
    private var suppressUntilShiftRelease = false
    private var insideDropWork: DispatchWorkItem?
    private var mouseWasDown = false
    private var generation = 0

    init() {
        host = WheelHostView(model: model)
        panel = DropPanel(host: host)
        host.onDragPerform = { [weak self] info in
            self?.performDrag(info) ?? false
        }
        host.onDragMoved = { [weak self] point in
            self?.pointerMoved(windowPoint: point)
        }
        host.onMouseUpScreen = { [weak self] screen in
            self?.selectionMouseUp(screen)
        }
        host.onKeyCode = { [weak self] keyCode, timestamp in
            self?.keys.handle(keyCode: keyCode, timestamp: timestamp) ?? false
        }
        keys.isActive = { [weak self] in self?.session != nil }
        keys.onArrow = { [weak self] step in self?.arrow(step) }
        keys.onReturn = { [weak self] in self?.pressReturn() }
        keys.onEscape = { [weak self] in self?.pressEscape() }
    }

    func start() {
        keys.start()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func showSelection(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        begin(urls: urls, at: NSEvent.mouseLocation, option: NSEvent.modifierFlags.contains(.option), origin: .selection)
    }

    private func tick() {
        keys.suppressGlobalMonitor = session?.origin.takesPanelKeyboard == true && panel.isKeyWindow
        keys.maintain()
        let flags = NSEvent.modifierFlags
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let mouseDown = (NSEvent.pressedMouseButtons & 1) == 1
        let mouse = NSEvent.mouseLocation

        guard var current = session else {
            mouseWasDown = mouseDown
            if suppressUntilShiftRelease {
                if !shift { suppressUntilShiftRelease = false }
                return
            }
            guard shift, mouseDown else { return }
            let urls = Self.fileURLs(from: NSPasteboard(name: .drag))
            guard !urls.isEmpty else { return }
            begin(urls: urls, at: mouse, option: option, origin: .drag)
            return
        }

        if option != (current.mode == .tools) {
            _ = current.reduce(.option(option))
            session = current
            sync()
        }

        if current.origin == .selection {
            ensureSelectionKeyboard()
            if mouseDown && !mouseWasDown {
                let hit = hitTest(screenPoint: mouse)
                if !hit.inside { apply(.dismissPassThrough) }
            }
            mouseWasDown = mouseDown
            return
        }

        mouseWasDown = mouseDown
        if !shift {
            let command = current.reduce(.shiftUp)
            session = current
            apply(command)
            return
        }
        if !mouseDown {
            let hit = hitTest(screenPoint: mouse)
            if hit.inside {
                scheduleInsideFallback(mouse)
            } else {
                _ = resolveMouseUp(screenPoint: mouse)
            }
            return
        }
        if Self.fileURLs(from: NSPasteboard(name: .drag)).isEmpty {
            let command = current.reduce(.pasteboardCleared)
            session = current
            apply(command)
            return
        }
        updatePointer(current: &current, screenPoint: mouse)
        session = current
        sync()
    }

    private func begin(urls: [URL], at screenPoint: CGPoint, option: Bool, origin: DragSession.Origin) {
        keys.maintain()
        insideDropWork?.cancel()
        insideDropWork = nil
        generation += 1
        let token = generation
        files = urls
        let described = urls.map(Self.sourceFile)
        applyOffer(described, option: option, origin: origin, anchor: screenPoint)
        let env = environment()
        Task {
            var probed: [SourceFile] = []
            for url in urls {
                probed.append(await SourceProbe.inspect(url: url, ffmpegURL: env.ffmpegURL))
            }
            await MainActor.run {
                guard token == self.generation, self.session != nil else { return }
                let held = NSEvent.modifierFlags.contains(.option)
                self.applyOffer(probed, option: held, origin: origin, anchor: nil)
            }
        }
    }

    private func applyOffer(_ described: [SourceFile], option: Bool, origin: DragSession.Origin, anchor: CGPoint?) {
        let env = environment()
        let offer = ConversionCatalog.offer(files: described, capabilities: env.capabilities, imageIO: env.imageIO)
        convertItems = Self.items(from: offer)
        toolItems = ToolWheel.wedges(for: files).compactMap(Self.item(from:))
        let center = Self.center(files: files, message: offer.message)
        centerPrimary = center.primary
        centerSecondary = center.secondary
        if session == nil {
            session = DragSession(
                origin: origin,
                optionHeld: option,
                convertWedgeCount: convertItems.count,
                toolsWedgeCount: toolItems.count,
                movedEnough: origin == .selection
            )
        } else if var current = session {
            current.convertWedgeCount = convertItems.count
            current.toolsWedgeCount = toolItems.count
            if let selection = current.selection, selection >= current.activeWedgeCount {
                current.selection = nil
            }
            session = current
        }
        if let anchor {
            self.anchor = anchor
            resolved = false
            consumedDrop = false
            place(near: anchor)
        }
        sync()
    }

    private func updatePointer(current: inout DragSession, screenPoint: CGPoint) {
        guard let anchor else { return }
        let distance = hypot(screenPoint.x - anchor.x, screenPoint.y - anchor.y)
        let hit = hitTest(screenPoint: screenPoint)
        _ = current.reduce(.pointer(distance: distance, wedge: hit.wedge))
    }

    private func pointerMoved(windowPoint: NSPoint) {
        guard var current = session, current.origin == .drag, !resolved else { return }
        updatePointer(current: &current, screenPoint: panel.convertPoint(toScreen: windowPoint))
        session = current
        sync()
    }

    private func selectionMouseUp(_ screen: NSPoint) {
        guard session?.origin == .selection else { return }
        _ = resolveMouseUp(screenPoint: screen)
    }

    private func performDrag(_ sender: NSDraggingInfo) -> Bool {
        resolveMouseUp(screenPoint: panel.convertPoint(toScreen: sender.draggingLocation))
    }

    private func scheduleInsideFallback(_ point: CGPoint) {
        guard insideDropWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            _ = self?.resolveMouseUp(screenPoint: point)
        }
        insideDropWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    @discardableResult
    private func resolveMouseUp(screenPoint: CGPoint) -> Bool {
        guard !resolved, var current = session else { return consumedDrop }
        let hit = hitTest(screenPoint: screenPoint)
        let command = current.reduce(.mouseUp(insidePanel: hit.inside, wedge: hit.wedge))
        session = current
        switch command {
        case .run, .dismissConsume:
            consumedDrop = true
        default:
            consumedDrop = false
        }
        resolved = true
        insideDropWork?.cancel()
        apply(command)
        return consumedDrop
    }

    private func arrow(_ step: Int) {
        guard var current = session else { return }
        _ = current.reduce(.arrow(step))
        session = current
        sync()
    }

    private func pressReturn() {
        guard var current = session else { return }
        let command = current.reduce(.returnKey)
        session = current
        apply(command)
    }

    private func pressEscape() {
        guard var current = session else { return }
        let command = current.reduce(.escape)
        session = current
        apply(command)
    }

    private func apply(_ command: SessionCommand) {
        switch command {
        case .none:
            sync()
        case .run(let index, let mode):
            let items = mode == .tools ? toolItems : convertItems
            let urls = files
            teardown()
            guard items.indices.contains(index) else { return }
            let item = items[index]
            if item.enabled {
                onConvert(urls, item.entry)
            } else {
                onBlocked(urls, item.label, item.reason ?? "Cancelled")
            }
        case .dismissConsume, .dismissPassThrough:
            teardown()
        }
    }

    private func teardown() {
        let shiftDragContinues = session?.origin == .drag
            && NSEvent.modifierFlags.contains(.shift)
            && (NSEvent.pressedMouseButtons & 1) == 1
        if shiftDragContinues { suppressUntilShiftRelease = true }
        generation += 1
        session = nil
        files = []
        anchor = nil
        panel.releaseKeyboard()
        panel.orderOut(nil)
        model.items = []
        model.selection = nil
        model.centerPrimary = ""
        model.centerSecondary = nil
    }

    private func sync() {
        guard let session else { return }
        model.mode = session.mode
        model.items = session.mode == .tools ? toolItems : convertItems
        model.selection = session.selection
        model.centerPrimary = centerPrimary
        model.centerSecondary = centerSecondary
    }

    private func place(near screenPoint: CGPoint) {
        let side = WheelGeometry.panelSide
        var origin = CGPoint(x: screenPoint.x - side / 2, y: screenPoint.y - side / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX), visible.maxX - side)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - side)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: side, height: side), display: true)
        panel.orderFrontRegardless()
        if session?.origin.takesPanelKeyboard == true {
            panel.claimKeyboard(firstResponder: host)
        } else {
            panel.releaseKeyboard()
        }
    }

    /// The status-item menu resigns key after the action returns. Reclaim until the
    /// selection panel is key and the host view, not the SwiftUI host, is first responder.
    private func ensureSelectionKeyboard() {
        guard session?.origin.takesPanelKeyboard == true else { return }
        let responderMissing = panel.firstResponder == nil || panel.firstResponder !== host
        guard !panel.isKeyWindow || responderMissing else { return }
        panel.claimKeyboard(firstResponder: host)
    }

    private func hitTest(screenPoint: CGPoint) -> (inside: Bool, wedge: Int?) {
        guard let session else { return (false, nil) }
        let frame = panel.frame
        let local = WheelGeometry.localPoint(screen: screenPoint, panelFrame: frame)
        let geometry = WheelGeometry(
            center: CGPoint(x: frame.width / 2, y: frame.height / 2),
            wedgeCount: session.activeWedgeCount
        )
        return (frame.contains(screenPoint), geometry.wedgeIndex(at: local))
    }

    private static func items(from offer: WheelOffer) -> [WheelItem] {
        offer.wedges.compactMap(item(from:))
    }

    private static func item(from wedge: Wedge) -> WheelItem? {
        switch wedge.state {
        case .hidden:
            return nil
        case .enabled:
            return WheelItem(entry: wedge.entry, enabled: true, reason: nil)
        case .disabled(let reason):
            return WheelItem(entry: wedge.entry, enabled: false, reason: reason)
        }
    }

    private static func sourceFile(_ url: URL) -> SourceFile {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let name = url.lastPathComponent.lowercased()
        let ext: String
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            ext = "tar.gz"
        } else {
            ext = url.pathExtension
        }
        return SourceFile(
            fileExtension: ext,
            isDirectory: values?.isDirectory ?? url.hasDirectoryPath,
            hasAudio: nil
        )
    }

    private static func center(files: [URL], message: String?) -> (primary: String, secondary: String?) {
        if let message { return (message, nil) }
        if files.count == 1, let file = files.first {
            let ext = file.pathExtension.isEmpty ? "FILE" : file.pathExtension.uppercased()
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            let formatted = size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            return (ext, formatted)
        }
        return ("\(files.count) files", nil)
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls
        }
        let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let names = pasteboard.propertyList(forType: legacy) as? [String], !names.isEmpty {
            return names.map { URL(fileURLWithPath: $0) }
        }
        return []
    }
}
