import XCTest

final class ExamplesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEachTabPresentsADifferentDesignScheme() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let liveConsoleTab = tabBar.buttons["Live Console"]
        let studioControlTab = tabBar.buttons["Studio Control"]
        let roomToolkitTab = tabBar.buttons["Room Toolkit"]
        let adminTableTab = tabBar.buttons["Admin Table"]
        XCTAssertTrue(liveConsoleTab.exists)
        XCTAssertTrue(studioControlTab.exists)
        XCTAssertTrue(roomToolkitTab.exists)
        XCTAssertTrue(adminTableTab.exists)

        liveConsoleTab.tap()
        XCTAssertTrue(app.otherElements["live-console-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.collectionViews["live-console-collection"].exists)
        XCTAssertTrue(app.buttons["live-console-add-message"].exists)

        studioControlTab.tap()
        XCTAssertTrue(app.otherElements["studio-control-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.collectionViews["studio-control-collection"].exists)
        XCTAssertTrue(app.segmentedControls["studio-control-segment"].exists)

        roomToolkitTab.tap()
        XCTAssertTrue(app.collectionViews["room-toolkit-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["room-toolkit-hero"].exists)
        XCTAssertTrue(app.staticTexts["SwiftUI-style API guide"].exists)

        adminTableTab.tap()
        XCTAssertTrue(app.otherElements["admin-table-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tables["admin-table-demo-table"].exists)
        XCTAssertTrue(app.tables["admin-table-demo-table"].isHittable)
        XCTAssertTrue(app.buttons["admin-table-reorder"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
