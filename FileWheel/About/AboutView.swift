import Foundation

#if canImport(SwiftUI)
import SwiftUI

public struct AboutView: View {
    public var content: AboutContent

    public init(content: AboutContent) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Wheel")
                .font(.title2.weight(.semibold))
            Text("\(content.pairCount) conversion pairs")
            Text("\(content.toolCount) tools")
            Text(content.readAloudSummary)
                .fixedSize(horizontal: false, vertical: true)
            Text(content.ffmpegVersionLine)
            if content.gaps.isEmpty {
                Text("No known encoder gaps.")
            } else {
                ForEach(content.gaps, id: \.self) { gap in
                    Text(gap)
                }
            }
            Text(content.privacyLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
    }
}

public struct QueueListView: View {
    public var items: [QueueItem]
    public var isPaused: Bool
    public var onCancel: (UUID) -> Void
    public var onReveal: ([URL]) -> Void

    public init(items: [QueueItem], isPaused: Bool, onCancel: @escaping (UUID) -> Void, onReveal: @escaping ([URL]) -> Void) {
        self.items = items
        self.isPaused = isPaused
        self.onCancel = onCancel
        self.onReveal = onReveal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isPaused ? "Queue paused" : "Queue")
                .font(.headline)
            if items.isEmpty {
                Text("Nothing queued.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                    if item.state == .running {
                        ProgressView()
                    } else {
                        ProgressView(value: item.progress)
                    }
                    Text(status(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        if item.state == .waiting || item.state == .running {
                            Button("Cancel") { onCancel(item.id) }
                        }
                        if !item.outputs.isEmpty {
                            Button("Show in Finder") { onReveal(item.outputs) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
    }

    private func status(_ item: QueueItem) -> String {
        switch item.state {
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .finished: return item.message.isEmpty ? "Finished" : item.message
        case .failed(let message): return message
        case .cancelled: return "Cancelled"
        }
    }
}
#endif
