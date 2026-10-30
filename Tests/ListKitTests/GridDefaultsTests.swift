import UIKit
import XCTest
@testable import ListKit

@MainActor
final class GridDefaultsTests: XCTestCase {
    func testBothTrackFactoriesUseEstimatedItemsAndZeroSpacing() {
        for grid in [GridLayout(tracks: 1), GridLayout(tracks: 3),
                     GridLayout(tracks: [.init(.flexible()), .init(.adaptive(minimumForCount: 80))])] {
            XCTAssertEqual(grid.itemMainAxisSize, .estimated(44))
            XCTAssertEqual(grid.trackSpacing, 0)
            XCTAssertEqual(grid.lineSpacing, 0)
            XCTAssertNil(grid.groupSpacing)
        }
        XCTAssertEqual(ListSectionLayout.defaultLayout, .gridConfiguration(GridLayout(tracks: 1)))
        let single = GridLayout(tracks: 1).gridCrossAxisSize(.estimated(100))
        XCTAssertTrue(single.environmentValidationErrors(in: TestLayoutEnvironment()).isEmpty)
        XCTAssertFalse(single.itemMainAxisSize(.aspectRatio(1))
            .environmentValidationErrors(in: TestLayoutEnvironment()).isEmpty)
    }

    func testZeroSpacingKeepsTracksLinesAndGroupsAdjacentInAllDirections() throws {
        for outerHorizontal in [false, true] {
            for orthogonal in [false, true] {
                let horizontal = outerHorizontal != orthogonal
                let f = LayoutFixture(width: 360, count: 6, horizontal: outerHorizontal)
                defer { f.close() }
                f.apply(GridLayout(tracks: 2).itemMainAxisSize(.fixed(30))
                    .gridCrossAxisSize(.fixed(200)).lineGrouping(.count(lines: 2))
                    .orthogonalScrolling(orthogonal ? .continuous : nil))
                f.render()
                let first = try f.frame(0), track = try f.frame(1)
                let line = try f.frame(2), group = try f.frame(4)
                XCTAssertEqual(horizontal ? first.height : first.width, 100, accuracy: 0.5)
                XCTAssertEqual(horizontal ? track.minY - first.maxY : track.minX - first.maxX, 0, accuracy: 0.5)
                XCTAssertEqual(horizontal ? line.minX - first.maxX : line.minY - first.maxY, 0, accuracy: 0.5)
                XCTAssertEqual(horizontal ? group.minX - line.maxX : group.minY - line.maxY, 0, accuracy: 0.5)
                XCTAssertTrue(f.adapter.lastLayoutDiagnostics.isEmpty)
            }
        }
    }
}
