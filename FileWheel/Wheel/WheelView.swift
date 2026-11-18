import FileWheelKit
import SwiftUI

struct WheelItem: Equatable, Identifiable {
    var id: String { entry.id }
    var entry: CatalogEntry
    var enabled: Bool
    var reason: String?

    var label: String { entry.label }
}

@MainActor
final class WheelModel: ObservableObject {
    @Published var items: [WheelItem] = []
    @Published var selection: Int?
    @Published var centerPrimary = ""
    @Published var centerSecondary: String?
    @Published var mode: WheelMode = .convert
}

struct WheelContainer: View {
    @ObservedObject var model: WheelModel

    var body: some View {
        WheelView(
            items: model.items,
            selection: model.selection,
            centerPrimary: model.centerPrimary,
            centerSecondary: model.centerSecondary,
            mode: model.mode
        )
        .allowsHitTesting(false)
    }
}

struct WheelView: View {
    var items: [WheelItem]
    var selection: Int?
    var centerPrimary: String
    var centerSecondary: String?
    var mode: WheelMode

    private var center: CGPoint {
        CGPoint(x: WheelGeometry.panelSide / 2, y: WheelGeometry.panelSide / 2)
    }

    var body: some View {
        let geometry = WheelGeometry(center: center, wedgeCount: items.count)
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: WheelGeometry.diameter, height: WheelGeometry.diameter)
            Circle()
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                .frame(width: WheelGeometry.diameter, height: WheelGeometry.diameter)
            ForEach(Array(zip(items, geometry.slots())), id: \.0.id) { item, slot in
                let highlighted = selection == slot.index
                wedgePath(slot)
                    .fill(fill(highlighted: highlighted, enabled: item.enabled))
                wedgePath(slot)
                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                Text(item.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.enabled ? Color.primary : Color.secondary)
                    .position(labelPoint(slot))
            }
            VStack(spacing: 2) {
                Text(centerPrimary)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)
                if let centerSecondary {
                    Text(centerSecondary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 130)
        }
        .frame(width: WheelGeometry.panelSide, height: WheelGeometry.panelSide)
        .animation(.easeInOut(duration: 0.15), value: mode)
    }

    private func fill(highlighted: Bool, enabled: Bool) -> Color {
        if highlighted && enabled { return Color.accentColor.opacity(0.42) }
        if highlighted { return Color.primary.opacity(0.16) }
        return Color.primary.opacity(enabled ? 0.08 : 0.04)
    }

    private func labelPoint(_ slot: WheelGeometry.Slot) -> CGPoint {
        let mid = (slot.startAngle + slot.endAngle) / 2
        return WheelGeometry.point(center: center, radius: slot.labelRadius, clockwiseFromTop: mid)
    }

    private func wedgePath(_ slot: WheelGeometry.Slot) -> Path {
        var path = Path()
        let steps = 28
        path.move(to: WheelGeometry.point(center: center, radius: slot.innerRadius, clockwiseFromTop: slot.startAngle))
        for step in 0...steps {
            let t = slot.startAngle + (slot.endAngle - slot.startAngle) * CGFloat(step) / CGFloat(steps)
            path.addLine(to: WheelGeometry.point(center: center, radius: slot.outerRadius, clockwiseFromTop: t))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let t = slot.startAngle + (slot.endAngle - slot.startAngle) * CGFloat(step) / CGFloat(steps)
            path.addLine(to: WheelGeometry.point(center: center, radius: slot.innerRadius, clockwiseFromTop: t))
        }
        path.closeSubpath()
        return path
    }
}
