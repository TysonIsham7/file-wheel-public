import XCTest

final class DragAndWheelTests: XCTestCase {
    func testDropOnWedgeRunsAndOutsideWritesNothing() {
        var session = DragSession(origin: .drag, optionHeld: false, convertWedgeCount: 5, toolsWedgeCount: 0)
        XCTAssertEqual(session.reduce(.pointer(distance: 3, wedge: 0)), .none)
        XCTAssertEqual(session.reduce(.mouseUp(insidePanel: true, wedge: 0)), .dismissConsume)

        session = DragSession(origin: .drag, optionHeld: false, convertWedgeCount: 5, toolsWedgeCount: 0)
        _ = session.reduce(.pointer(distance: 20, wedge: 0))
        XCTAssertEqual(session.reduce(.mouseUp(insidePanel: true, wedge: 0)), .run(wedgeIndex: 0, mode: .convert))

        session = DragSession(origin: .drag, optionHeld: false, convertWedgeCount: 5, toolsWedgeCount: 0)
        _ = session.reduce(.pointer(distance: 30, wedge: 1))
        XCTAssertEqual(session.reduce(.mouseUp(insidePanel: false, wedge: nil)), .dismissPassThrough)
    }

    func testOptionTogglesToolsWithoutEndingTheDrag() {
        var session = DragSession(origin: .drag, optionHeld: false, convertWedgeCount: 5, toolsWedgeCount: 0)
        XCTAssertEqual(session.reduce(.option(true)), .none)
        XCTAssertEqual(session.mode, .tools)
        XCTAssertEqual(session.reduce(.option(false)), .none)
        XCTAssertEqual(session.mode, .convert)
        _ = session.reduce(.pointer(distance: 12, wedge: 2))
        XCTAssertEqual(session.reduce(.mouseUp(insidePanel: true, wedge: 2)), .run(wedgeIndex: 2, mode: .convert))
    }

    func testSelectionKeyboardMatchesShiftDrag() {
        XCTAssertFalse(DragSession.Origin.drag.takesPanelKeyboard)
        XCTAssertTrue(DragSession.Origin.selection.takesPanelKeyboard)

        var session = DragSession(origin: .selection, optionHeld: false, convertWedgeCount: 4, toolsWedgeCount: 0, movedEnough: true)
        XCTAssertEqual(session.reduce(.returnKey), .none)
        XCTAssertEqual(session.reduce(.arrow(1)), .none)
        XCTAssertEqual(session.selection, 0)
        XCTAssertEqual(session.reduce(.arrow(1)), .none)
        XCTAssertEqual(session.selection, 1)
        XCTAssertEqual(session.reduce(.returnKey), .run(wedgeIndex: 1, mode: .convert))

        session = DragSession(origin: .selection, optionHeld: false, convertWedgeCount: 4, toolsWedgeCount: 0, movedEnough: true)
        XCTAssertEqual(session.reduce(.arrow(-1)), .none)
        XCTAssertEqual(session.selection, 3)
        XCTAssertEqual(session.reduce(.escape), .dismissPassThrough)
    }

    func testWheelKeyCodes() {
        XCTAssertEqual(WheelKeyAction.from(keyCode: 53), .cancel)
        XCTAssertEqual(WheelKeyAction.from(keyCode: 36), .confirm)
        XCTAssertEqual(WheelKeyAction.from(keyCode: 76), .confirm)
        XCTAssertEqual(WheelKeyAction.from(keyCode: 123), .arrow(-1))
        XCTAssertEqual(WheelKeyAction.from(keyCode: 125), .arrow(-1))
        XCTAssertEqual(WheelKeyAction.from(keyCode: 124), .arrow(1))
        XCTAssertEqual(WheelKeyAction.from(keyCode: 126), .arrow(1))
        XCTAssertNil(WheelKeyAction.from(keyCode: 0))
    }

    func testArrowReturnAndEscape() {
        var session = DragSession(origin: .drag, optionHeld: false, convertWedgeCount: 4, toolsWedgeCount: 0)
        XCTAssertEqual(session.reduce(.returnKey), .none)
        _ = session.reduce(.arrow(1))
        XCTAssertEqual(session.selection, 0)
        XCTAssertEqual(session.reduce(.returnKey), .run(wedgeIndex: 0, mode: .convert))

        session = DragSession(origin: .drag, optionHeld: false, convertWedgeCount: 4, toolsWedgeCount: 0)
        _ = session.reduce(.pointer(distance: 8, wedge: 3))
        XCTAssertEqual(session.reduce(.escape), .dismissPassThrough)
        XCTAssertEqual(session.reduce(.shiftUp), .dismissPassThrough)
    }

    func testWheelHitsTheWedgeUnderThePointer() {
        let center = CGPoint(x: 200, y: 200)
        let geometry = WheelGeometry(center: center, wedgeCount: 4)
        let mids: [CGFloat] = [.pi / 4, .pi / 4 + .pi / 2, .pi / 4 + .pi, .pi / 4 + (3 * .pi / 2)]
        for (index, angle) in mids.enumerated() {
            let point = WheelGeometry.point(center: center, radius: 80, clockwiseFromTop: angle)
            XCTAssertEqual(geometry.wedgeIndex(at: point), index)
        }
        XCTAssertNil(geometry.wedgeIndex(at: CGPoint(x: 200, y: 190)))
    }
}
