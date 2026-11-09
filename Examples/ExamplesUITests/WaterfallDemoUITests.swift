import XCTest

@MainActor
final class WaterfallDemoUITests: XCTestCase {
    func testAutomaticSizingUpdatesAndBothAxes() {
        let app = XCUIApplication()
        app.launchArguments += ["-WaterfallDemo"]
        app.launch()
        let collection = app.collectionViews["waterfall-collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls["waterfall-tracks"].buttons["自适应"].isSelected)
        let first = collection.cells["waterfall-card-0"]
        let second = collection.cells["waterfall-card-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertNotEqual(first.frame.height, second.frame.height)
        capture("waterfall-vertical", app: app)
        let original = first.frame
        first.tap()
        XCTAssertTrue(wait { first.frame.height > original.height + 10 })
        app.buttons["waterfall-append"].tap()
        XCTAssertTrue(wait { app.staticTexts["waterfall-status"].label.contains("24 张卡片") })
        app.segmentedControls["waterfall-tracks"].buttons["3 轨道"].tap()
        XCTAssertTrue(wait { first.frame.width < original.width - 10 })

        app.segmentedControls["waterfall-axis"].buttons["横向"].tap()
        XCTAssertTrue(wait { abs(first.frame.height - 116) < 1 })
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        XCTAssertNotEqual(first.frame.width, second.frame.width)
        capture("waterfall-horizontal", app: app)

        app.segmentedControls["waterfall-axis"].buttons["正交横向"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let x = first.frame.minX
        first.swipeLeft()
        XCTAssertTrue(wait { !first.isHittable || abs(first.frame.minX - x) > 10 })
        capture("waterfall-orthogonal", app: app)
        app.segmentedControls["waterfall-tracks"].buttons["自适应"].tap()
        app.segmentedControls["waterfall-axis"].buttons["纵向"].tap()
        XCTAssertTrue(wait { abs(first.frame.width - original.width) < 1 })
        XCTAssertTrue(app.staticTexts["waterfall-status"].label.contains("轨道数随容器变化"))
        capture("waterfall-adaptive", app: app)
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
