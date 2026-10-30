import UIKit
import XCTest
@testable import ListKit

@MainActor
final class LayoutObjectNamingTests: XCTestCase {
    func testGridRegionTrackGroupAlignmentAndLineGroupingHaveSeparateScopes() throws {
        for outerHorizontal in [false, true] {
            for orthogonal in [false, true] {
                let horizontal = outerHorizontal != orthogonal
                let f = LayoutFixture(width: 360, count: 6, horizontal: outerHorizontal)
                defer { f.close() }
                let grid = GridLayout(tracks: [
                    ListGridTrack(.fixed(40), spacingAfter: 6),
                    ListGridTrack(.fixed(50), spacingAfter: 100)
                ])
                    .gridCrossAxisSize(.fixed(200))
                    .trackGroupAlignment(.center)
                    .trackSpacing(10).lineSpacing(10).lineSpacing(8).groupSpacing(12)
                    .lineGrouping(.count(lines: 2))
                    .itemMainAxisSize(.fixed(30))
                    .sectionInsets(.init(top: 11, leading: 13, bottom: 17, trailing: 19))
                    .orthogonalScrolling(orthogonal ? .continuous : nil)
                f.apply(grid); f.render()
                let first = try f.frame(0), second = try f.frame(1)
                let nextLine = try f.frame(2), nextGroup = try f.frame(4)
                // The two tracks span 96 points; the final spacingAfter adds no outer padding.
                XCTAssertEqual(horizontal ? second.maxY - first.minY : second.maxX - first.minX, 96, accuracy: 0.5)
                // Center the entire track group in 200 points, then apply the Section inset.
                XCTAssertEqual(horizontal ? first.minY : first.minX, 52 + (horizontal ? 11 : 13), accuracy: 0.5)
                XCTAssertEqual(horizontal ? nextLine.minX - first.maxX : nextLine.minY - first.maxY, 8, accuracy: 0.5)
                XCTAssertEqual(horizontal ? nextGroup.minX - first.minX : nextGroup.minY - first.minY, 80, accuracy: 0.5)
                XCTAssertTrue(f.adapter.lastLayoutDiagnostics.isEmpty)
            }
        }
    }
}
