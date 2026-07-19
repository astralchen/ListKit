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
        XCTAssertTrue(app.collectionViews["live-console-collection"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["live-console-add-message"].exists)

        studioControlTab.tap()
        XCTAssertTrue(app.collectionViews["studio-control-collection"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls["studio-control-segment"].exists)

        roomToolkitTab.tap()
        XCTAssertTrue(app.collectionViews["room-toolkit-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["room-metric-strip"].exists)
        XCTAssertTrue(app.staticTexts["SwiftUI-style API guide"].exists)

        adminTableTab.tap()
        let adminTable = app.tables["admin-table-demo-table"]
        XCTAssertTrue(adminTable.waitForExistence(timeout: 3))
        XCTAssertTrue(adminTable.isHittable)
        XCTAssertEqual(
            adminTable.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "M")).count,
            0
        )
        XCTAssertTrue(app.buttons["admin-table-reorder"].exists)
    }

    @MainActor
    func testSelectingAPIGuideRowDoesNotScroll() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Room Toolkit"].tap()

        let metricStrip = app.otherElements["room-metric-strip"]
        let capability = app.staticTexts["Stable row context"]
        XCTAssertTrue(metricStrip.waitForExistence(timeout: 3))
        XCTAssertTrue(capability.waitForExistence(timeout: 3))
        let metricStripMinY = metricStrip.frame.minY

        capability.tap()

        XCTAssertEqual(metricStrip.frame.minY, metricStripMinY, accuracy: 1)
        XCTAssertTrue(capability.isHittable)
    }

    @MainActor
    func testAPIGuideRowHidesAndRestoresAllChildren() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Room Toolkit"].tap()

        let guide = app.staticTexts["SwiftUI-style API guide"]
        let capabilityTitles = [
            "Async snapshot apply",
            "Stable row context",
            "Native interactions"
        ]
        XCTAssertTrue(guide.waitForExistence(timeout: 3))
        for title in capabilityTitles {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
        }

        guide.tap()

        for title in capabilityTitles {
            XCTAssertFalse(app.staticTexts[title].waitForExistence(timeout: 1))
        }

        guide.tap()

        for title in capabilityTitles {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testRoomToolkitHeaderMenuAddsSystemEvent() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Room Toolkit"].tap()

        let menu = app.buttons["room-toolkit-header-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()

        let addSystemEvent = app.buttons["Add System Event"]
        XCTAssertTrue(addSystemEvent.waitForExistence(timeout: 2))
        addSystemEvent.tap()

        XCTAssertTrue(
            app.staticTexts["System health check completed."].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testRoomActivityFilterMenuFiltersAndRestoresMessages() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Room Toolkit"].tap()

        let collection = app.collectionViews["room-toolkit-screen"]
        let filter = app.buttons["room-toolkit-activity-filter"]
        XCTAssertTrue(collection.waitForExistence(timeout: 3))
        for _ in 0..<4 where !filter.isHittable {
            collection.swipeUp()
        }
        XCTAssertTrue(filter.isHittable)
        let filterMinY = filter.frame.minY

        filter.tap()
        let messages = app.buttons["Messages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 2))
        messages.tap()

        XCTAssertTrue(app.staticTexts["Loving the new ListKit live demo!"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Sent a Rocket"].exists)
        XCTAssertEqual(filter.value as? String, "Messages")
        XCTAssertEqual(filter.frame.minY, filterMinY, accuracy: 1)

        filter.tap()
        let gifts = app.buttons["Gifts"]
        XCTAssertTrue(gifts.waitForExistence(timeout: 2))
        gifts.tap()

        XCTAssertTrue(app.staticTexts["Sent a Rocket"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Loving the new ListKit live demo!"].exists)
        XCTAssertEqual(filter.value as? String, "Gifts")
        XCTAssertEqual(filter.frame.minY, filterMinY, accuracy: 1)

        filter.tap()
        let system = app.buttons["System"]
        XCTAssertTrue(system.waitForExistence(timeout: 2))
        system.tap()

        XCTAssertFalse(app.staticTexts["Sent a Rocket"].exists)
        XCTAssertFalse(app.staticTexts["Loving the new ListKit live demo!"].exists)
        XCTAssertEqual(filter.value as? String, "System")
        XCTAssertEqual(filter.frame.minY, filterMinY, accuracy: 1)

        filter.tap()
        let allActivity = app.buttons["All Activity"]
        XCTAssertTrue(allActivity.waitForExistence(timeout: 2))
        allActivity.tap()

        XCTAssertTrue(app.staticTexts["Loving the new ListKit live demo!"].waitForExistence(timeout: 3))
        XCTAssertEqual(filter.value as? String, "All Activity")
        XCTAssertEqual(filter.frame.minY, filterMinY, accuracy: 1)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
