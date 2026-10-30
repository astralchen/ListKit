#if NATIVE_PAGING_PROBE
import XCTest

/// 实验测试故意保留失败断言；失败表示该原生更新路径没有修复分页。
@MainActor
final class NativePagingProbeUITests: XCTestCase {
    func testFixedControl() throws { try run(mode: "baseline", fixed: true) }
    func testEstimatedBaseline() throws { try run(mode: "baseline") }
    func testEstimatedInvalidate() throws { try run(mode: "invalidate") }
    func testEstimatedFullInvalidation() throws { try run(mode: "full") }
    func testEstimatedRebuild() throws { try run(mode: "rebuild") }
    func testSingleBaseline() throws { try run(mode: "baseline", single: true) }
    func testSingleRebuild() throws { try run(mode: "rebuild", single: true) }

    private func run(mode: String, fixed: Bool = false, single: Bool = false) throws {
        continueAfterFailure = true
        for vertical in [false, true] {
            let name = "\(mode)-\(vertical ? "vertical" : "horizontal")-\(fixed ? "fixed" : single ? "single" : "nested")"
            let app = XCUIApplication()
            app.launchArguments = ["-NativePagingProbe", "-ProbeMode", mode]
            if vertical { app.launchArguments.append("-ProbeVertical") }
            if fixed { app.launchArguments.append("-ProbeFixed") }
            if single { app.launchArguments.append("-ProbeSingle") }
            app.launch()
            let collection = app.collectionViews["probe-collection"]
            let first = collection.cells["probe-item-0"]
            guard first.waitForExistence(timeout: 10) else {
                XCTFail("\(name): fixture did not launch")
                app.terminate()
                continue
            }
            let initial = try snapshot(app, name: name + "-initial")
            let initialAgain = try snapshot(app, name: name + "-stable")
            XCTAssertEqual(frame(initial, item: 0), frame(initialAgain, item: 0), "initial geometry must be stable")
            if !fixed { XCTAssertGreaterThan(initial["fits"] as? Int ?? 0, 0) }
            let expectedSizes: [CGFloat] = fixed ? Array(repeating: 100, count: 6) : [40,100,60,70,110,90]
            for item in 0..<(single ? 1 : 6) {
                let f = frame(initialAgain, item: item)
                XCTAssertEqual(vertical ? f.height : f.width, expectedSizes[item], accuracy: 1,
                               "\(name): initial self-sizing item \(item)")
            }
            app.buttons["probe-intervention"].tap()
            let ready = try snapshot(app, name: name + "-ready")
            XCTAssertEqual(ready["interventions"] as? Int, 1)
            // 记录更新是否改变 offset；测试不会恢复或调整滚动位置。
            let origin = vertical ? first.frame.minY : first.frame.minX
            let capacity = single ? 1 : 6
            let mainExtent: CGFloat = fixed ? 320 : single ? 40 : 300
            capture(app, name: name + "-before")
            drag(app, collection: collection, vertical: vertical, distance: single ? 60 : (mainExtent + 20) * 0.65)
            let after = try snapshot(app, name: name + "-after-first")
            capture(app, name: name + "-after-first")
            let next = collection.cells["probe-item-\(capacity)"]
            let error = next.exists ? (vertical ? next.frame.minY : next.frame.minX) - origin : CGFloat.infinity
            print("PAGING_RESULT \(name) first error=\(error) offset=\(String(describing: after["offset"])) providers=\(String(describing: after["providers"]))")
            XCTAssertTrue(next.exists, "\(name): next group must be visible")
            XCTAssertEqual(error, 0, accuracy: 1, "\(name): native first page must align with measured group")
            // 再次真实拖动，检查第二个、不同长度的 group；不因首个断言失败而丢失后续证据。
            let secondExtent: CGFloat = fixed ? 320 : single ? 100 : 270
            drag(app, collection: collection, vertical: vertical, distance: (secondExtent + 20) * 0.65)
            let second = try snapshot(app, name: name + "-after-second")
            capture(app, name: name + "-after-second")
            let third = collection.cells["probe-item-\(capacity * 2)"]
            let secondError = third.exists ? (vertical ? third.frame.minY : third.frame.minX) - origin : CGFloat.infinity
            print("PAGING_RESULT \(name) second error=\(secondError) offset=\(String(describing: second["offset"]))")
            XCTAssertTrue(third.exists, "\(name): third group must be visible")
            XCTAssertEqual(secondError, 0, accuracy: 1, "\(name): native second page must align with measured group")
            let trace = app.staticTexts["probe-trace"].value as? String ?? "missing"
            let attachment = XCTAttachment(string: trace)
            attachment.name = name + "-trace.json"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    private func snapshot(_ app: XCUIApplication, name: String) throws -> [String: Any] {
        app.buttons["probe-snapshot"].tap()
        let value = try XCTUnwrap(app.staticTexts["probe-state"].value as? String)
        let attachment = XCTAttachment(string: value)
        attachment.name = name + ".json"
        attachment.lifetime = .keepAlways
        add(attachment)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
    private func frame(_ state: [String: Any], item: Int) -> CGRect {
        let frames = state["frames"] as? [[String: Any]] ?? []
        let values = frames.first { ($0["item"] as? Int) == item }?["frame"] as? [Double] ?? [0,0,0,0]
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    private func drag(_ app: XCUIApplication, collection: XCUIElement, vertical: Bool, distance: CGFloat) {
        let frame = collection.frame
        let startPoint = CGPoint(x: vertical ? frame.midX : frame.maxX - 20,
                                 y: vertical ? frame.maxY - 20 : frame.midY)
        let endPoint = CGPoint(x: startPoint.x - (vertical ? 0 : distance),
                               y: startPoint.y - (vertical ? distance : 0))
        let root = app.coordinate(withNormalizedOffset: .zero)
        root.withOffset(CGVector(dx: startPoint.x, dy: startPoint.y))
            .press(forDuration: 0.1, thenDragTo: root.withOffset(CGVector(dx: endPoint.x, dy: endPoint.y)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

#endif
