import XCTest

final class ExamplesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let originalOrientation = MainActor.assumeIsolated {
            XCUIDevice.shared.orientation
        }
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
        }
        addTeardownBlock {
            MainActor.assumeIsolated {
                XCUIDevice.shared.orientation = originalOrientation
            }
        }
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
    func testLiveConsoleLandscapeKeepsPrimaryContentInsideSafeHorizontalBounds() throws {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        let collection = app.collectionViews["live-console-collection"]
        let addMessage = app.buttons["live-console-add-message"]
        let sendGift = app.buttons["live-console-send-gift"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        XCTAssertTrue(addMessage.waitForExistence(timeout: 3))
        XCTAssertTrue(sendGift.waitForExistence(timeout: 3))

        // iPhone 17 的横屏安全区域在两侧均大于 47pt。这里同时防止内容压到
        // Dynamic Island 一侧，以及 Section 宽度从另一侧溢出屏幕。
        let safeHorizontalBounds = window.frame.insetBy(dx: 47, dy: 0)
        XCTAssertGreaterThanOrEqual(addMessage.frame.minX, safeHorizontalBounds.minX)
        XCTAssertLessThanOrEqual(sendGift.frame.maxX, safeHorizontalBounds.maxX)

        let roomTitle = app.staticTexts["Room Toolkit"]
        let micHint = app.staticTexts["Tap a seat to move speaking focus"]
        XCTAssertTrue(roomTitle.exists)
        XCTAssertTrue(micHint.exists)
        XCTAssertGreaterThanOrEqual(roomTitle.frame.minX, safeHorizontalBounds.minX)
        XCTAssertLessThanOrEqual(micHint.frame.maxX, safeHorizontalBounds.maxX)

        let roomTitleMinX = roomTitle.frame.minX
        let dragStart = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.42))
        let dragEnd = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.42))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertEqual(roomTitle.frame.minX, roomTitleMinX, accuracy: 1)
    }

    @MainActor
    func testAdminTableLandscapeKeepsHeaderAndRowsInsideSafeHorizontalBounds() throws {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Admin Table"].tap()

        let table = app.tables["admin-table-demo-table"]
        let summary = app.otherElements["admin-table-summary"]
        let sectionTitle = table.staticTexts
            .matching(NSPredicate(format: "label == %@", "Admin Events"))
            .element(boundBy: 0)
        let firstRowTitle = table.staticTexts["Moderator joined"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(sectionTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(firstRowTitle.waitForExistence(timeout: 3))

        let safeHorizontalBounds = window.frame.insetBy(dx: 47, dy: 0)
        for (name, element) in [
            ("summary", summary),
            ("section title", sectionTitle),
            ("first row title", firstRowTitle)
        ] {
            XCTAssertGreaterThanOrEqual(
                element.frame.minX,
                safeHorizontalBounds.minX,
                "\(name) crosses the leading safe-area boundary"
            )
            XCTAssertLessThanOrEqual(
                element.frame.maxX,
                safeHorizontalBounds.maxX,
                "\(name) crosses the trailing safe-area boundary"
            )
        }

        let summaryMinX = summary.frame.minX
        let dragStart = table.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.35))
        let dragEnd = table.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertEqual(summary.frame.minX, summaryMinX, accuracy: 1)
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

    /// 通过真实长按验证菜单首次展示、收起后重开以及点击预览提交。
    @MainActor
    func testCollectionContextMenuDismissAndPreviewCommit() throws {
        let app = XCUIApplication()
        app.launch()
        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Room Toolkit"].tap()
        let collection = app.collectionViews["room-toolkit-screen"]
        let item = collection.staticTexts["Native interactions"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        if !item.isHittable { collection.swipeUp() }
        item.press(forDuration: 0.7)
        let action = app.buttons["Activate"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        let displayed = XCTAttachment(screenshot: app.screenshot())
        displayed.name = "Collection context menu first presentation"
        displayed.lifetime = .keepAlways
        add(displayed)
        // 点按菜单外部，验证收起后原行仍能再次建立新的菜单会话。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.15)).tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 3))
        let dismissed = XCTAttachment(screenshot: app.screenshot())
        dismissed.name = "Collection context menu dismissed"
        dismissed.lifetime = .keepAlways
        add(dismissed)
        item.press(forDuration: 0.7)
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        // UIKit 将菜单预览包装为独立的可访问性容器。
        let preview = app.otherElements["Preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 3))
        let message = app.staticTexts["Activated Native interactions through a stable row context."]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        let committed = XCTAttachment(screenshot: app.screenshot())
        committed.name = "Collection context menu preview committed"
        committed.lifetime = .keepAlways
        add(committed)
    }

    /// 验证新 API 演示页的坐标、配置标识、动画完成及两种菜单结束路径。
    @MainActor
    func testContextMenuAPIDemoShowsLifecycleAndCommit() throws {
        let app = XCUIApplication()
        app.launch()
        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Room Toolkit"].tap()
        app.buttons["room-toolkit-header-menu"].tap()
        app.buttons["Context Menu APIs"].tap()
        let collection = app.collectionViews["context-menu-demo-collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 3))
        let log = app.textViews["context-menu-demo-log"]
        let original = collection.cells["context-menu-original"]
        original.press(forDuration: 0.7)
        let action = app.buttons["Record Action"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.17)).tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 3))
        func waitForLog(_ text: String) {
            let predicate = NSPredicate(format: "value CONTAINS %@", text)
            expectation(for: predicate, evaluatedWith: log)
            waitForExpectations(timeout: 5)
        }
        waitForLog("endCompleted · Original card #1")
        for event in ["configuration", "x:", "y:", "highlightPreview", "willDisplay", "displayCompleted", "dismissalPreview", "willEnd"] {
            XCTAssertTrue((log.value as? String)?.contains(event) == true, event)
        }
        let dismissed = XCTAttachment(screenshot: app.screenshot())
        dismissed.name = "Menu API demo dismissal lifecycle"
        dismissed.lifetime = .keepAlways
        add(dismissed)
        app.buttons["context-menu-clear-log"].tap()
        XCTAssertEqual(log.value as? String, "Long press a card to begin.")
        collection.cells["context-menu-preview"].press(forDuration: 0.7)
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        let preview = app.otherElements["Preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        let displayed = XCTAttachment(screenshot: app.screenshot())
        displayed.name = "Menu API demo configuration preview"
        displayed.lifetime = .keepAlways
        add(displayed)
        preview.tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 3))
        waitForLog("commitCompleted · Preview & Commit #2")
        XCTAssertTrue((log.value as? String)?.contains("commit · Preview & Commit #2 · row: Preview & Commit") == true)
        let committed = XCTAttachment(screenshot: app.screenshot())
        committed.name = "Menu API demo commit lifecycle"
        committed.lifetime = .keepAlways
        add(committed)
        original.press(forDuration: 0.7)
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        action.tap()
        waitForLog("actionSelected · Original card #3")
        waitForLog("endCompleted · Original card #3")
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
    func testLiveConsoleMicAndGiftEventsRefreshAndScrollToFinalMessage() throws {
        let app = XCUIApplication()
        app.launch()

        let collection = app.collectionViews["live-console-collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 5))

        let guestSeat = app.cells["mic-seat-guest-1"]
        XCTAssertTrue(guestSeat.waitForExistence(timeout: 3))
        XCTAssertTrue(guestSeat.staticTexts["Ready"].exists)
        guestSeat.tap()
        XCTAssertTrue(guestSeat.staticTexts["Live"].waitForExistence(timeout: 3))

        let rose = app.cells["gift-rose"]
        for _ in 0..<6 where !rose.isHittable {
            collection.swipeUp()
        }
        XCTAssertTrue(rose.isHittable)
        rose.tap()

        let sendRose = app.buttons["gift-send-rose"]
        XCTAssertTrue(sendRose.waitForExistence(timeout: 3))
        XCTAssertTrue(sendRose.isHittable)
        sendRose.tap()

        // sendGift(_:) performs selection, mutation, one render, and final-layout scroll in
        // one event. The appended message must therefore become visible without another swipe.
        XCTAssertTrue(app.staticTexts["Rose sent to Alex."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
