import XCTest

@MainActor
final class LayoutLabUITests: XCTestCase {
  func testCustomBoundaryKindsFollowAxis() {
    let app = launchLayoutLab()
    let title = app.descendants(matching: .any)["lab-title"]
    let summary = app.descendants(matching: .any)["lab-summary"]
    XCTAssertTrue(title.waitForExistence(timeout: 10))
    app.buttons["Count"].tap()
    XCTAssertTrue(summary.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "lab.title · 1")
    XCTAssertEqual(summary.label, "lab.summary")
    XCTAssertLessThan(title.frame.maxY, summary.frame.minY)
    capture("custom-kinds-vertical", app: app)
    app.buttons["Axis"].tap()
    let moved = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        title.frame.maxX < summary.frame.minX
      }, object: title)
    XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
    XCTAssertEqual(title.frame.width, 100, accuracy: 1)
    XCTAssertEqual(summary.frame.width, 100, accuracy: 1)
    capture("custom-kinds-horizontal", app: app)
  }

  func testGridModesWidthAndEmptyContent() {
    let app = launchLayoutLab()
    let collection = app.collectionViews["layout-lab-collection"]
    XCTAssertTrue(collection.waitForExistence(timeout: 10))
    let first = collection.cells["layout-item-0"]
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    capture("adaptive-wide", app: app)

    selectSizing("宽高比 1", in: app)
    app.segmentedControls["layout-modes"].buttons["3 columns"].tap()
    let wideWidth = first.frame.width
    XCTAssertEqual(first.frame.height, wideWidth, accuracy: 1)
    app.buttons["Width"].tap()
    XCTAssertTrue(waitForWidth(first, lessThan: wideWidth - 5))
    XCTAssertEqual(first.frame.height, first.frame.width, accuracy: 1)
    capture("fixed-narrow", app: app)

    app.segmentedControls["layout-modes"].buttons["Mixed"].tap()
    XCTAssertEqual(first.frame.width, 60, accuracy: 1)
    capture("mixed-narrow", app: app)
    app.buttons["Count"].tap()
    XCTAssertTrue(first.exists)
    XCTAssertFalse(collection.cells["layout-item-1"].exists)
    capture("one-item", app: app)
    app.buttons["Count"].tap()
    XCTAssertTrue(NSPredicate(format: "exists == false").evaluate(with: first))
    capture("empty-section", app: app)
    app.buttons["Count"].tap()
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    app.segmentedControls["layout-modes"].buttons["List"].tap()
    selectSizing("固定 56", in: app)
    XCTAssertEqual(first.frame.height, 56, accuracy: 1)
    capture("list", app: app)
  }

    func testOrthogonalScenesScrollInBothOuterDirections() {
        for horizontal in [false, true] {
            for scene in ["Cards", "Tags", "Banner", "Centered", "2×3"] {
                let app = launchLayoutLab()
                if horizontal { app.buttons["Axis"].tap() }
                selectScene(scene, in: app)
                let collection = app.collectionViews["layout-lab-collection"]
                let first = collection.cells["layout-item-0"]
                XCTAssertTrue(first.waitForExistence(timeout: 5))
                let original = first.frame
                if scene == "2×3" {
                    let second = collection.cells["layout-item-1"]
                    XCTAssertEqual(
                        horizontal ? original.minY : original.minX,
                        horizontal ? second.frame.minY : second.frame.minX, accuracy: 1)
                }
                capture("\(scene)-\(horizontal ? "horizontal" : "vertical")-before", app: app)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                // Start inside the orthogonal content, not its boundary header or outer collection.
                let center = CGVector(
                    dx: horizontal ? original.midX : collection.frame.maxX - 40,
                    dy: horizontal ? collection.frame.maxY - 80 : original.midY)
                let start = origin.withOffset(center)
                let end = origin.withOffset(
                    CGVector(
                        dx: horizontal ? center.dx : collection.frame.minX + 40,
                        dy: horizontal ? collection.frame.minY + 80 : center.dy))
                start.press(forDuration: 0.05, thenDragTo: end)
                let moved = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in
                        !first.exists
                            || abs(
                                (horizontal ? first.frame.minY : first.frame.minX)
                                    - (horizontal ? original.minY : original.minX)) > 10
                    }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, scene)
                capture("\(scene)-\(horizontal ? "horizontal" : "vertical")-after", app: app)
                app.terminate()
            }
        }
    }

    func testTwoByThreePageStopsAndTailPreservesSize() {
        let app = launchLayoutLab()
        selectScene("2×3", in: app)
        let collection = app.collectionViews["layout-lab-collection"]
        let first = collection.cells["layout-item-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let origin = first.frame
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: collection.frame.maxX - 30, dy: origin.midY))
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: collection.frame.minX + 30, dy: origin.midY))
        start.press(forDuration: 0.05, thenDragTo: end)
        let next = collection.cells["layout-item-6"]
        let stopped = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                next.exists && abs(next.frame.minX - origin.minX) < 2
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed)
        XCTAssertEqual(next.frame.width, origin.width, accuracy: 1)
        capture("two-by-three-page-stop", app: app)
        start.press(forDuration: 0.05, thenDragTo: end)
        let tail = collection.cells["layout-item-16"]
        XCTAssertTrue(tail.waitForExistence(timeout: 5))
        XCTAssertEqual(tail.frame.width, origin.width, accuracy: 1)
        capture("two-by-three-tail", app: app)
    }

    func testLeadingAndCenteredGroupsStopAtTheirDeclaredAnchor() {
        for scene in ["Cards", "Centered"] {
            let app = launchLayoutLab()
            selectScene(scene, in: app)
            let collection = app.collectionViews["layout-lab-collection"]
            let first = collection.cells["layout-item-0"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            let original = first.frame
            let root = app.coordinate(withNormalizedOffset: .zero)
            root.withOffset(CGVector(dx: collection.frame.maxX - 35, dy: original.midY))
                .press(
                    forDuration: 0.05,
                    thenDragTo: root.withOffset(
                        CGVector(dx: collection.frame.minX + 35, dy: original.midY)))
            let countPerGroup = Int(floor((collection.frame.width - 24 + 10) / (92 + 10)))
            let stopped = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    (1..<17).contains { index in
                        if scene == "Cards" && index % countPerGroup != 0 { return false }
                        let item = collection.cells["layout-item-\(index)"]
                        guard item.exists else { return false }
                        if scene == "Centered" { return abs(item.frame.midX - collection.frame.midX) < 2 }
                        return abs(item.frame.minX - original.minX) < 2
                    }
                }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed, scene)
            capture("\(scene)-declared-anchor", app: app)
            app.terminate()
        }
    }

    func testParametersUpdateLiveCodeAndGeometry() {
        let app = launchLayoutLab()
        app.segmentedControls["layout-modes"].buttons["Fixed"].tap()
        app.buttons["参数 / 代码"].tap()
        app.buttons["lab-sizing"].tap()
        app.buttons["宽高比 1"].tap()
        app.steppers["lab-track-spacing"].buttons["Increment"].tap()
        app.steppers["lab-line-spacing"].buttons["Increment"].tap()
        app.switches["lab-group-spacing-override"].tap()
        app.steppers["lab-group-spacing"].buttons["Increment"].tap()
        app.steppers["lab-lines"].buttons["Increment"].tap()
        app.segmentedControls["lab-parameter-tabs"].buttons["代码"].tap()
        let code = app.textViews["lab-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        let source = code.value as? String ?? ""
        for fragment in [".aspectRatio(1)", ".trackSpacing(12)", ".lineSpacing(12)",
                         ".groupSpacing(14)", ".count(lines: 2)"] {
            XCTAssertTrue(source.contains(fragment), fragment)
        }
        capture("live-parameters-code", app: app)
        app.buttons["完成"].tap()
        let collection = app.collectionViews["layout-lab-collection"]
        let first = collection.cells["layout-item-0"]
        let second = collection.cells["layout-item-1"]
        XCTAssertEqual(first.frame.width, 60, accuracy: 1)
        XCTAssertEqual(first.frame.height, 60, accuracy: 1)
        XCTAssertEqual(second.frame.minX - first.frame.maxX, 12, accuracy: 1)
        let nextLine = collection.cells["layout-item-3"]
        let nextGroup = collection.cells["layout-item-6"]
        XCTAssertEqual(nextLine.frame.minY - first.frame.maxY, 12, accuracy: 1)
        XCTAssertEqual(nextGroup.frame.minY - nextLine.frame.maxY, 14, accuracy: 1)
        capture("configured-vertical", app: app)
        app.buttons["参数 / 代码"].tap()
        app.switches["lab-group-spacing-override"].tap()
        XCTAssertFalse(app.steppers["lab-group-spacing"].exists)
        app.segmentedControls["lab-parameter-tabs"].buttons["代码"].tap()
        let resetSource = app.textViews["lab-code"].value as? String ?? ""
        XCTAssertTrue(resetSource.contains(".lineSpacing(12)"))
        XCTAssertFalse(resetSource.contains(".groupSpacing("))
        capture("inherited-spacing-code", app: app)
        app.buttons["完成"].tap()
        XCTAssertEqual(nextGroup.frame.minY - nextLine.frame.maxY, 12, accuracy: 1)
        app.buttons["Axis"].tap()
        XCTAssertTrue(app.segmentedControls["layout-modes"].buttons["Fixed"].isSelected)
        app.buttons["Width"].tap()
        XCTAssertEqual(collection.frame.height, 240, accuracy: 1)
        XCTAssertLessThan(collection.frame.minY - app.segmentedControls["layout-modes"].frame.maxY, 100)
        XCTAssertEqual(first.frame.width, 60, accuracy: 1)
        capture("configured-horizontal", app: app)
    }

    func testEstimatedContentRefreshAndSceneCode() {
        let app = launchLayoutLab()
        app.segmentedControls["layout-modes"].buttons["List"].tap()
        let first = app.collectionViews["layout-lab-collection"].cells["layout-item-0"]
        let before = first.frame.height
        app.buttons["参数 / 代码"].tap()
        app.buttons["lab-sizing"].tap()
        app.buttons["自适应"].tap()
        let expanded = app.switches["lab-expanded"]
        if !expanded.isHittable { app.tables["lab-parameters"].swipeUp() }
        expanded.tap()
        XCTAssertEqual(expanded.value as? String, "1")
        app.segmentedControls["lab-parameter-tabs"].buttons["代码"].tap()
        XCTAssertTrue((app.textViews["lab-code"].value as? String ?? "").contains(".estimated(44)"))
        XCTAssertTrue((app.textViews["lab-code"].value as? String ?? "").contains("内容已增加"))
        app.buttons["完成"].tap()
        XCTAssertGreaterThan(first.frame.height, before)
        capture("estimated-expanded", app: app)
        if #available(iOS 17.0, *) {
            app.segmentedControls["layout-modes"].buttons["3 columns"].tap()
            selectSizing("同组统一", in: app)
            let cells = app.collectionViews["layout-lab-collection"].cells
            XCTAssertEqual(cells["layout-item-0"].frame.height, cells["layout-item-1"].frame.height, accuracy: 1)
            XCTAssertEqual(cells["layout-item-0"].frame.height, cells["layout-item-2"].frame.height, accuracy: 1)
            capture("uniform-expanded", app: app)
        }
        selectScene("2×3", in: app)
        app.buttons["Axis"].tap()
        app.buttons["参数 / 代码"].tap()
        app.segmentedControls["lab-parameter-tabs"].buttons["代码"].tap()
        let code = app.textViews["lab-code"].value as? String ?? ""
        XCTAssertTrue(code.contains("scrollDirection: .horizontal"))
        XCTAssertTrue(code.contains(".count(lines: 3, mainAxisSize: .fractionalViewport(1))"))
        XCTAssertTrue(code.contains(".orthogonalScrolling(.groupPaging)"))
        capture("paging-horizontal-code", app: app)
    }

    func testMeasuredBadgesFollowItemsWhileScrollingInBothDirections() {
        for horizontal in [false, true] {
            let app = launchLayoutLab()
            if horizontal { app.buttons["Axis"].tap() }
            if horizontal { app.buttons["Width"].tap() }
            selectScene("Measured badges", in: app)
            let collection = app.collectionViews["layout-lab-collection"]
            let first = collection.cells["layout-item-0"]
            let third = collection.cells["layout-item-4"]
            let otherThird = collection.cells["layout-item-5"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            let badge = app.buttons["layout-badge-2"]
            XCTAssertTrue(badge.waitForExistence(timeout: 5))
            let item = collection.cells["layout-item-2"]
            XCTAssertEqual(badge.frame.maxX, item.frame.maxX, accuracy: 1)
            XCTAssertEqual(badge.frame.minY, item.frame.minY, accuracy: 1)
            badge.tap()
            XCTAssertEqual(app.descendants(matching: .any)["lab-explanation"].label, "点击徽标：item 2")
            let origin = first.frame
            let extent = horizontal ? max(third.frame.maxY, otherThird.frame.maxY) - origin.minY
                : max(third.frame.maxX, otherThird.frame.maxX) - origin.minX
            let root = app.coordinate(withNormalizedOffset: .zero)
            let start = root.withOffset(CGVector(dx: horizontal ? origin.midX : origin.minX + extent * 0.85,
                                                dy: horizontal ? origin.minY + extent * 0.85 : origin.midY))
            let end = root.withOffset(CGVector(dx: horizontal ? origin.midX : origin.minX + extent * 0.15,
                                              dy: horizontal ? origin.minY + extent * 0.15 : origin.midY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            let next = collection.cells["layout-item-6"]
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                next.exists && abs((horizontal ? next.frame.minY : next.frame.minX)
                    - (horizontal ? origin.minY + extent + 20 : origin.minX + extent + 20)) > 30
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
            let nextBadge = app.buttons["layout-badge-6"]
            XCTAssertTrue(nextBadge.exists)
            XCTAssertEqual(nextBadge.frame.maxX, next.frame.maxX, accuracy: 1)
            XCTAssertEqual(nextBadge.frame.minY, next.frame.minY, accuracy: 1)
            nextBadge.tap()
            XCTAssertEqual(app.descendants(matching: .any)["lab-explanation"].label, "点击徽标：item 6")
            capture("measured-badges-\(horizontal ? "horizontal" : "vertical")", app: app)
            app.terminate()
        }
    }

    /// 启动配置测试可能留下横屏状态；每次启动都恢复本组几何断言所需的竖屏窗口。
    private func launchLayoutLab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LayoutLab"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let window = app.windows.firstMatch
        let portrait = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                window.exists && window.frame.height > window.frame.width
            },
            object: window
        )
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed,
                       "Layout Lab geometry tests require a portrait window")
        return app
    }

    private func selectScene(_ title: String, in app: XCUIApplication) {
        app.buttons["Scenes"].tap()
        // UIKit combines a menu action's title and subtitle in its accessibility label.
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ", ")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), title)
        choice.tap()
    }

    private func selectSizing(_ title: String, in app: XCUIApplication) {
        app.buttons["参数 / 代码"].tap()
        app.buttons["lab-sizing"].tap()
        app.buttons[title].tap()
        app.buttons["完成"].tap()
    }

    private func waitForWidth(_ item: XCUIElement, lessThan width: CGFloat) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in item.frame.width < width }, object: item)
    return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
  }
  private func capture(_ name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
