import XCTest

@MainActor
final class DragDropUITests: XCTestCase {
    func testDragTextOntoMatchingRow() {
        let app = XCUIApplication()
        app.launchArguments.append("-DragDropDemo")
        app.launch()
        let source = app.cells["source"]
        let inbox = app.cells["inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5))
        let toggle = app.buttons["toggle-inbox"]
        toggle.tap()
        source.press(forDuration: 2, thenDragTo: inbox, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(inbox.staticTexts["Drop text here"].exists)
        toggle.tap()
        source.press(forDuration: 2, thenDragTo: inbox, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(inbox.staticTexts["Hello from ListKit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Release to copy text"].exists)
        let image = app.cells["image"]
        image.press(forDuration: 2, thenDragTo: inbox, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(image.staticTexts["Page received image"].waitForExistence(timeout: 5), app.navigationBars.debugDescription)
        XCTAssertTrue(inbox.staticTexts["Hello from ListKit"].exists)
    }

    func testReorderAccessoryAlongsideDragAndDropRows() {
        let app = XCUIApplication()
        app.launchArguments.append("-DragDropDemo")
        app.launch()
        let first = app.cells.matching(NSPredicate(format: "identifier == %@", "First")).element
        let third = app.cells["Third"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        let grip = first.buttons["First"]
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        let handle = grip.frame
        XCTAssertTrue(first.frame.contains(CGPoint(x: handle.midX, y: handle.midY)))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: handle.midX, dy: handle.midY))
        let end = origin.withOffset(CGVector(dx: handle.midX, dy: third.frame.maxY - 5))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.navigationBars["Moved First"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(first.frame.midY, third.frame.midY)
        let inbox = app.cells["inbox"]
        let content = first.staticTexts["First"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = inbox.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        content.press(forDuration: 2, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(inbox.staticTexts["First"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(first.frame.midY, third.frame.midY)
    }
}
