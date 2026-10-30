import UIKit
import XCTest
@testable import ListKit

@MainActor
final class LayoutAPISemanticsTests: XCTestCase {
    func testIndependentSpacingAndLineCountInAllDirections() throws {
        for outerHorizontal in [false, true] {
            for orthogonal in [false, true] {
                let fixture = LayoutFixture(width: 360, count: 7, horizontal: outerHorizontal)
                defer { fixture.close() }
                let horizontal = outerHorizontal != orthogonal
                let grid = GridLayout(tracks: 2)
                    .gridCrossAxisSize(.fixed(220)).itemMainAxisSize(.fixed(40))
                    .trackSpacing(10).lineSpacing(12).groupSpacing(20)
                    .lineGrouping(.count(lines: 3))
                    .orthogonalScrolling(orthogonal ? .continuous : nil)
                fixture.apply(grid); fixture.render()
                let first = try fixture.frame(0), second = try fixture.frame(1)
                let nextLine = try fixture.frame(2), nextGroup = try fixture.frame(6)
                XCTAssertEqual(horizontal ? first.height : first.width, 105, accuracy: 0.5)
                XCTAssertEqual(horizontal ? second.minY - first.maxY : second.minX - first.maxX, 10, accuracy: 0.5)
                XCTAssertEqual(horizontal ? nextLine.minX - first.maxX : nextLine.minY - first.maxY, 12, accuracy: 0.5)
                // 3 lines × 40 + 2 gaps × 12 + group spacing 20 = 164.
                XCTAssertEqual(horizontal ? nextGroup.minX - first.minX : nextGroup.minY - first.minY, 164, accuracy: 0.5)
                XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
            }
        }
    }

    func testFillAndFittingUseLineSpacingWithoutTrackOrGroupSpacing() throws {
        let environment = TestLayoutEnvironment()
        let base = GridLayout(tracks: 2).gridCrossAxisSize(.fixed(220))
            .trackSpacing(10).lineSpacing(12).groupSpacing(70)
        let filled = try base.itemMainAxisSize(.fillGroup)
            .lineGrouping(.count(lines: 3, mainAxisSize: .fixed(300)))
            .geometry(in: environment, scrollDirection: .vertical)
        XCTAssertEqual(filled.mainExtents, [92, 92])
        XCTAssertEqual(filled.groupExtent, 300)
        let fitted = try base.itemMainAxisSize(.fixed(90))
            .lineGrouping(.fitting(mainAxisSize: .fixed(300)))
            .geometry(in: environment, scrollDirection: .vertical)
        XCTAssertEqual(fitted.count, 3)
        XCTAssertEqual(fitted.groupExtent, 300)
        XCTAssertFalse(base.itemMainAxisSize(.fractionalGroup(1.0 / 3))
            .lineGrouping(.count(lines: 3, mainAxisSize: .fixed(300)))
            .environmentValidationErrors(in: environment).isEmpty)
    }

    func testLineSpacingAndGroupOverrideAreOrderIndependentAndResettable() throws {
        let base = GridLayout(tracks: [.init(.fixed(40), spacingAfter: 3), .init(.fixed(40))])
            .trackSpacing(10)
        let before = base.groupSpacing(20).lineSpacing(12)
        let after = base.lineSpacing(12).groupSpacing(20)
        XCTAssertEqual(before, after)
        XCTAssertEqual(before.lineSpacing, 12)
        XCTAssertEqual(before.groupSpacing, 20)
        XCTAssertEqual(try before.geometry(in: TestLayoutEnvironment(), scrollDirection: .vertical)
            .tracks[0].spacing, 3)
        XCTAssertEqual(before.groupSpacing(nil), base.lineSpacing(12))
        XCTAssertEqual(before.lineSpacing(8).lineSpacing(12), before)
        XCTAssertEqual(before.groupSpacing(0).groupSpacing(20), before)
        XCTAssertNil(base.groupSpacing)
        // Equal geometry today does not imply equal configuration: only nil follows later line changes.
        XCTAssertNotEqual(base.lineSpacing(12), base.lineSpacing(12).groupSpacing(12))
        XCTAssertEqual(Set([base.lineSpacing(12), base.lineSpacing(12).groupSpacing(12)]).count, 2)
    }

    func testUnifiedSpacingAndOverrideUpdatesRenderAcrossGroupsInAllDirections() throws {
        for outerHorizontal in [false, true] {
            for orthogonal in [false, true] {
                for lines in [1, 3] {
                    let fixture = LayoutFixture(width: 360, count: 8, horizontal: outerHorizontal)
                    defer { fixture.close() }
                    let horizontal = outerHorizontal != orthogonal
                    let base = GridLayout(tracks: 2).itemMainAxisSize(.fixed(40))
                        .gridCrossAxisSize(.fixed(220)).trackSpacing(10)
                        .lineGrouping(.count(lines: lines))
                        .orthogonalScrolling(orthogonal ? .continuous : nil)
                    // Reapply to the same adapter: changing or clearing the override must invalidate layout.
                    let cases: [(ListSectionGridLayout, CGFloat, CGFloat)] = [
                        (base.lineSpacing(12), 12, 12),
                        (base.lineSpacing(18), 18, 18),
                        (base.groupSpacing(24).lineSpacing(12), 12, 24),
                        (base.lineSpacing(12).groupSpacing(24), 12, 24),
                        (base.groupSpacing(0).lineSpacing(12), 12, 0),
                        (base.groupSpacing(24).groupSpacing(nil).lineSpacing(12), 12, 12),
                        (base.lineSpacing(12).groupSpacing(24).groupSpacing(nil).lineSpacing(18), 18, 18),
                        (base.groupSpacing(24).lineSpacing(18).groupSpacing(nil), 18, 18),
                        (base.lineSpacing(12).groupSpacing(0).lineSpacing(18), 18, 0),
                        (base.lineSpacing(12).groupSpacing(12).lineSpacing(18), 18, 12),
                        (base.lineSpacing(18).groupSpacing(nil).groupSpacing(24), 18, 24),
                    ]
                    for (grid, lineGap, groupGap) in cases {
                        fixture.apply(grid); fixture.render()
                        let first = try fixture.frame(0), track = try fixture.frame(1)
                        let lastLine = try fixture.frame((lines - 1) * 2)
                        let nextGroup = try fixture.frame(lines * 2)
                        XCTAssertEqual(horizontal ? track.minY - first.maxY : track.minX - first.maxX,
                                       10, accuracy: 0.5)
                        if lines > 1 {
                            let nextLine = try fixture.frame(2)
                            XCTAssertEqual(horizontal ? nextLine.minX - first.maxX : nextLine.minY - first.maxY,
                                           lineGap, accuracy: 0.5)
                        }
                        XCTAssertEqual(horizontal ? nextGroup.minX - lastLine.maxX : nextGroup.minY - lastLine.maxY,
                                       groupGap, accuracy: 0.5)
                        XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
                    }
                }
            }
        }
    }

