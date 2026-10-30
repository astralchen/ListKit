#if NATIVE_PAGING_PROBE
import XCTest

@MainActor
final class StablePagingProbeUITests: XCTestCase {
    func testMeasuredLineSlots() throws { try run(envelope: false) }
    func testMeasuredPageEnvelopeOnly() throws { try run(envelope: true) }

    func testMeasuredLineSlotsWithPublicAnchor() throws { try run(envelope: false, restore: true) }

    private func run(envelope: Bool, restore: Bool = false) throws {
        continueAfterFailure = true
        for vertical in [false, true] {
            let app = XCUIApplication()
            let name = "\(restore ? "restored-slots" : envelope ? "envelope" : "slots")-\(vertical ? "vertical" : "horizontal")"
            app.launchArguments = ["-StablePagingProbe"]
            if vertical { app.launchArguments.append("-StableVertical") }
            if envelope { app.launchArguments.append("-StableEnvelopeOnly") }
            if restore { app.launchArguments.append("-StableRestorePage") }
            app.launch()
            let collection = app.collectionViews["stable-collection"]
            guard collection.waitForExistence(timeout: 10) else { XCTFail("fixture missing"); continue }
            var state = try snapshot(app, name: name + "-initial")
            validateGeometry(state, name: name + "-initial")
            capture(app, name: name + "-initial")
            state = try move(app, collection: collection, state: state, forward: true, name: name + "-first")
            let originalPage = (number(state, "offset", vertical ? 1 : 0) / number(state, "stride")).rounded()
            app.buttons["stable-update"].tap()
            state = try snapshot(app, name: name + "-updated")
            validateGeometry(state, name: name + "-updated")
            XCTAssertEqual(state["revision"] as? Int, 1)
            let updateError = number(state, "offset", vertical ? 1 : 0) - originalPage * number(state, "stride")
            print("STABLE_UPDATE \(name) content anchorError=\(updateError)")
            XCTAssertEqual(updateError, 0, accuracy: 1, "\(name): content update must retain aligned page under the selected transaction policy")
            capture(app, name: name + "-updated")
            state = try move(app, collection: collection, state: state, forward: true, name: name + "-after-update")
            let beforeResize = state
            let pageBeforeResize = (number(state, "offset", vertical ? 1 : 0) / number(state, "stride")).rounded()
            app.buttons["stable-resize"].tap()
            state = try snapshot(app, name: name + "-resized")
            validateGeometry(state, name: name + "-resized")
            XCTAssertEqual(number(state, "track"), 80, accuracy: 0.01)
            XCTAssertEqual(number(state, "viewport"), 300, accuracy: 0.01)
            XCTAssertNotEqual(number(beforeResize, "pageExtent"), number(state, "pageExtent"))
            let resizeError = number(state, "offset", vertical ? 1 : 0) - pageBeforeResize * number(state, "stride")
            print("STABLE_UPDATE \(name) container anchorError=\(resizeError)")
            XCTAssertEqual(resizeError, 0, accuracy: 1, "\(name): resize must retain aligned page under the selected transaction policy")
            capture(app, name: name + "-resized")
            state = try move(app, collection: collection, state: state, forward: true, name: name + "-after-resize")
            state = try move(app, collection: collection, state: state, forward: false, name: name + "-reverse")
            if restore {
                for (button, stage) in [("stable-update", "shrink"), ("stable-resize", "wide")] {
                    let page = (number(state, "offset", vertical ? 1 : 0) / number(state, "stride")).rounded()
                    let oldStride = number(state, "stride")
                    app.buttons[button].tap()
                    state = try snapshot(app, name: name + "-" + stage)
                    validateGeometry(state, name: name + "-" + stage)
                    XCTAssertNotEqual(oldStride, number(state, "stride"))
                    let error = number(state, "offset", vertical ? 1 : 0) - page * number(state, "stride")
                    print("STABLE_UPDATE \(name) \(stage) anchorError=\(error)")
                    XCTAssertEqual(error, 0, accuracy: 1, "\(name): shrinking/restored dimensions retain page")
                    capture(app, name: name + "-" + stage)
                    state = try move(app, collection: collection, state: state, forward: true,
                                     name: name + "-after-" + stage)
                }
                XCTAssertEqual(state["revision"] as? Int, 0)
                XCTAssertEqual(state["narrow"] as? Bool, false)
            }
            let trace = XCTAttachment(string: app.staticTexts["stable-trace"].value as? String ?? "missing")
            trace.name = name + "-trace.json"
            trace.lifetime = .keepAlways
            add(trace)
            app.terminate()
        }
    }
    private func move(_ app: XCUIApplication, collection: XCUIElement, state: [String: Any],
                      forward: Bool, name: String) throws -> [String: Any] {
        let vertical = state["vertical"] as? Bool ?? false
        let stride = number(state, "stride")
        let current = (number(state, "offset", vertical ? 1 : 0) / stride).rounded()
        let target = Int(current) + (forward ? 1 : -1)
        let bounds = collection.frame
        let available = vertical ? bounds.height : bounds.width
        let distance = min(stride * 0.65, available - 40)
        let axisStart = forward ? (vertical ? bounds.maxY : bounds.maxX) - 20
                                : (vertical ? bounds.minY : bounds.minX) + 20
        let start = CGPoint(x: vertical ? bounds.midX : axisStart, y: vertical ? axisStart : bounds.midY)
        let delta = distance * (forward ? -1 : 1)
        let end = CGPoint(x: start.x + (vertical ? 0 : delta), y: start.y + (vertical ? delta : 0))
        let root = app.coordinate(withNormalizedOffset: .zero)
        root.withOffset(CGVector(dx: start.x, dy: start.y)).press(forDuration: 0.1,
            thenDragTo: root.withOffset(CGVector(dx: end.x, dy: end.y)), withVelocity: .slow,
            thenHoldForDuration: 0.2)
        let next = try snapshot(app, name: name)
        capture(app, name: name)
        validateGeometry(next, name: name)
        let actualOffset = number(next, "offset", vertical ? 1 : 0)
        let error = actualOffset - CGFloat(target) * stride
        let item = collection.cells["stable-item-\(target * 6)"]
        let screenError = item.exists ? (vertical ? item.frame.minY - bounds.minY : item.frame.minX - bounds.minX) : CGFloat.infinity
        print("STABLE_RESULT \(name) target=\(target) offsetError=\(error) screenError=\(screenError) stride=\(stride)")
        XCTAssertEqual(error, 0, accuracy: 1, "\(name): native groupPaging offset")
        XCTAssertEqual(screenError, 0, accuracy: 1, "\(name): page must start at its intended item")
        return next
    }
    private func validateGeometry(_ state: [String: Any], name: String) {
        let vertical = state["vertical"] as? Bool ?? false
        let axis = vertical ? 1 : 0
        let frames = state["frames"] as? [[String: Any]] ?? []
        let measured = state["measured"] as? [Double] ?? []
        let visible = Set(state["visible"] as? [Int] ?? [])
        let captions: [Double] = [18,34,22,28,40,26,20,30,38,24,28,32,42,20,24,30,36,44]
        XCTAssertEqual(measured.count, 42)
        for item in 0..<measured.count {
            XCTAssertEqual(measured[item], number(state, "track") * 0.35 + captions[item % captions.count]
                           + number(state, "revision") * 24, accuracy: 0.1, "\(name): independent measurement oracle")
        }
        for entry in frames {
            guard let item = entry["item"] as? Int, let f = entry["frame"] as? [Double] else { continue }
            if item % 6 == 0 {
                XCTAssertEqual(f[axis], Double(item / 6) * number(state, "stride"), accuracy: 1,
                               "\(name): group capacity/item mapping \(item)")
            }
            if visible.contains(item), measured.indices.contains(item) {
                XCTAssertEqual(f[axis + 2], measured[item], accuracy: 1, "\(name): item must keep natural measured size")
                let pageEnd = Double(item / 6) * number(state, "stride") + number(state, "pageExtent")
                XCTAssertLessThanOrEqual(f[axis] + f[axis + 2], pageEnd + 1, "\(name): content overflow")
            }
        }
    }
    private func number(_ state: [String: Any], _ key: String, _ index: Int? = nil) -> Double {
        if let index { return (state[key] as? [Double])?[index] ?? .nan }
        return (state[key] as? NSNumber)?.doubleValue ?? .nan
    }
    private func snapshot(_ app: XCUIApplication, name: String) throws -> [String: Any] {
        app.buttons["stable-snapshot"].tap()
        let value = try XCTUnwrap(app.staticTexts["stable-state"].value as? String)
        let attachment = XCTAttachment(string: value)
        attachment.name = name + ".json"
        attachment.lifetime = .keepAlways
        add(attachment)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
