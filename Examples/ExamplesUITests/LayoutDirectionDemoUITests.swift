import XCTest
import UIKit

@MainActor
final class LayoutDirectionDemoUITests: XCTestCase {
    func testNativeCollectionIndicatorDefault() { checkNativeCollectionIndicator([]) }
    func testNativeCollectionIndicatorEmbedded() { checkNativeCollectionIndicator(["-EmbeddedNativeIndicator"]) }
    func testNativeCollectionIndicatorCustomInsets() { checkNativeCollectionIndicator(["-CustomIndicatorInsets"]) }

    private func checkNativeCollectionIndicator(_ args: [String]) {
        let app = XCUIApplication()
        app.launchArguments = ["-NativeCollectionIndicator", "-CollectionIndicatorScreenshot"] + args
        app.launch()
        let directions = app.segmentedControls["layout-direction-control"]
        XCTAssertTrue(directions.waitForExistence(timeout: 10))
        directions.buttons["RTL"].tap()
        let grid = app.collectionViews["direction-grid"]
        XCTAssertGreaterThan(grid.cells["direction-grid-0"].frame.minX, grid.cells["direction-grid-1"].frame.minX)
        grid.swipeUp()
        let top = max(grid.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        let frame = CGRect(x: grid.frame.minX, y: top, width: grid.frame.width, height: grid.frame.maxY - top - 34)
        app.buttons["direction-flash-indicators"].tap()
        capture("native-rtl", app: app, indicatorIn: frame, onLeft: true,
                knownCollectionLimitation: args.contains("-EmbeddedNativeIndicator") || args.contains("-CustomIndicatorInsets"))
    }

    func testTableIndicatorDirectionRoundTripAfterScrolling() {
        checkTableIndicatorDirectionRoundTrip()
    }

    func testTableIndicatorDirectionFromInitialRTL() { checkTableIndicatorDirectionRoundTrip(initialRTL: true) }
    func testTableIndicatorDirectionWithCustomInsets() { checkTableIndicatorDirectionRoundTrip(customInsets: true) }

    private func checkTableIndicatorDirectionRoundTrip(initialRTL: Bool = false, customInsets: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["-LayoutDirectionDemo", "-TableIndicatorScreenshot"]
        if customInsets { app.launchArguments.append("-CustomTableIndicatorInsets") }
        app.launch()
        XCTAssertTrue(app.buttons["direction-table-page"].waitForExistence(timeout: 10))
        if initialRTL { app.segmentedControls["layout-direction-control"].buttons["RTL"].tap() }
        app.buttons["direction-table-page"].tap()
        let table = app.tables["direction-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        table.swipeUp()
        let directions = app.segmentedControls["layout-direction-control"]
        let top = app.navigationBars.firstMatch.frame.maxY
        let frame = CGRect(x: table.frame.minX, y: top, width: table.frame.width,
                           height: table.frame.maxY - top - 34)
        let anchor = table.cells["direction-table-15"]
        let anchorY = anchor.frame.minY
        app.buttons["direction-flash-indicators"].tap()
        capture("table-initial", app: app, indicatorIn: frame, onLeft: initialRTL)
        for (index, direction) in ["RTL", "LTR", "RTL", "系统默认"].enumerated() {
            directions.buttons[direction].tap()
            app.buttons["direction-flash-indicators"].tap()
            capture("table-\(index)-\(direction)", app: app, indicatorIn: frame, onLeft: direction == "RTL")
            XCTAssertEqual(anchor.frame.minY, anchorY, accuracy: 1, "Direction changes must preserve the visible row")
        }
    }

    func testDirectionRoundTripOnExistingLists() {
        checkDirectionRoundTrip(customIndicatorInsets: false)
    }

    func testDirectionRoundTripWithCustomIndicatorInsets() {
        checkDirectionRoundTrip(customIndicatorInsets: true)
    }

    func testEmbeddedDirectionRoundTrip() {
        checkDirectionRoundTrip(customIndicatorInsets: false, overview: true)
    }

    func testEmbeddedDirectionRoundTripWithCustomIndicatorInsets() {
        checkDirectionRoundTrip(customIndicatorInsets: true, overview: true)
    }

    private func checkDirectionRoundTrip(customIndicatorInsets: Bool, overview: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments += [overview ? "-LayoutDirectionOverview" : "-LayoutDirectionDemo"]
        if customIndicatorInsets { app.launchArguments += ["-CustomIndicatorInsets"] }
        app.launch()
        let directions = app.segmentedControls["layout-direction-control"]
        XCTAssertTrue(directions.waitForExistence(timeout: 10))
        let grid = app.collectionViews["direction-grid"]
        let first = grid.cells["direction-grid-0"]
        let second = grid.cells["direction-grid-1"]
        let mixedFirst = grid.cells["direction-mixed-0"]
        let mixedSecond = grid.cells["direction-mixed-1"]
        directions.buttons["LTR"].tap()
        XCTAssertTrue(wait { first.frame.minX < second.frame.minX })
        XCTAssertTrue(wait { mixedFirst.frame.minX < mixedSecond.frame.minX })
        let original = first.frame
        directions.buttons["RTL"].tap()
        XCTAssertTrue(wait { first.frame.minX > second.frame.minX })
        XCTAssertTrue(wait { mixedFirst.frame.minX > mixedSecond.frame.minX })
        let top = max(grid.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        let indicatorFrame = CGRect(x: grid.frame.minX, y: top, width: grid.frame.width, height: grid.frame.maxY - top - 34)
        app.buttons["direction-flash-indicators"].tap()
        capture("direction-rtl", app: app, indicatorIn: indicatorFrame, onLeft: true,
                knownCollectionLimitation: customIndicatorInsets || overview)
        directions.buttons["LTR"].tap()
        XCTAssertTrue(wait { abs(first.frame.minX - original.minX) < 1 })
        XCTAssertTrue(wait { mixedFirst.frame.minX < mixedSecond.frame.minX })
        app.buttons["direction-flash-indicators"].tap()
        capture("direction-ltr-indicators", app: app, indicatorIn: indicatorFrame, onLeft: false)
        directions.buttons["RTL"].tap()
        directions.buttons["系统默认"].tap()
        XCTAssertTrue(directions.buttons["系统默认"].isSelected)
        capture("direction-system", app: app)
        if overview { return }
        app.buttons["direction-table-page"].tap()
        let table = app.tables["direction-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        table.swipeUp()
        app.segmentedControls["layout-direction-control"].buttons["RTL"].tap()
        XCTAssertTrue(table.cells.firstMatch.exists)
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func capture(_ name: String, app: XCUIApplication, indicatorIn frame: CGRect? = nil,
                         onLeft: Bool = false, knownCollectionLimitation: Bool = false) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let frame else { return }
        // UIKit 的镜像坐标转换不一定等同最终呈现；直接检查截图中的原生灰色滚动条。
        guard let image = screenshot.image.cgImage else {
            XCTFail("Missing screenshot pixels")
            return
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(rendered)
        let scale = CGFloat(width) / app.frame.width
        func grayPixels(left: Bool) -> Int {
            let minX = Int((left ? frame.minX : frame.maxX - 20) * scale)
            let maxX = Int((left ? frame.minX + 20 : frame.maxX) * scale)
            var count = 0
            for y in Int((frame.minY + 12) * scale)..<Int((frame.maxY - 12) * scale) {
                for x in minX..<maxX {
                    let offset = (y * width + x) * 4
                    let rgb = pixels[offset..<(offset + 3)].map(Int.init)
                    if rgb.min()! > 60, rgb.max()! < 235, rgb.max()! - rgb.min()! < 8 { count += 1 }
                }
            }
            return count
        }
        let left = grayPixels(left: true)
        let right = grayPixels(left: false)
        // “滚动条已淡出”不属于已知方向缺陷，必须作为普通失败处理。
        XCTAssertGreaterThan(left + right, 30, "Expected a visible native indicator")
        let assertSide = {
            XCTAssertGreaterThan(onLeft ? left : right, 30, "Expected indicator side; left=\(left), right=\(right)")
            XCTAssertEqual(onLeft ? right : left, 0, "Indicator rendered on the wrong side")
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if knownCollectionLimitation && version.majorVersion == 26 && version.minorVersion == 5 {
            XCTExpectFailure("iOS 26.5：原生 Collection 在嵌入式/手动边距模式仍将 RTL 指示器放在右侧；自动边距开关刷新无效", failingBlock: assertSide)
        } else {
            assertSide()
        }
    }
}
