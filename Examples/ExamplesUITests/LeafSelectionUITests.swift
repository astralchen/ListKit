import XCTest

@MainActor
final class LeafSelectionUITests: XCTestCase {
    func testSingleOneSection() throws { try run(mode: "single", companion: false) }
    func testAutomaticOneSection() throws { try run(mode: "automatic", companion: false) }
    func testMultipleOneSection() throws { try run(mode: "multiple", companion: false) }
    func testSingleTwoSections() throws { try run(mode: "single", companion: true) }
    func testAutomaticTwoSections() throws { try run(mode: "automatic", companion: true) }
    func testMultipleTwoSections() throws { try run(mode: "multiple", companion: true) }

    func testDynamicRowActionInsertionAndRemoval() { runDynamic(action: "dynamic-row") }
    func testDynamicDelegateAttachmentAndRelease() { runDynamic(action: "dynamic-delegate") }
    func testDynamicDelegatePolicyChanges() { runDynamic(action: "dynamic-policy") }

    private func runDynamic(action: String) {
        let app = launch(mode: "multiple", action: action)
        defer { app.terminate() }
        check(app, events: [], selected: [], name: action + "-initial")
        tap(app.cells["gesture-first"])
        var events = ["first-selected", "first-changed-true"]
        check(app, events: events, selected: ["first"], name: action + "-first")
        advance(app, phase: 1)
        if action == "dynamic-delegate" { XCTAssertEqual(read(app)["adapterHasDelegate"] as? Bool, true) }
        check(app, events: events, selected: ["first"], name: action + "-enabled")
        tap(app.cells["gesture-second"])
        events += ["first-deselected", "first-changed-false", "second-selected", "second-changed-true"]
        if action != "dynamic-delegate" { events.append("second-primary") }
        if action != "dynamic-row" { events.append("delegate-primary-second") }
        check(app, events: events, selected: ["second"], name: action + "-performed")
        advance(app, phase: 2)
        if action == "dynamic-delegate" { XCTAssertEqual(read(app)["adapterHasDelegate"] as? Bool, false) }
        check(app, events: events, selected: ["second"], name: action + "-disabled")
        tap(app.cells["gesture-first"])
        events += ["first-selected", "first-changed-true"]
        check(app, events: events, selected: ["first", "second"], name: action + "-multiselect-restored")
        tap(app.cells["gesture-second"])
        events += ["second-deselected", "second-changed-false"]
        check(app, events: events, selected: ["first"], name: action + "-deselect-restored")
    }