    func testMutableSpacingPropertiesResolveCurrentValuesAndDiagnoseInvalidOverrides() {
        var grid = GridLayout(tracks: 2).itemMainAxisSize(.fixed(40))
        func resolvedGap(_ value: ListSectionGridLayout) -> CGFloat {
            ListSection(0) {} layout: { value }.resolvedForTesting().interGroupSpacing
        }
        grid.lineSpacing = 8
        XCTAssertEqual(resolvedGap(grid), 8)
        grid.groupSpacing = 20
        grid.lineSpacing = 12
        XCTAssertEqual(resolvedGap(grid), 20)
        grid.groupSpacing = 0
        XCTAssertEqual(resolvedGap(grid), 0)
        grid.groupSpacing = nil
        XCTAssertEqual(resolvedGap(grid), 12)
        for invalid in [CGFloat(-1), .nan, .infinity] {
            XCTAssertFalse(grid.groupSpacing(invalid).validationErrors.isEmpty)
            XCTAssertFalse(grid.lineSpacing(invalid).groupSpacing(20).validationErrors.isEmpty)
        }
        XCTAssertTrue(grid.groupSpacing(nil).validationErrors.isEmpty)
    }

    func testCrossAxisSizeFollowsDirectionAndCanResetWithScrolling() throws {
        let base = GridLayout(tracks: 2).itemMainAxisSize(.fixed(40)).trackSpacing(10).lineSpacing(10)
        let configured = base.gridCrossAxisSize(.fixed(220)).orthogonalScrolling(.continuous)
        for direction in [ListLayoutScrollDirection.vertical, .horizontal] {
            let geometry = try configured.geometry(in: TestLayoutEnvironment(), scrollDirection: direction)
            XCTAssertEqual(geometry.crossExtent, 220)
            XCTAssertEqual(geometry.axis, direction == .vertical ? .horizontal : .vertical)
        }
        XCTAssertEqual(configured.gridCrossAxisSize(nil).orthogonalScrolling(nil), base)
        XCTAssertEqual(configured.gridCrossAxisSize(.estimated(80)).gridCrossAxisSize(.fixed(220)), configured)
    }

    func testExplicitBackgroundPolicyRestoresDefaultsAfterCustomRules() {
        let base = ListSection(0) {} decorations: {
            SectionDecoration(UICollectionReusableView.self, kind: "card")
        }
        let grid = GridLayout(tracks: 1).decorationItems {
            DecorationItemLayout(kind: "card", backgroundInsets: .init(6), zIndex: 2)
        }
        XCTAssertTrue(base.layout { grid.decorationItems(.none) }.resolvedForTesting().decorationItems.isEmpty)
        let restored = base.layout { grid.decorationItems(.none).decorationItems(.registeredBackgrounds) }
            .resolvedForTesting().decorationItems
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].zIndex, -1)
        XCTAssertEqual(restored[0].contentInsets, .zero)
    }

    func testProviderBoundaryReferencesSupportArraysOptionalsAndConditions() {
        let reference = CustomLayoutBoundary(kind: "header").whenContentExists()
        let absent: CustomLayoutBoundary? = nil
        let grid: ListCustomLayout<Int> = CustomLayout(layoutKey: 0) { context in
            ListSectionLayout.gridConfiguration(GridLayout(tracks: 1)).makeCompositionalSection(
                environment: context.environment, itemSupplementaries: [])
        }.boundarySupplementaries {
            [reference]
            absent
            if false { CustomLayoutBoundary(kind: "footer") }
        }
        XCTAssertEqual(grid.options.boundaries.count, 1)
        XCTAssertEqual(grid.options.boundaries[0].kind, "header")
        XCTAssertNil(grid.options.boundaries[0].geometry)
        XCTAssertTrue(grid.options.boundaries[0].optional)
    }

    func testInvalidIndependentDimensionsAreDiagnosed() {
        let base = GridLayout(tracks: 2)
        for grid in [base.trackSpacing(-1), base.lineSpacing(.nan), base.groupSpacing(.infinity),
                     base.gridCrossAxisSize(.fixed(0)), base.lineGrouping(.count(lines: 2, mainAxisSize: .fixed(-1))),
                     base.lineGrouping(.fitting(mainAxisSize: .fixed(.nan)))] {
            XCTAssertFalse(grid.validationErrors.isEmpty)
        }
    }
}
