import AppKit
import SwiftUI

struct ProgressRoot: View {
    @ObservedObject var queue: ConversionQueue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if queue.rows.isEmpty {
                    Text("No conversions running")
                        .foregroundStyle(.secondary)
                }
                ForEach(queue.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.fileName).lineLimit(1)
                            Spacer(minLength: 8)
                            if row.status == .queued || row.status == .running {
                                Button("Cancel") { queue.cancel(row.id) }
                            }
                        }
                        Text(row.action)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: row.fraction)
                        if let detail = row.detail, row.status == .failed || row.status == .cancelled {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(row.status == .failed ? Color.red : Color.secondary)
                        }
                    }
                }
                if queue.showRevealButton {
                    Button("Show in Finder") { queue.reveal() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(width: 420, height: 280)
    }
}

@MainActor
final class ProgressWindowController {
    private let queue: ConversionQueue
    private var window: NSWindow?

    init(queue: ConversionQueue) {
        self.queue = queue
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: ProgressRoot(queue: queue))
            let window = NSWindow(contentViewController: host)
            window.title = "File Wheel"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
