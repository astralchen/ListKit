#if NATIVE_PAGING_PROBE
import XCTest

@MainActor
final class StablePagingIdentityUITests: XCTestCase {
    func testLTRHorizontal() throws { try run(vertical: false, rtl: false) }
    func testRTLHorizontal() throws { try run(vertical: false, rtl: true) }
    func testLTRVertical() throws { try run(vertical: true, rtl: false) }
    func testRTLVertical() throws { try run(vertical: true, rtl: true) }

    private func run(vertical: Bool, rtl: Bool) throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        let name = "\(rtl ? "rtl" : "ltr")-\(vertical ? "vertical" : "horizontal")"
        app.launchArguments = ["-StablePagingProbe", "-StableRestorePage", "-StableIdentity", "-StableBadges", "-StableTailInset", "-StableLogicalLeft", "-StableMeasuredEstimate"]
        if vertical { app.launchArguments.append("-StableVertical") }
        if rtl { app.launchArguments.append("-StableRTL") }
        app.launch()
        let collection = app.collectionViews["stable-collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        var state = try snapshot(app, name: name + "-initial")
        validate(state, app: app, expectedPage: 0, name: name + "-initial")
        state = try move(app, state: state, forward: true, name: name + "-first")
        for (button, stage) in [("identity-insert", "insert"), ("identity-delete", "delete-anchor"),
                                ("identity-reorder", "reorder")] {
            state = try mutate(app, before: state, button: button, name: name + "-" + stage)
            state = try tapBadge(app, state: state, name: name + "-" + stage + "-tap")
            if stage == "insert" {
                // 22 items: visit the four-item tail using touches, then return to page 1.
                for page in [2, 3, 2, 1] {
                    state = try move(app, state: state, forward: page > (state["currentPage"] as? Int ?? 0),
                                     expectedPage: page, name: name + "-four-tail-\(page)-from-\(state["currentPage"] ?? "?")")
                }
            }
        }
        // Reordering moved the anchor identity into the partial last page.
        state = try move(app, state: state, forward: false, name: name + "-tail-back")
        state = try move(app, state: state, forward: true, name: name + "-tail-forward")
        for index in 0..<4 {
            state = try mutate(app, before: state, button: "identity-trim", name: name + "-trim-\(index)")
            state = try tapBadge(app, state: state, name: name + "-trim-\(index)-tap")
            let tailPage = ((state["ids"] as? [Int] ?? []).count - 1) / 6
            state = try move(app, state: state, forward: false, expectedPage: tailPage - 1,
                             name: name + "-trim-\(index)-back")
            state = try move(app, state: state, forward: true, expectedPage: tailPage,
                             name: name + "-trim-\(index)-forward")
        }
        for (button, stage) in [("stable-update", "content"), ("stable-resize", "resize")] {
            state = try mutate(app, before: state, button: button, name: name + "-" + stage)
            state = try tapBadge(app, state: state, name: name + "-" + stage + "-tap")
            state = try move(app, state: state, forward: false, expectedPage: 1, name: name + "-" + stage + "-back")
            state = try move(app, state: state, forward: true, expectedPage: 2, name: name + "-" + stage + "-forward")
        }
        state = try mutate(app, before: state, button: "identity-one", name: name + "-one")
        state = try tapBadge(app, state: state, name: name + "-one-tap")
        state = try mutate(app, before: state, button: "identity-clear", name: name + "-empty")
        XCTAssertEqual((state["ids"] as? [Int])?.count, 0)
        XCTAssertEqual((state["badgeViews"] as? [[String: Any]])?.count, 0)
        XCTAssertTrue(collection.cells.allElementsBoundByIndex.isEmpty)
        state = try mutate(app, before: state, button: "identity-insert", name: name + "-insert-into-empty")
        _ = try tapBadge(app, state: state, name: name + "-insert-into-empty-tap")
        let trace = XCTAttachment(string: app.staticTexts["stable-trace"].value as? String ?? "missing")
        trace.name = name + "-trace.json"
        trace.lifetime = .keepAlways
        add(trace)
        app.terminate()
    }
    private func mutate(_ app: XCUIApplication, before: [String: Any], button: String, name: String) throws -> [String: Any] {
        let old = try XCTUnwrap(before["ids"] as? [Int])
        let oldPage = before["currentPage"] as? Int ?? 0
        let oldIndex = min(oldPage * 6, max(0, old.count - 1))
        let anchor = old.isEmpty ? nil : old[oldIndex]
        app.buttons[button].tap()
        let after = try snapshot(app, name: name)
        let ids = try XCTUnwrap(after["ids"] as? [Int])
        var expected = anchor.flatMap { ids.contains($0) ? $0 : nil }
        var rule = "same"
        if expected == nil { expected = old.dropFirst(oldIndex + 1).first { ids.contains($0) }; rule = "successor" }
        if expected == nil { expected = old.prefix(oldIndex).reversed().first { ids.contains($0) }; rule = "predecessor" }
        if expected == nil { expected = ids.first; rule = expected == nil ? "empty" : "first" }
        let restore = try XCTUnwrap(after["restoration"] as? [String: Any])
        XCTAssertEqual(restore["anchorID"] as? Int, anchor, "\(name): preserve identity, not old index")
        XCTAssertEqual(restore["resolvedID"] as? Int, expected, "\(name): fallback identity")
        XCTAssertEqual(restore["fallback"] as? String, rule, "\(name): fallback policy")
        let page = expected.flatMap { ids.firstIndex(of: $0) }.map { $0 / 6 } ?? 0
        print("IDENTITY_UPDATE \(name) anchor=\(String(describing: anchor)) resolved=\(String(describing: expected)) rule=\(rule) page=\(page) count=\(ids.count)")
        validate(after, app: app, expectedPage: page, name: name)
        return after
    }
    private func move(_ app: XCUIApplication, state: [String: Any], forward: Bool, expectedPage: Int? = nil, name: String) throws -> [String: Any] {
        let vertical = state["vertical"] as? Bool ?? false
        let rtl = state["rtl"] as? Bool ?? false
        let current = state["currentPage"] as? Int ?? 0
        let target = expectedPage ?? (current + (forward ? 1 : -1))
        let bounds = app.collectionViews["stable-collection"].frame
        let distance = min((state["stride"] as? Double ?? 0) * 0.65, (vertical ? bounds.height : bounds.width) - 40)
        let positive = vertical ? !forward : rtl ? forward : !forward
        let axisStart = positive ? (vertical ? bounds.minY : bounds.minX) + 20
                                 : (vertical ? bounds.maxY : bounds.maxX) - 20
        let start = CGPoint(x: vertical ? bounds.midX : axisStart, y: vertical ? axisStart : bounds.midY)
        let delta = distance * (positive ? 1 : -1)
        let end = CGPoint(x: start.x + (vertical ? 0 : delta), y: start.y + (vertical ? delta : 0))
        let root = app.coordinate(withNormalizedOffset: .zero)
        root.withOffset(CGVector(dx: start.x, dy: start.y)).press(forDuration: 0.1,
            thenDragTo: root.withOffset(CGVector(dx: end.x, dy: end.y)), withVelocity: .slow, thenHoldForDuration: 0.2)
        let next = try snapshot(app, name: name)
        print("IDENTITY_GESTURE \(name) from=\(current) target=\(target) actual=\(next["currentPage"] ?? "missing")")
        validate(next, app: app, expectedPage: target, name: name)
        return next
    }
    private func validate(_ state: [String: Any], app: XCUIApplication, expectedPage: Int, name: String) {
        let ids = state["ids"] as? [Int] ?? []
        let vertical = state["vertical"] as? Bool ?? false
        let rtl = state["rtl"] as? Bool ?? false
        XCTAssertEqual(state["invalidBadgeRequests"] as? Int, 0, "\(name): no phantom badges")
        XCTAssertEqual(state["currentPage"] as? Int, expectedPage, "\(name): page identity")
        guard !ids.isEmpty else { return }
        let start = expectedPage * 6
        guard ids.indices.contains(start) else { XCTFail("\(name): invalid expected page"); return }
        let collection = app.collectionViews["stable-collection"]
        let item = collection.cells["stable-item-\(start)"]
        XCTAssertTrue(item.exists, "\(name): page first item exists")
        if item.exists {
            XCTAssertEqual(item.value as? String, "id:\(ids[start])")
            let error = vertical ? item.frame.minY - collection.frame.minY
                : rtl ? item.frame.maxX - collection.frame.maxX : item.frame.minX - collection.frame.minX
            print("IDENTITY_EDGE \(name) error=\(error) page=\(expectedPage)")
            XCTAssertEqual(error, 0, accuracy: 1, "\(name): logical page leading boundary")
        }
        let badgeViews = state["badgeViews"] as? [[String: Any]] ?? []
        XCTAssertEqual(Set(badgeViews.compactMap { $0["item"] as? Int }),
                       Set(state["visible"] as? [Int] ?? []), "\(name): every visible item has its badge")
        XCTAssertFalse(badgeViews.isEmpty, "\(name): actual supplementary badges must exist")
        for badge in badgeViews {
            guard let i = badge["item"] as? Int, ids.indices.contains(i),
                  let b = badge["badge"] as? [Double], let c = badge["cell"] as? [Double] else { continue }
            XCTAssertEqual(badge["id"] as? Int, ids[i], "\(name): badge identity after reuse")
            XCTAssertEqual(b[1], c[1], accuracy: 1, "\(name): badge top")
            XCTAssertEqual(rtl ? b[0] : b[0] + b[2], rtl ? c[0] : c[0] + c[2], accuracy: 1,
                           "\(name): logical trailing badge")
        }
        let measured = state["measured"] as? [Double] ?? []
        let frames = state["frames"] as? [[String: Any]] ?? []
        let visible = Set(state["visible"] as? [Int] ?? [])
        for f in frames {
            guard let i = f["item"] as? Int, visible.contains(i), measured.indices.contains(i),
                  let rect = f["frame"] as? [Double] else { continue }
            XCTAssertEqual(rect[vertical ? 3 : 2], measured[i], accuracy: 1, "\(name): natural item size")
        }
    }
    private func tapBadge(_ app: XCUIApplication, state: [String: Any], name: String) throws -> [String: Any] {
        let ids = state["ids"] as? [Int] ?? []
        let page = state["currentPage"] as? Int ?? 0
        guard ids.indices.contains(page * 6) else { return state }
        let resolved = (state["restoration"] as? [String: Any])?["resolvedID"] as? Int
        let id = resolved.flatMap { ids.contains($0) ? $0 : nil } ?? ids[page * 6]
        let badge = app.buttons["stable-badge-\(id)"]
        XCTAssertTrue(badge.isHittable, "\(name): badge must be touchable")
        if badge.isHittable { badge.tap() }
        let result = try snapshot(app, name: name)
        XCTAssertEqual(result["badgeTapID"] as? Int, id, "\(name): touch must target current identity")
        return result
    }
    private func snapshot(_ app: XCUIApplication, name: String) throws -> [String: Any] {
        app.buttons["stable-snapshot"].tap()
        let value = try XCTUnwrap(app.staticTexts["stable-state"].value as? String)
        let attachment = XCTAttachment(string: value)
        attachment.name = name + ".json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
}
#endif
