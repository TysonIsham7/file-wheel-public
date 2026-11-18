import AppKit
import FileWheelKit
import SwiftUI

struct AboutView: View {
    var text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .textSelection(.enabled)
        }
        .frame(width: 480, height: 380)
    }
}

@MainActor
final class AboutPanel {
    private var window: NSWindow?
    private var text = "File Wheel"

    func show(report: CapabilityReport?, content: AboutContent?) {
        var lines = report?.aboutText ?? "File Wheel\nffmpeg: ffmpeg was not found. Install FFmpeg and unar with: brew install ffmpeg unar"
        if let content {
            lines += "\n\nOffered pairs: \(content.pairCount)"
            lines += "\nTools: \(content.toolCount)"
            lines += "\n\(content.readAloudSummary)"
            lines += "\n\(content.ffmpegVersionLine)"
            lines += "\n\(content.privacyLine)"
            if !content.gaps.isEmpty {
                lines += "\nGaps:"
                for gap in content.gaps {
                    lines += "\n- \(gap)"
                }
            }
        }
        text = lines
        let host = NSHostingController(rootView: AboutView(text: text))
        if window == nil {
            let window = NSWindow(contentViewController: host)
            window.title = "About File Wheel"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        } else {
            window?.contentViewController = host
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
