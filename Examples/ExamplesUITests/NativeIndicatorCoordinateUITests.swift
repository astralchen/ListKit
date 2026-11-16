import UIKit
import XCTest

/// 比较屏幕像素，而不是把 UIKit 内部指示器的 frame 当作物理坐标。
@MainActor
final class NativeIndicatorCoordinateUITests: XCTestCase {
    func testFlowAndMixedCompositionalCoordinateResponse() throws {
        var samples: [String: [String: Any]] = [:]
        for layout in ["flow", "compositional"] {
            let app = XCUIApplication()
            app.launchArguments = ["-NativeCollectionIndicator", "-NativeMixedLayout", "-NativeIndicatorCoordinateProbe",
                                   "-CollectionIndicatorScreenshot", "-AppleLanguages", "(en)", "-AppleInterfaceStyle", "Light"]
            if layout == "flow" { app.launchArguments += ["-NativeCollectionLayout", "flow"] }
            app.launch()
            let directions = app.segmentedControls["layout-direction-control"]
            XCTAssertTrue(directions.waitForExistence(timeout: 10))
            directions.buttons["RTL"].tap()
            let grid = app.collectionViews["direction-grid"]
            // 两个对照都保留纵横混合内容，并做真实横向手势检查。
            let first = app.cells["direction-horizontal-0"].firstMatch
            let second = app.cells["direction-horizontal-1"].firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(first.frame.minX, second.frame.minX)
            XCTAssertGreaterThan(grid.cells["direction-grid-0"].frame.minX, grid.cells["direction-grid-1"].frame.minX)
            let gridY = grid.cells["direction-grid-0"].frame.minY
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: grid.frame.minX + grid.frame.width * 0.25, dy: first.frame.midY))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: grid.frame.width * 0.55, dy: 0)))
            XCTAssertTrue(app.cells["direction-horizontal-3"].firstMatch.isHittable)
            XCTAssertEqual(grid.cells["direction-grid-0"].frame.minY, gridY, accuracy: 1)

            let appFrame = app.frame
            let navigationBottom = app.navigationBars.firstMatch.frame.maxY
            let next = app.buttons["indicator-probe-next"]
            let flash = app.buttons["direction-flash-indicators"]
            for direction in ["ltr", "rtl"] {
                var layoutIdentity: String?
                for geometry in ["full", "embedded"] {
                    for adjustment in ["auto", "manual"] {
                        for inset in ["zero", "left4", "left24", "right12", "custom"] {
                            let step = "\(direction)-\(geometry)-\(adjustment)-\(inset)"
                            try XCTContext.runActivity(named: "\(layout)-\(step)") { _ in
                                try requireForeground(app)
                                next.tap()
                                let ready = NSPredicate { _, _ in
                                    (grid.value as? String)?.contains("\"step\":\"\(step)\"") == true
                                }
                                XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: grid)], timeout: 15), .completed)
                                let value = try XCTUnwrap(grid.value as? String)
                                var sample = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
                                guard sample["step"] as? String == step else {
                                    XCTFail("Probe did not settle at \(step): \(value)")
                                    throw CoordinateError.wrongStep
                                }
                                let identity = try XCTUnwrap(sample["layoutIdentity"] as? String)
                                if let layoutIdentity { XCTAssertEqual(identity, layoutIdentity, "Insets/geometry must not rebuild the layout") }
                                layoutIdentity = identity
                                XCTAssertEqual(sample["transform"] as? [Double], [1, 0, 0, 1, 0, 0])
                                let basis = try XCTUnwrap(sample["basis"] as? [Double])
                                XCTAssertEqual(abs(basis[1] - basis[0]), 1, accuracy: 0.001)
                                let window = try XCTUnwrap(sample["windowRect"] as? [CGFloat])
                                let searchTop = max(window[1], navigationBottom)
                                let search = CGRect(x: window[0], y: searchTop, width: window[2],
                                                    height: window[1] + window[3] - searchTop)
                                var measured: CGRect?
                                for attempt in 0..<3 {
                                    if attempt > 0 { flash.tap() }
                                    let screenshot = app.screenshot()
                                    try requireForeground(app)
                                    let attachment = XCTAttachment(screenshot: screenshot)
                                    attachment.name = "\(layout)-\(step)-attempt\(attempt)"
                                    attachment.lifetime = .keepAlways
                                    add(attachment)
                                    if let rect = try indicatorRect(screenshot, appFrame: appFrame, search: search) {
                                        measured = rect
                                        break
                                    }
                                }
                                let indicator = try XCTUnwrap(measured, "Expected visible native indicator after three flashes: \(value)")
                                sample["pixelRect"] = [indicator.minX, indicator.minY, indicator.width, indicator.height].map(Double.init)
                                print("IndicatorCoordinateSample " + String(data: try JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys]), encoding: .utf8)!)
                                if layout == "flow" {
                                    XCTAssertLessThan(direction == "rtl" ? indicator.midX - search.minX
                                                      : search.maxX - indicator.midX, 40)
                                }
                                samples["\(layout)-\(step)"] = sample
                            }
                        }
                    }
                }
            }
            app.terminate()
        }
        var comparisons: [[String: Any]] = []
        for key in samples.keys.sorted() where key.hasPrefix("flow-") {
            let step = String(key.dropFirst(5))
            let flow = try XCTUnwrap(samples[key])
            let compositional = try XCTUnwrap(samples["compositional-" + step])
            for property in ["windowRect", "safe", "adjusted", "content", "vertical", "offset", "contentSize"] {
                let lhs = try XCTUnwrap(flow[property] as? [Double])
                let rhs = try XCTUnwrap(compositional[property] as? [Double])
                XCTAssertEqual(lhs.count, rhs.count)
                for (a, b) in zip(lhs, rhs) { XCTAssertEqual(a, b, accuracy: 0.5, "\(step): \(property)") }
            }
            XCTAssertEqual(flow["auto"] as? Bool, compositional["auto"] as? Bool)
            let fBasis = try XCTUnwrap(flow["basis"] as? [Double])
            let cBasis = try XCTUnwrap(compositional["basis"] as? [Double])
            XCTAssertEqual(fBasis[1] - fBasis[0], 1, accuracy: 0.001)
            XCTAssertEqual(abs(cBasis[1] - cBasis[0]), 1, accuracy: 0.001)
            let f = try XCTUnwrap(flow["pixelRect"] as? [Double])
            let c = try XCTUnwrap(compositional["pixelRect"] as? [Double])
            let window = try XCTUnwrap(flow["windowRect"] as? [Double])
            let identical = abs(c[0] - f[0]) < 1.5
            let reflected = abs(c[0] - (2 * window[0] + window[2] - f[0] - f[2])) < 1.5
            // 这是坐标路径诊断：允许测得相同或镜像，但不允许把缺失指示器当成通过。
            XCTAssertTrue(identical || reflected, "Unexpected coordinate mapping: \(step), Flow=\(f), Compositional=\(c)")
            XCTAssertEqual(f[2], c[2], accuracy: 1.5, "\(step): indicator width")
            XCTAssertEqual(f[1], c[1], accuracy: 1.5, "\(step): vertical origin")
            XCTAssertEqual(f[3], c[3], accuracy: 1.5, "\(step): vertical length")
            comparisons.append(["step": step, "mapping": identical ? "identical" : "reflected", "flow": f, "compositional": c])
        }
        for geometry in ["full", "embedded"] {
            for adjustment in ["auto", "manual"] {
                for layout in ["flow", "compositional"] {
                    let prefix = "\(layout)-rtl-\(geometry)-\(adjustment)-"
                    let small = try XCTUnwrap(samples[prefix + "left4"])
                    let large = try XCTUnwrap(samples[prefix + "left24"])
                    let first = try XCTUnwrap(small["pixelRect"] as? [Double])
                    let last = try XCTUnwrap(large["pixelRect"] as? [Double])
                    let basis = try XCTUnwrap(small["basis"] as? [Double])
                    XCTAssertEqual(last[0] - first[0], 20 * (basis[1] - basis[0]), accuracy: 1.5,
                                   "Left inset displacement should follow the measured public coordinate basis: \(prefix)")
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["samples": samples, "comparisons": comparisons,
            "os": ProcessInfo.processInfo.operatingSystemVersionString], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "indicator-coordinate-results.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum CoordinateError: Error { case wrongStep, lostForeground }

    private func requireForeground(_ app: XCUIApplication) throws {
        guard app.state == .runningForeground else {
            XCTFail("Another app took the sampling screen; reject this run")
            throw CoordinateError.lostForeground
        }
    }

    private func indicatorRect(_ screenshot: XCUIScreenshot, appFrame: CGRect, search: CGRect) throws -> CGRect? {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let width = image.width, height = image.height
        let scale = CGFloat(width) / appFrame.width
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
        let y0 = max(0, Int((search.minY + 8) * scale))
        let y1 = min(height, Int((search.maxY - 12) * scale))
        var columns: [(x: Int, start: Int, end: Int)] = []
        for edge in [search.minX..<(search.minX + 40), (search.maxX - 40)..<search.maxX] {
            for x in max(0, Int(edge.lowerBound * scale))..<min(width, Int(edge.upperBound * scale)) {
                var start = y0
                for y in y0...y1 {
                    var gray = false
                    if y < y1 {
                        let i = (y * width + x) * 4
                        let rgb = [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
                        gray = rgb.min()! > 60 && rgb.max()! < 235 && rgb.max()! - rgb.min()! < 8
                    }
                    if !gray {
                        if y - start >= Int(18 * scale) { columns.append((x, start, y)) }
                        start = y + 1
                    }
                }
            }
        }
        guard let minX = columns.map(\.x).min() else { return nil }
        let maxX = try XCTUnwrap(columns.map(\.x).max())
        XCTAssertLessThan(CGFloat(maxX - minX + 1) / scale, 8, "Expected a single narrow indicator")
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(columns.map(\.start).min()!) / scale,
                      width: CGFloat(maxX - minX + 1) / scale,
                      height: CGFloat(columns.map(\.end).max()! - columns.map(\.start).min()!) / scale)
    }
}
