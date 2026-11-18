import CoreGraphics
import Foundation

enum WheelMode: Equatable {
    case convert
    case tools
}

struct DragSession: Equatable {
    enum Origin: Equatable {
        case drag
        case selection

        /// Shift-drag keeps the key window in Finder so the drag is not cancelled.
        /// Convert selection has no drag. The status item leaves this process active
        /// with no key window, and a session event tap does not see keys routed here.
        var takesPanelKeyboard: Bool { self == .selection }
    }

    static let movementThreshold: CGFloat = 4

    var origin: Origin
    var mode: WheelMode
    var convertWedgeCount: Int
    var toolsWedgeCount: Int
    var selection: Int?
    var movedEnough: Bool
    var keyboardArmed: Bool

    var activeWedgeCount: Int {
        mode == .convert ? convertWedgeCount : toolsWedgeCount
    }

    init(
        origin: Origin,
        optionHeld: Bool,
        convertWedgeCount: Int,
        toolsWedgeCount: Int,
        movedEnough: Bool = false
    ) {
        self.origin = origin
        self.mode = optionHeld ? .tools : .convert
        self.convertWedgeCount = convertWedgeCount
        self.toolsWedgeCount = toolsWedgeCount
        self.selection = nil
        self.movedEnough = movedEnough
        self.keyboardArmed = false
    }

    mutating func reduce(_ event: SessionEvent) -> SessionCommand {
        switch event {
        case .option(let held):
            mode = held ? .tools : .convert
            selection = nil
            keyboardArmed = false
            return .none
        case .pointer(let distance, let wedge):
            guard distance >= Self.movementThreshold else { return .none }
            movedEnough = true
            if let wedge, wedge >= 0, wedge < activeWedgeCount {
                selection = wedge
            } else if !keyboardArmed {
                selection = nil
            }
            return .none
        case .arrow(let step):
            let count = activeWedgeCount
            guard count > 0, step != 0 else { return .none }
            keyboardArmed = true
            let current = selection ?? (step > 0 ? -1 : 0)
            var next = (current + step) % count
            if next < 0 { next += count }
            selection = next
            return .none
        case .returnKey:
            guard let selection, activeWedgeCount > 0, selection < activeWedgeCount else { return .none }
            guard movedEnough || keyboardArmed else { return .none }
            return .run(wedgeIndex: selection, mode: mode)
        case .mouseUp(let inside, let wedge):
            guard inside else { return .dismissPassThrough }
            if movedEnough, let wedge, wedge >= 0, wedge < activeWedgeCount {
                return .run(wedgeIndex: wedge, mode: mode)
            }
            return .dismissConsume
        case .escape:
            return .dismissPassThrough
        case .shiftUp:
            return origin == .drag ? .dismissPassThrough : .none
        case .pasteboardCleared:
            return origin == .drag ? .dismissPassThrough : .none
        }
    }
}

enum SessionEvent: Equatable {
    case option(Bool)
    case pointer(distance: CGFloat, wedge: Int?)
    case mouseUp(insidePanel: Bool, wedge: Int?)
    case escape
    case returnKey
    case arrow(Int)
    case shiftUp
    case pasteboardCleared
}

enum SessionCommand: Equatable {
    case none
    case dismissPassThrough
    case dismissConsume
    case run(wedgeIndex: Int, mode: WheelMode)
}

enum WheelKeyAction: Equatable {
    case arrow(Int)
    case confirm
    case cancel

    static func from(keyCode: UInt16) -> WheelKeyAction? {
        switch keyCode {
        case 53:
            return .cancel
        case 36, 76:
            return .confirm
        case 123, 125:
            return .arrow(-1)
        case 124, 126:
            return .arrow(1)
        default:
            return nil
        }
    }
}