    private func advance(_ app: XCUIApplication, phase: Int) {
        let button = app.buttons["gesture-advance"]
        XCTAssertTrue(button.exists)
        XCTAssertTrue(button.isHittable)
        button.tap()
        // phase 已更新不代表 apply 已完成，必须同时等待 ready。
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let state = self.read(app)
            return state["phase"] as? Int == phase && state["ready"] as? Bool == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 10), .completed)
    }

    private func run(mode: String, companion: Bool) throws {
        let app = launch(mode: mode, companion: companion)
        defer { app.terminate() }
        let name = "\(mode)-\(companion ? 2 : 1)-sections"
        check(app, events: [], selected: [], name: name + "-initial")
        XCTAssertFalse(app.cells["gesture-hidden-child"].exists)
        tap(app.cells["gesture-first"])
        var events = ["first-selected", "first-changed-true"]
        check(app, events: events, selected: ["first"], name: name + "-first")
        tap(app.cells["gesture-second"])
        if mode != "multiple" { events += ["first-deselected", "first-changed-false"] }
        events += ["second-selected", "second-changed-true"]
        check(app, events: events, selected: mode == "multiple" ? ["first", "second"] : ["second"], name: name + "-second")
        if mode == "multiple" {
            tap(app.cells["gesture-second"])
            events += ["second-deselected", "second-changed-false"]
            check(app, events: events, selected: ["first"], name: name + "-deselect-second")
            tap(app.cells["gesture-first"])
            events += ["first-deselected", "first-changed-false"]
            check(app, events: events, selected: [], name: name + "-deselect-first")
        } else {
            tap(app.cells["gesture-first"])
            events += ["second-deselected", "second-changed-false", "first-selected", "first-changed-true"]
            check(app, events: events, selected: ["first"], name: name + "-switch-back")
        }
    }

    func testConfiguredActionDoesNotEnablePrimaryActionOnPlainLeaf() {
        let app = launch(mode: "multiple", action: "row")
        defer { app.terminate() }
        check(app, events: [], selected: [], name: "row-action-initial")
        tap(app.cells["gesture-first"])
        var events = ["first-selected", "first-changed-true"]
        check(app, events: events, selected: ["first"], name: "row-action-first")
        tap(app.cells["gesture-first"])
        events += ["first-deselected", "first-changed-false"]
        check(app, events: events, selected: [], name: "row-action-plain-toggle")
        tap(app.cells["gesture-first"])
        events += ["first-selected", "first-changed-true"]
        check(app, events: events, selected: ["first"], name: "row-action-reselect")
        tap(app.cells["gesture-second"])
        events += ["first-deselected", "first-changed-false", "second-selected", "second-changed-true", "second-primary"]
        check(app, events: events, selected: ["second"], name: "row-action-performed")
    }

    func testExternalPrimaryActionIsForwarded() {
        let app = launch(mode: "multiple", action: "delegate")
        defer { app.terminate() }
        check(app, events: [], selected: [], name: "delegate-initial")
        tap(app.cells["gesture-first"])
        var events = ["first-selected", "first-changed-true", "delegate-primary-first"]
        check(app, events: events, selected: ["first"], name: "delegate-first")
        tap(app.cells["gesture-second"])
        events += ["first-deselected", "first-changed-false", "second-selected", "second-changed-true", "delegate-primary-second"]
        check(app, events: events, selected: ["second"], name: "delegate-second")
    }

    func testExternalPolicyCanVetoConfiguredRowAction() {
        let app = launch(mode: "multiple", action: "delegate-policy")
        defer { app.terminate() }
        check(app, events: [], selected: [], name: "policy-initial")
        tap(app.cells["gesture-first"])
        var events = ["first-selected", "first-changed-true", "delegate-primary-first"]
        check(app, events: events, selected: ["first"], name: "policy-allowed")
        tap(app.cells["gesture-second"])
        events += ["second-selected", "second-changed-true"]
        check(app, events: events, selected: ["first", "second"], name: "policy-vetoed")
    }

    private func launch(mode: String, companion: Bool = false, action: String = "none") -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-LeafSelectionProbe"]
        app.launchEnvironment = ["LEAF_MODE": mode, "LEAF_COMPANION": companion ? "1" : "0", "LEAF_ACTION": action]
        app.launch()
        XCTAssertTrue(app.staticTexts["gesture-state"].waitForExistence(timeout: 15))
        return app
    }

    private func tap(_ cell: XCUIElement) {
        XCTAssertTrue(cell.exists)
        XCTAssertTrue(cell.isHittable)
        // Touch the label area rather than the accessory. This synthesizes an actual touch sequence.
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
    }
    private func read(_ app: XCUIApplication) -> [String: Any] {
        let value = app.staticTexts["gesture-state"].value as? String ?? "{}"
        return (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any] ?? [:]
    }
    private func check(_ app: XCUIApplication, events: [String], selected: [String], name: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let state = self.read(app)
            return state["ready"] as? Bool == true
                && state["events"] as? [String] == events
                && state["selected"] as? [String] == selected.sorted()
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        let state = read(app)
        let json = String(data: try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]), encoding: .utf8)!
        let trace = XCTAttachment(string: json)
        trace.name = name + ".json"
        trace.lifetime = .keepAlways
        add(trace)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("LEAF_GESTURE_CHECK \(name) \(json)")
        XCTAssertEqual(result, .completed, name + " " + json)
        for id in ["first", "second"] {
            XCTAssertEqual(app.cells["gesture-\(id)"].isSelected, selected.contains(id), name + " " + id)
        }
    }
}
