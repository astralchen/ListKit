import XCTest

@MainActor
final class AdminTableSelectionUITests: XCTestCase {
    func testAdminTableSupportsIndependentMultipleSelection() {
        runSelectionScenario(holdingRefreshes: false)
    }

    func testAdminTableWaitsForDelayedApplyBeforeCheckingSelection() {
        runSelectionScenario(holdingRefreshes: true)
    }

    private struct ProbeState: Decodable {
        let editing: Bool
        let requestedGeneration: Int
        let completedGeneration: Int
        let heldGeneration: Int

        func isComplete(generation: Int) -> Bool {
            requestedGeneration == generation && completedGeneration == generation
        }
    }

    private func runSelectionScenario(holdingRefreshes: Bool) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AdminTableSelectionProbe"]
        if holdingRefreshes { app.launchArguments.append("-AdminTableHoldRefreshes") }
        app.launch()
        defer { app.terminate() }
        let tabBar = app.tabBars["design-scheme-tabs"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Admin Table"].tap()
        let table = app.tables["admin-table-demo-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let first = table.cells["admin-event-mod-1"]
        let second = table.cells["admin-event-mod-2"]
        let third = table.cells["admin-event-mod-3"]

        let rows = [first, second, third]
        var expectedGeneration = 1
        func readState() -> ProbeState? {
            guard let value = table.value as? String, let data = value.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ProbeState.self, from: data)
        }
        func selectionMatches(_ expected: [Bool]) -> Bool {
            zip(rows, expected).allSatisfy { $0.exists && $0.isSelected == $1 }
        }
        func isReady(_ expected: [Bool], editing: Bool, generation: Int) -> Bool {
            guard let state = readState() else { return false }
            return state.isComplete(generation: generation)
                && state.editing == editing && selectionMatches(expected)
        }
        func check(
            _ expected: [Bool], editing: Bool, _ stage: String,
            file: StaticString = #filePath, line: UInt = #line
        ) {
            let generation = expectedGeneration
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                isReady(expected, editing: editing, generation: generation)
            }, object: nil)
            let result = XCTWaiter.wait(for: [ready], timeout: 20)
            let actual = rows.map { $0.exists ? $0.isSelected : nil }
            let state = readState()
            let message = "\(stage): expected generation \(generation), editing \(editing), selection \(expected); got \(String(describing: state)), \(actual)"
            if result != .completed || actual != expected.map(Optional.some)
                || state?.editing != editing || state?.isComplete(generation: generation) != true {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Admin Table \(stage) failure"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Admin Table \(stage) hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertEqual(result, .completed, message, file: file, line: line)
            XCTAssertEqual(actual, expected.map(Optional.some), stage, file: file, line: line)
            XCTAssertEqual(state?.editing, editing, stage, file: file, line: line)
            XCTAssertEqual(state?.requestedGeneration, generation, stage, file: file, line: line)
            XCTAssertEqual(state?.completedGeneration, generation, stage, file: file, line: line)
            XCTAssertEqual(state?.heldGeneration, 0, stage, file: file, line: line)
        }
        func tap(
            _ row: XCUIElement, expecting expected: [Bool], editing: Bool, _ stage: String,
            file: StaticString = #filePath, line: UInt = #line
        ) {
            // 由操作序列决定目标代次，不能把尚未接收到请求的旧完成状态当作就绪。
            expectedGeneration += 1
            let generation = expectedGeneration
            row.tap()
            if holdingRefreshes {
                let pending = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    guard let state = readState() else { return false }
                    return state.requestedGeneration == generation
                        && state.completedGeneration == generation - 1
                        && state.heldGeneration == generation
                        && state.editing == editing && selectionMatches(expected)
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 10), .completed,
                               "\(stage): native selection must change before the held apply finishes", file: file, line: line)
                // 与正常等待共用就绪条件；删掉完成代次判断会在这里直接失败。
                XCTAssertFalse(isReady(expected, editing: editing, generation: generation),
                               "\(stage): pending apply must not be ready", file: file, line: line)
                app.buttons["admin-table-resume-render"].tap()
            }
            check(expected, editing: editing, stage, file: file, line: line)
        }
        check([true, false, true], editing: false, "initial controlled selection")
        tap(second, expecting: [true, true, true], editing: false, "select second without clearing others")
        tap(second, expecting: [true, false, true], editing: false, "deselect second")
        tap(first, expecting: [false, false, true], editing: false, "deselect first")
        tap(first, expecting: [true, false, true], editing: false, "reselect first before editing")
        app.buttons["admin-table-reorder"].tap()
        check([true, false, true], editing: true, "enter editing preserves both selections")
        tap(second, expecting: [true, true, true], editing: true, "select while editing")
        tap(first, expecting: [false, true, true], editing: true, "deselect while editing")
        let editingScreenshot = XCTAttachment(screenshot: app.screenshot())
        editingScreenshot.name = "Admin Table editing selection"
        editingScreenshot.lifetime = .keepAlways
        add(editingScreenshot)
        app.buttons["admin-table-reorder"].tap()
        check([false, true, true], editing: false, "exit editing preserves both selections")
        tap(first, expecting: [true, true, true], editing: false, "normal selection and refresh preserve both selections")
        tap(second, expecting: [true, false, true], editing: false, "normal deselection resumes after editing")
        let normalScreenshot = XCTAttachment(screenshot: app.screenshot())
        normalScreenshot.name = "Admin Table normal selection"
        normalScreenshot.lifetime = .keepAlways
        add(normalScreenshot)
    }
}
