import CoreGraphics
import Foundation

struct WheelGeometry: Equatable {
    static let diameter: CGFloat = 280
    static let margin: CGFloat = 24
    static let centerDeadZone: CGFloat = 46
    static let firstRingCapacity = 8
    static var radius: CGFloat { diameter / 2 }
    static var panelSide: CGFloat { diameter + margin * 2 }

    struct Slot: Equatable {
        var index: Int
        var startAngle: CGFloat
        var endAngle: CGFloat
        var innerRadius: CGFloat
        var outerRadius: CGFloat
        var labelRadius: CGFloat
    }

    var center: CGPoint
    var wedgeCount: Int

    static func localPoint(screen: CGPoint, panelFrame: CGRect) -> CGPoint {
        CGPoint(x: screen.x - panelFrame.minX, y: panelFrame.maxY - screen.y)
    }

    static func point(center: CGPoint, radius: CGFloat, clockwiseFromTop angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + sin(angle) * radius,
            y: center.y - cos(angle) * radius
        )
    }

    func slots() -> [Slot] {
        guard wedgeCount > 0 else { return [] }
        if wedgeCount <= Self.firstRingCapacity {
            return slots(from: 0, count: wedgeCount, inner: Self.centerDeadZone + 6, outer: Self.radius)
        }
        let outerCount = Self.firstRingCapacity
        let innerCount = wedgeCount - outerCount
        let boundary = (Self.centerDeadZone + Self.radius) / 2
        let outer = slots(from: 0, count: outerCount, inner: boundary + 2, outer: Self.radius)
        let inner = slots(from: outerCount, count: innerCount, inner: Self.centerDeadZone + 4, outer: boundary - 2)
        return outer + inner
    }

    func wedgeIndex(at point: CGPoint) -> Int? {
        guard wedgeCount > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= Self.centerDeadZone, distance <= Self.radius else { return nil }
        let angle = Self.clockwiseFromTop(dx: dx, dy: dy)
        let boundary = (Self.centerDeadZone + Self.radius) / 2
        if wedgeCount <= Self.firstRingCapacity {
            return index(angle: angle, count: wedgeCount, indexOffset: 0)
        }
        if distance >= boundary {
            return index(angle: angle, count: Self.firstRingCapacity, indexOffset: 0)
        }
        return index(angle: angle, count: wedgeCount - Self.firstRingCapacity, indexOffset: Self.firstRingCapacity)
    }

    private func slots(from offset: Int, count: Int, inner: CGFloat, outer: CGFloat) -> [Slot] {
        guard count > 0 else { return [] }
        let step = (2 * CGFloat.pi) / CGFloat(count)
        return (0..<count).map { index in
            let start = CGFloat(index) * step
            return Slot(
                index: offset + index,
                startAngle: start,
                endAngle: start + step,
                innerRadius: inner,
                outerRadius: outer,
                labelRadius: (inner + outer) / 2
            )
        }
    }

    private func index(angle: CGFloat, count: Int, indexOffset: Int) -> Int {
        let step = (2 * CGFloat.pi) / CGFloat(count)
        var value = Int(angle / step)
        if value >= count { value = count - 1 }
        if value < 0 { value = 0 }
        return indexOffset + value
    }

    private static func clockwiseFromTop(dx: CGFloat, dy: CGFloat) -> CGFloat {
        let angle = atan2(dx, -dy)
        return angle < 0 ? angle + (2 * .pi) : angle
    }
}
