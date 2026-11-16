import XCTest
import UIKit

@MainActor
final class LayoutDirectionDemoUITests: XCTestCase {
    func testNativeIndicatorAutomaticAdjustmentTriggers() { checkNativeIndicatorProbe(boundaries: false) }
    func testNativeIndicatorSystemBarBoundaries() { checkNativeIndicatorProbe(boundaries: true) }

    func testNativeIndicatorTopGeometry() { checkNativeIndicatorProbe(boundaries: false, topGeometry: true) }

    private func checkNativeIndicatorProbe(boundaries: Bool, topGeometry: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["-NativeCollectionIndicator", "-NativeMixedLayout", "-NativeIndicatorTriggerProbe",
                               "-CollectionIndicatorScreenshot", "-AppleLanguages", "(en)"]
        if boundaries { app.launchArguments.append("-NativeIndicatorBoundaryProbe") }
        if topGeometry { app.launchArguments.append("-NativeIndicatorTopProbe") }
        app.launch()
        let directions = app.segmentedControls["layout-direction-control"]
        XCTAssertTrue(directions.waitForExistence(timeout: 10))
        directions.buttons["RTL"].tap()
        let grid = app.collectionViews["direction-grid"]
        XCTAssertGreaterThan(grid.cells["direction-grid-0"].frame.minX, grid.cells["direction-grid-1"].frame.minX)
        XCTAssertGreaterThan(grid.cells["direction-horizontal-0"].frame.minX, grid.cells["direction-horizontal-1"].frame.minX)
        let firstHorizontal = grid.cells["direction-horizontal-0"]
        let originalGridY = grid.cells["direction-grid-0"].frame.minY
        let dragStart = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0))
            .withOffset(CGVector(dx: 0, dy: firstHorizontal.frame.midY - grid.frame.minY))
        dragStart.press(forDuration: 0.1, thenDragTo: dragStart.withOffset(CGVector(dx: grid.frame.width * 0.55, dy: 0)))
        XCTAssertTrue(grid.cells["direction-horizontal-3"].isHittable)
        XCTAssertEqual(grid.cells["direction-grid-0"].frame.minY, originalGridY, accuracy: 1)
        let steps = topGeometry
            ? ["baseline", "top-0-wide", "top-0-narrow", "top-1-wide", "top-1-narrow",
               "top-61-wide", "top-149-wide", "top-150-wide", "full-again"]
            : boundaries
            ? ["baseline", "window-top-underlap", "window-top-edge", "window-top-clear", "nav-underlap", "nav-edge", "nav-clear", "home-underlap", "home-edge", "home-clear",
               "full-again", "disable-bar-observation", "enable-bar-observation"]
            : ["baseline", "auto-off", "auto-on", "top-only", "zero-after-top", "bottom-only",
                     "zero-after-bottom", "both", "zero-after-both", "horizontal-only", "zero-after-horizontal",
                     "horizontal-indicator-only", "horizontal-indicator-zero", "content-never", "content-auto",
                     "embedded", "embedded-safe-add", "embedded-safe-remove", "full-again"]
        for step in steps {
            XCTContext.runActivity(named: step) { _ in
                app.buttons["indicator-probe-next"].tap()
                XCTAssertTrue(wait { grid.label.contains("probe=\(step);") })
                let metrics = XCTAttachment(string: grid.label)
                metrics.name = "trigger-\(step)-metrics"
                metrics.lifetime = .keepAlways
                add(metrics)
                let top = max(grid.frame.minY, app.navigationBars.firstMatch.frame.maxY)
                let frame = CGRect(x: grid.frame.minX, y: top, width: grid.frame.width, height: grid.frame.maxY - top - 34)
                app.buttons["direction-flash-indicators"].tap()
                capture("trigger-\(step)", app: app, indicatorIn: frame, recordIndicatorSideOnly: true)
            }
        }
    }

    func testNativeInitialCompositionalArabicEmbedded() { checkNativeCollectionIndicator(["-NativeInitialCompositionalLayout", "-NativeMixedLayout", "-EmbeddedNativeIndicator", "-NativeLanguageStartup", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]) }
    func testNativeInitialCompositionalArabicCustomInsets() { checkNativeCollectionIndicator(["-NativeInitialCompositionalLayout", "-NativeMixedLayout", "-CustomIndicatorInsets", "-NativeLanguageStartup", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]) }
    func testNativeInitialCompositionalDirectionEmbedded() { checkNativeCollectionIndicator(["-NativeInitialCompositionalLayout", "-NativeMixedLayout", "-EmbeddedNativeIndicator"]) }
    func testNativeInitialCompositionalDirectionCustomInsets() { checkNativeCollectionIndicator(["-NativeInitialCompositionalLayout", "-NativeMixedLayout", "-CustomIndicatorInsets"]) }

    func testNativeMixedPublicConfigurationEmbedded() {
        for configuration in ["default", "automatic", "none", "margins", "readable", "adjust-always", "adjust-never"] {
            XCTContext.runActivity(named: "Embedded: \(configuration)") { _ in
                checkNativeCollectionIndicator(["-NativeMixedLayout", "-NativeCompositionalCase", configuration, "-EmbeddedNativeIndicator"])
            }
        }
    }
    func testNativeMixedPublicConfigurationCustomInsets() {
        for configuration in ["default", "automatic", "none", "margins", "readable", "adjust-always", "adjust-never"] {
            XCTContext.runActivity(named: "CustomInsets: \(configuration)") { _ in
                checkNativeCollectionIndicator(["-NativeMixedLayout", "-NativeCompositionalCase", configuration, "-CustomIndicatorInsets"])
            }
        }
    }

    func testNativeMixedNeverCustomInsets() { checkNativeCollectionIndicator(["-NativeMixedLayout", "-NativeCompositionalCase", "adjust-never", "-CustomIndicatorInsets"]) }
    func testNativeMixedDefault() { checkNativeCollectionIndicator(["-NativeMixedLayout"]) }
    func testNativeListFactoryGroupedEmbedded() { checkNativeCollectionIndicator(["-NativeCompositionalCase", "list-factory", "-NativeGroupedList", "-EmbeddedNativeIndicator"]) }
    func testNativeListFactoryGroupedCustomInsets() { checkNativeCollectionIndicator(["-NativeCompositionalCase", "list-factory", "-NativeGroupedList", "-CustomIndicatorInsets"]) }
    func testNativeListFactoryEmbedded() { checkNativeCollectionIndicator(["-NativeCompositionalCase", "list-factory", "-EmbeddedNativeIndicator"]) }
    func testNativeListFactoryCustomInsets() { checkNativeCollectionIndicator(["-NativeCompositionalCase", "list-factory", "-CustomIndicatorInsets"]) }
    func testNativeMixedListSectionEmbedded() { checkNativeCollectionIndicator(["-NativeMixedLayout", "-NativeCompositionalCase", "list-section", "-EmbeddedNativeIndicator"]) }
    func testNativeMixedListSectionCustomInsets() { checkNativeCollectionIndicator(["-NativeMixedLayout", "-NativeCompositionalCase", "list-section", "-CustomIndicatorInsets"]) }

    func testNativeFlowArabicEmbedded() { checkNativeCollectionIndicator(["-NativeCollectionLayout", "flow", "-NativeLanguageStartup", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-EmbeddedNativeIndicator"]) }
    func testNativeFlowArabicCustomInsets() { checkNativeCollectionIndicator(["-NativeCollectionLayout", "flow", "-NativeLanguageStartup", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-CustomIndicatorInsets"]) }
    func testNativeFlowDirectionEmbedded() { checkNativeCollectionIndicator(["-NativeCollectionLayout", "flow", "-EmbeddedNativeIndicator"]) }
    func testNativeFlowDirectionCustomInsets() { checkNativeCollectionIndicator(["-NativeCollectionLayout", "flow", "-CustomIndicatorInsets"]) }
    func testNativeSystemLanguageEmbedded() throws { try checkNativeSystemLanguage(["-EmbeddedNativeIndicator"]) }
    func testNativeSystemLanguageCustomInsets() throws { try checkNativeSystemLanguage(["-CustomIndicatorInsets"]) }

    private func checkNativeSystemLanguage(_ args: [String]) throws {
        guard ProcessInfo.processInfo.environment["LISTKIT_VERIFY_SYSTEM_RTL"] == "1" else {
            throw XCTSkip("需先把目标模拟器的全局首选语言设置为阿拉伯语；验证后恢复原设置")
        }
        checkNativeCollectionIndicator(["-NativeLanguageStartup", "-NativeSystemLanguageStartup"] + args)
    }

    func testNativeArabicLanguageDefault() { checkNativeCollectionIndicator(["-NativeLanguageStartup", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]) }
    func testNativeArabicLanguageEmbedded() { checkNativeCollectionIndicator(["-NativeLanguageStartup", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-EmbeddedNativeIndicator"]) }
    func testNativeArabicLanguageCustomInsets() { checkNativeCollectionIndicator(["-NativeLanguageStartup", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-CustomIndicatorInsets"]) }
    func testNativeSceneRTLBeforeWindowDefault() { checkNativeCollectionIndicator(["-NativeSceneRTLBeforeWindow", "-NativeDirectionScope", "scene"]) }
    func testNativeSceneRTLBeforeWindowEmbedded() { checkNativeCollectionIndicator(["-NativeSceneRTLBeforeWindow", "-EmbeddedNativeIndicator", "-NativeDirectionScope", "scene"]) }
    func testNativeSceneRTLBeforeWindowCustomInsets() { checkNativeCollectionIndicator(["-NativeSceneRTLBeforeWindow", "-CustomIndicatorInsets", "-NativeDirectionScope", "scene"]) }
    func testNativeSceneDirectionEmbedded() { checkNativeCollectionIndicator(["-EmbeddedNativeIndicator", "-NativeDirectionScope", "scene"]) }
    func testNativeSceneDirectionCustomInsets() { checkNativeCollectionIndicator(["-CustomIndicatorInsets", "-NativeDirectionScope", "scene"]) }
    func testNativeWindowDirectionEmbedded() { checkNativeCollectionIndicator(["-EmbeddedNativeIndicator", "-NativeDirectionScope", "window"]) }
    func testNativeWindowDirectionCustomInsets() { checkNativeCollectionIndicator(["-CustomIndicatorInsets", "-NativeDirectionScope", "window"]) }
    func testNativeControllerDirectionEmbedded() { checkNativeCollectionIndicator(["-EmbeddedNativeIndicator", "-NativeDirectionScope", "controller"]) }
    func testNativeControllerDirectionCustomInsets() { checkNativeCollectionIndicator(["-CustomIndicatorInsets", "-NativeDirectionScope", "controller"]) }
    func testNativeVisibilityRefreshEmbedded() { checkNativeCollectionIndicator(["-EmbeddedNativeIndicator", "-NativeIndicatorVisibilityRefresh", "immediate"]) }
    func testNativeVisibilityRefreshEmbeddedDelayed() { checkNativeCollectionIndicator(["-EmbeddedNativeIndicator", "-NativeIndicatorVisibilityRefresh", "delayed"]) }
    func testNativeVisibilityRefreshCustomInsets() { checkNativeCollectionIndicator(["-CustomIndicatorInsets", "-NativeIndicatorVisibilityRefresh", "immediate"]) }
    func testNativeVisibilityRefreshCustomInsetsDelayed() { checkNativeCollectionIndicator(["-CustomIndicatorInsets", "-NativeIndicatorVisibilityRefresh", "delayed"]) }
    func testNativeDifferenceContentInset() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "content-inset"]) }
    func testNativeDifferenceChildSafeArea() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "child-safe-area"]) }
    func testNativeDifferenceZeroSet() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "zero-set"]) }
    func testNativeDifferenceNarrow() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "narrow"]) }
    func testNativeDifferenceShort() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "short"]) }
    func testNativeDifferenceBelowBar() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "below-bar"]) }
    func testNativeDifferenceSafeArea() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "safe-area"]) }
    func testNativeDifferenceManualZero() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "manual-zero"]) }
    func testNativeDifferenceAutomaticCustom() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "auto-custom"]) }
    func testNativeDifferenceTopInsets() { checkNativeCollectionIndicator(["-NativeIndicatorCase", "top-insets"]) }
    func testNativeCollectionIndicatorDefault() { checkNativeCollectionIndicator([]) }
    func testNativeCollectionIndicatorEmbedded() { checkNativeCollectionIndicator(["-EmbeddedNativeIndicator"]) }
    func testNativeCollectionIndicatorCustomInsets() { checkNativeCollectionIndicator(["-CustomIndicatorInsets"]) }

    private func checkNativeCollectionIndicator(_ args: [String]) {
        let app = XCUIApplication()
        app.launchArguments = ["-NativeCollectionIndicator", "-CollectionIndicatorScreenshot"] + args
        // Scene trait 对照固定使用英语，避免测试依赖设备语言；系统语言用例不传语言参数。
        if !args.contains("-NativeLanguageStartup") { app.launchArguments += ["-AppleLanguages", "(en)"] }
        app.launch()
        let directions = app.segmentedControls["layout-direction-control"]
        XCTAssertTrue(directions.waitForExistence(timeout: 10))
        let initialSceneRTL = args.contains("-NativeSceneRTLBeforeWindow")
        let languageStartup = args.contains("-NativeLanguageStartup")
        if languageStartup {
            XCTAssertTrue(directions.buttons["系统默认"].isSelected)
        } else if initialSceneRTL {
            XCTAssertTrue(directions.buttons["RTL"].isSelected)
        } else {
            directions.buttons["RTL"].tap()
        }
        let grid = app.collectionViews["direction-grid"]
        if initialSceneRTL || languageStartup {
            XCTAssertTrue(wait { grid.label.contains("trait=1; effective=1; controllerTrait=1; windowTrait=1; sceneTrait=1") }, grid.label)
        }
        if languageStartup {
            XCTAssertTrue(grid.label.contains("bundleLanguage=ar; applicationDirection=1; sceneOverride=false; collectionOverride=false; semantic=0"), grid.label)
            if args.contains("-NativeSystemLanguageStartup") {
                XCTAssertTrue(grid.label.contains("argumentLanguageOverride=false"), grid.label)
            }
        }
        if args.contains("list-factory") {
            XCTAssertLessThan(grid.cells["direction-grid-0"].frame.minY, grid.cells["direction-grid-1"].frame.minY)
        } else {
            XCTAssertGreaterThan(grid.cells["direction-grid-0"].frame.minX, grid.cells["direction-grid-1"].frame.minX)
        }
        // 全屏 .never 不避让导航栏，顶部横向 section 被遮挡；此组合只检查网格和指示器。
        if args.contains("-NativeMixedLayout") && !(args.contains("adjust-never") && !args.contains("-EmbeddedNativeIndicator")) {
            let first = grid.cells["direction-horizontal-0"]
            let second = grid.cells["direction-horizontal-1"]
            XCTAssertGreaterThan(first.frame.minX, second.frame.minX)
            // RTL 向右拖动，后续项目应进入视口，同时纵向位置不变。
            let originalY = grid.cells["direction-grid-0"].frame.minY
            let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0))
                .withOffset(CGVector(dx: 0, dy: first.frame.midY - grid.frame.minY))
            let end = start.withOffset(CGVector(dx: grid.frame.width * 0.55, dy: 0))
            start.press(forDuration: 0.1, thenDragTo: end)
            XCTAssertTrue(grid.cells["direction-horizontal-3"].isHittable)
            XCTAssertEqual(grid.cells["direction-grid-0"].frame.minY, originalY, accuracy: 1)
        }
        grid.swipeUp()
        let top = max(grid.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        let frame = CGRect(x: grid.frame.minX, y: top, width: grid.frame.width, height: grid.frame.maxY - top - 34)
        app.buttons["direction-flash-indicators"].tap()
        let knownModes: Set<String> = ["child-safe-area", "content-inset", "auto-custom", "manual-zero", "safe-area", "top-insets"]
        let mode = args.firstIndex(of: "-NativeIndicatorCase").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let scoped = args.contains("-NativeDirectionScope")
        let flow = args.contains("flow")
        capture("native-rtl", app: app, indicatorIn: frame, onLeft: true,
                knownCollectionLimitation: !flow && (languageStartup || initialSceneRTL || args.contains("-EmbeddedNativeIndicator") || args.contains("-CustomIndicatorInsets") || mode.map(knownModes.contains) == true))
        if args.contains("-NativeIndicatorCase") || scoped || languageStartup || flow || args.contains("-NativeCompositionalCase") || args.contains("-NativeMixedLayout") {
            let metrics = XCTAttachment(string: grid.label)
            metrics.name = "native-indicator-metrics"
            metrics.lifetime = .keepAlways
            add(metrics)
        }
        if scoped {
            XCTAssertTrue(grid.label.contains("trait=1; effective=1; controllerTrait=1"), grid.label)
            directions.buttons["LTR"].tap()
            app.buttons["direction-flash-indicators"].tap()
            // 创建窗口前已为 RTL 的全屏默认配置，切回 LTR 后指示器反而留在左侧。
            let initialFullScreenLimitation = initialSceneRTL && !args.contains("-EmbeddedNativeIndicator") && !args.contains("-CustomIndicatorInsets")
            capture("native-scope-ltr", app: app, indicatorIn: frame, onLeft: false,
                    knownCollectionLimitation: initialFullScreenLimitation)
            XCTAssertTrue(grid.label.contains("trait=0; effective=0; controllerTrait=0"), grid.label)
            directions.buttons["系统默认"].tap()
            XCTAssertTrue(grid.label.contains("trait=0; effective=0; controllerTrait=0"), grid.label)
        }
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

    func testListKitArabicLaunchWithCustomIndicatorInsets() {
        checkListKitArabicIndicator(["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"], custom: true)
    }

    func testListKitArabicLaunchWithAutomaticIndicatorInsets() {
        checkListKitArabicIndicator(["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"], custom: false)
    }

    func testListKitSystemArabicLaunchWithCustomIndicatorInsets() throws {
        try requireSystemArabic()
        checkListKitArabicIndicator([], custom: true)
    }

    func testListKitSystemArabicLaunchWithAutomaticIndicatorInsets() throws {
        try requireSystemArabic()
        checkListKitArabicIndicator([], custom: false)
    }

    func testListKitSystemArabicLaunchInEmbeddedLayout() throws {
        try requireSystemArabic()
        checkListKitArabicIndicator([], custom: false, overview: true)
    }

    private func requireSystemArabic() throws {
        guard ProcessInfo.processInfo.environment["LISTKIT_VERIFY_SYSTEM_RTL"] == "1" else {
            throw XCTSkip("Run on a simulator whose system language is Arabic")
        }
    }

    private func checkListKitArabicIndicator(_ arguments: [String], custom: Bool, overview: Bool = false) {
        checkListKitLanguageIndicator("ar", arguments: arguments, custom: custom, overview: overview)
    }

    func testListKitSystemHebrewLaunchWithAutomaticIndicatorInsets() throws {
        try requireSystemHebrew()
        checkListKitLanguageIndicator("he", arguments: [], custom: false, checkReturnToSystem: true)
    }

    func testListKitSystemHebrewLaunchWithCustomIndicatorInsets() throws {
        try requireSystemHebrew()
        checkListKitLanguageIndicator("he", arguments: [], custom: true, checkReturnToSystem: true)
    }

    func testListKitSimplifiedChineseLaunchUsesSystemLTR() {
        checkListKitLanguageIndicator("zh-Hans", arguments: ["-AppleLanguages", "(zh-Hans-CN)", "-AppleLocale", "zh_CN"],
                                      custom: false, isRTL: false)
    }

    func testSystemChineseColdLaunchAndReturnFromRTL() throws {
        guard ProcessInfo.processInfo.environment["LISTKIT_VERIFY_SYSTEM_CHINESE"] == "1" else {
            throw XCTSkip("Run on a device whose system language is Simplified Chinese")
        }
        continueAfterFailure = false
        let preferences = Locale.preferredLanguages
        XCTAssertTrue(preferences.first?.hasPrefix("zh-Hans") == true, "Device languages: \(preferences)")
        let app = XCUIApplication()
        XCTAssertTrue(app.launchArguments.isEmpty)
        let launchEvidence = XCTAttachment(string: "Device languages: \(preferences); launchArguments: \(app.launchArguments)")
        launchEvidence.name = "system-chinese-cold-launch-environment"
        launchEvidence.lifetime = .keepAlways
        add(launchEvidence)
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launch()

        let openGrid = app.navigationBars.buttons["Grid"]
        XCTAssertTrue(openGrid.waitForExistence(timeout: 15))
        openGrid.tap()
        let openDirection = app.navigationBars.buttons["布局方向"]
        XCTAssertTrue(openDirection.waitForExistence(timeout: 10))
        openDirection.tap()

        let directions = app.segmentedControls["layout-direction-control"]
        let grid = app.collectionViews["direction-grid"]
        let first = grid.cells["direction-grid-0"]
        let second = grid.cells["direction-grid-1"]
        let system = directions.buttons["系统默认"]
        XCTAssertTrue(system.waitForExistence(timeout: 10))
        XCTAssertTrue(system.isSelected)
        XCTAssertTrue(wait { first.exists && second.exists && first.frame.minX < second.frame.minX })
        let flash = app.buttons["direction-flash-indicators"]
        let frame = indicatorSearchFrame(grid: grid, app: app)
        grid.swipeUp()
        flash.tap()
        capture("system-chinese-cold-right", app: app, indicatorIn: frame, onLeft: false)

        grid.swipeDown()
        XCTAssertTrue(wait { first.isHittable && second.isHittable })
        directions.buttons["RTL"].tap()
        XCTAssertTrue(wait { first.exists && second.exists && first.frame.minX > second.frame.minX })
        flash.tap()
        capture("system-chinese-explicit-rtl-left", app: app, indicatorIn: frame, onLeft: true)

        system.tap()
        XCTAssertTrue(system.isSelected)
        XCTAssertTrue(wait { first.exists && second.exists && first.frame.minX < second.frame.minX })
        flash.tap()
        capture("system-chinese-restored-right", app: app, indicatorIn: frame, onLeft: false)
    }

    private func requireSystemHebrew() throws {
        guard ProcessInfo.processInfo.environment["LISTKIT_VERIFY_SYSTEM_HEBREW"] == "1" else {
            throw XCTSkip("Run on a device whose system language is Hebrew")
        }
    }

    private func checkListKitLanguageIndicator(
        _ language: String, arguments: [String], custom: Bool, overview: Bool = false, isRTL: Bool = true,
        checkReturnToSystem: Bool = false
    ) {
        let app = XCUIApplication()
        app.launchArguments = [overview ? "-LayoutDirectionOverview" : "-LayoutDirectionDemo",
                               "-CheckIndicatorLanguageLaunch"] + arguments
        if custom { app.launchArguments.append("-CustomIndicatorInsets") }
        app.launch()
        let grid = app.collectionViews["direction-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        let expectedInsets = custom ? "8.0,4.0,8.0,12.0" : "0.0,0.0,0.0,0.0"
        let expectedDirection = isRTL ? "rtl" : "ltr"
        let expected = "\(language);\(expectedDirection);unspecified;languageArgument=\(!arguments.isEmpty)"
            + ";vertical=\(expectedInsets);auto=\(!custom)"
        let matches = wait { grid.label == expected }
        let metrics = XCTAttachment(string: "\(grid.label);\(grid.value ?? "")")
        metrics.name = "\(language)-launch-environment"
        metrics.lifetime = .keepAlways
        add(metrics)
        guard matches else {
            XCTFail("Unexpected launch environment: \(grid.label);\(grid.value ?? "")")
            return
        }
        let first = grid.cells["direction-grid-0"].frame.minX
        let second = grid.cells["direction-grid-1"].frame.minX
        if isRTL {
            XCTAssertGreaterThan(first, second)
            checkHorizontalGesture(in: grid)
        } else {
            XCTAssertLessThan(first, second)
        }
        grid.swipeUp()
        let frame = indicatorSearchFrame(grid: grid, app: app)
        let verifySide = !isRTL || (language == "he" && ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 18)
        app.buttons["direction-flash-indicators"].tap()
        capture("listkit-\(language)-system-indicator", app: app, indicatorIn: frame, onLeft: isRTL,
                recordIndicatorSideOnly: !verifySide)
        if checkReturnToSystem {
            let directions = app.segmentedControls["layout-direction-control"]
            for (button, direction) in [("LTR", "ltr"), ("RTL", "rtl")] {
                directions.buttons[button].tap()
                XCTAssertTrue(wait { grid.label.hasPrefix("\(language);\(direction);explicit;") }, grid.label)
                directions.buttons["系统默认"].tap()
                XCTAssertTrue(wait { grid.label == expected }, "Unexpected restored environment: \(grid.label)")
                app.buttons["direction-flash-indicators"].tap()
                capture("listkit-\(language)-system-after-\(button)", app: app, indicatorIn: frame,
                        onLeft: isRTL, recordIndicatorSideOnly: !verifySide)
            }
        }
    }

    private func checkHorizontalGesture(in grid: XCUIElement) {
        let first = grid.cells["direction-mixed-0"]
        let firstGridY = grid.cells["direction-grid-0"].frame.minY
        XCTAssertGreaterThan(first.frame.minX, grid.cells["direction-mixed-1"].frame.minX)
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0))
            .withOffset(CGVector(dx: 0, dy: first.frame.midY - grid.frame.minY))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: grid.frame.width * 0.55, dy: 0)))
        XCTAssertTrue(grid.cells["direction-mixed-3"].isHittable)
        XCTAssertEqual(grid.cells["direction-grid-0"].frame.minY, firstGridY, accuracy: 1)
    }

    private func indicatorSearchFrame(grid: XCUIElement, app: XCUIApplication) -> CGRect {
        let top = max(grid.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        return CGRect(x: grid.frame.minX, y: top, width: grid.frame.width, height: grid.frame.maxY - top - 34)
    }

    private func checkDirectionRoundTrip(customIndicatorInsets: Bool, overview: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments += [overview ? "-LayoutDirectionOverview" : "-LayoutDirectionDemo", "-AppleLanguages", "(en)"]
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
        let indicatorFrame = indicatorSearchFrame(grid: grid, app: app)
        app.buttons["direction-flash-indicators"].tap()
        capture("direction-rtl", app: app, indicatorIn: indicatorFrame, onLeft: true,
                expectedLeftDistance: customIndicatorInsets ? 7 : 3)
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
                         onLeft: Bool = false, knownCollectionLimitation: Bool = false, recordIndicatorSideOnly: Bool = false,
                         expectedLeftDistance: CGFloat? = nil) {
        let screenshot = XCUIScreen.main.screenshot()
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
        func grayColumns(left: Bool) -> (x: Int, counts: [Int]) {
            let minX = Int((left ? frame.minX : frame.maxX - 20) * scale)
            let maxX = Int((left ? frame.minX + 20 : frame.maxX) * scale)
            var counts = Array(repeating: 0, count: maxX - minX)
            for y in Int((frame.minY + 12) * scale)..<Int((frame.maxY - 12) * scale) {
                for x in minX..<maxX {
                    let offset = (y * width + x) * 4
                    let rgb = pixels[offset..<(offset + 3)].map(Int.init)
                    if rgb.min()! > 60, rgb.max()! < 235, rgb.max()! - rgb.min()! < 8 { counts[x - minX] += 1 }
                }
            }
            return (minX, counts)
        }
        let leftColumns = grayColumns(left: true)
        let left = leftColumns.counts.reduce(0, +)
        let right = grayColumns(left: false).counts.reduce(0, +)
        // “滚动条已淡出”不属于已知方向缺陷，必须作为普通失败处理。
        XCTAssertGreaterThan(left + right, 30, "Expected a visible native indicator")
        if recordIndicatorSideOnly {
            let pixels = XCTAttachment(string: "left=\(left); right=\(right)")
            pixels.name = name + "-pixels"
            pixels.lifetime = .keepAlways
            add(pixels)
            XCTAssertTrue(left == 0 || right == 0, "Expected one visible indicator side")
            return
        }
        let assertSide = {
            XCTAssertGreaterThan(onLeft ? left : right, 30, "Expected indicator side; left=\(left), right=\(right)")
            XCTAssertEqual(onLeft ? right : left, 0, "Indicator rendered on the wrong side")
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if knownCollectionLimitation && version.majorVersion == 26 && version.minorVersion == 5 {
            XCTExpectFailure("iOS 26.5：原生 Collection 在已记录的容器、边距、Scene 方向或 RTL 语言启动配置下，指示器位于错误侧边，详见 README 对照实验", failingBlock: assertSide)
        } else {
            assertSide()
        }
        if let expectedLeftDistance, let longestColumn = leftColumns.counts.max(), longestColumn > 0,
           let offset = leftColumns.counts.firstIndex(where: { $0 > longestColumn / 2 }) {
            let distance = CGFloat(leftColumns.x + offset) / scale - frame.minX
            XCTAssertEqual(distance, expectedLeftDistance, accuracy: 1.0 / scale,
                           "Expected the same physical left inset as Flow Layout")
        }
    }
}
