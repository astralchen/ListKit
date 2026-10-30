import UIKit
import XCTest
@testable import ListKit

@MainActor
final class LayoutAPIReviewTests: XCTestCase {
    func testSectionInsetsAndCrossAxisSizeUseSeparateDimensionsInAllDirections() throws {
        let insets = ListLayoutInsets(top: 11, leading: 13, bottom: 17, trailing: 19)
        for outerHorizontal in [false, true] {
            for orthogonal in [false, true] {
                for fixedCross in [false, true] {
                    let f = LayoutFixture(width: 360, count: 8, horizontal: outerHorizontal)
                    defer { f.close() }
                    let horizontal = outerHorizontal != orthogonal
                    let grid = GridLayout(tracks: 2).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0)
                        .sectionInsets(insets).gridCrossAxisSize(fixedCross ? .fixed(220) : nil)
                        .orthogonalScrolling(orthogonal ? .continuous : nil)
                    f.apply(grid); f.render()
                    let first = try f.frame(0), second = try f.frame(1)
                    let available = horizontal ? f.collection.bounds.height - 28 : f.collection.bounds.width - 32
                    let cross = fixedCross ? 220 : available
                    XCTAssertEqual(horizontal ? first.height : first.width, cross / 2, accuracy: 0.5)
                    XCTAssertEqual(horizontal ? second.maxY - first.minY : second.maxX - first.minX, cross, accuracy: 0.5)
                    XCTAssertEqual(first.minX, 13, accuracy: 0.5)
                    XCTAssertEqual(first.minY, 11, accuracy: 0.5)
                    XCTAssertTrue(f.adapter.lastLayoutDiagnostics.isEmpty)
                }
            }
        }
    }

    func testViewportFractionDeductsOnlySectionMainAxisInsets() throws {
        let env = TestLayoutEnvironment()
        for outer in [ListLayoutScrollDirection.vertical, .horizontal] {
            for orthogonal in [false, true] {
                let grid = GridLayout(tracks: 1).sectionInsets(.init(top: 11, leading: 13, bottom: 17, trailing: 19))
                    .gridCrossAxisSize(.fixed(220)).itemMainAxisSize(.fractionalViewport(0.5))
                    .orthogonalScrolling(orthogonal ? .continuous : nil)
                let geometry = try grid.geometry(in: env, scrollDirection: outer)
                let viewport = geometry.axis == .vertical ? env.container.effectiveContentSize.height - 28
                    : env.container.effectiveContentSize.width - 32
                XCTAssertEqual(geometry.mainExtents, [viewport * 0.5])
                XCTAssertEqual(geometry.crossExtent, 220)
            }
        }
    }

    func testBoundaryAspectRatioWithExplicitGridCrossSizeAndSectionInsets() throws {
        for horizontal in [false, true] {
            let f = LayoutFixture(width: 360, count: 4, horizontal: horizontal)
            defer { f.close() }
            f.adapter.apply(transaction: .disabled) {
                ListSection(0) {
                    for i in 0..<4 { Row(i, model: i, cell: UICollectionViewCell.self) { _, _, _ in } }
                } layout: {
                    GridLayout(tracks: 2).itemMainAxisSize(.fixed(40)).gridCrossAxisSize(.fixed(220))
                        .sectionInsets(.init(top: 11, leading: 13, bottom: 17, trailing: 19))
                        .boundarySupplementaries {
                            BoundarySupplementaryLayout(kind: "header", mainAxisSize: .aspectRatio(2),
                                sizingAxis: horizontal ? .horizontal : .vertical, alignment: horizontal ? .leading : .top)
                        }
                } supplementaries: {
                    SectionSupplementary(UICollectionReusableView.self, kind: "header", id: 0) { _, _ in }
                }
            }
            f.render()
            let header = try XCTUnwrap(f.collection.layoutAttributesForSupplementaryElement(
                ofKind: "header", at: IndexPath(item: 0, section: 0))).frame
            XCTAssertEqual(header.width / header.height, 2, accuracy: 0.01)
            XCTAssertEqual(horizontal ? header.height : header.width, horizontal ? 332 : 328, accuracy: 0.5)
        }
    }

    func testBadgeGroupsKeepIndependentSpacingAndTailDimensions() throws {
        for horizontal in [false, true] {
            let f = LayoutFixture(width: 360, count: 7, horizontal: horizontal)
            defer { f.close() }
            f.adapter.apply(transaction: .disabled) {
                ListSection(0) {
                    for i in 0..<7 { Row(i, model: i, cell: UICollectionViewCell.self) { _, _, _ in } }
                } layout: {
                    GridLayout(tracks: 2).gridCrossAxisSize(.fixed(220)).itemMainAxisSize(.fillGroup)
                        .trackSpacing(10).lineSpacing(12).groupSpacing(20)
                        .lineGrouping(.count(lines: 3, mainAxisSize: .fixed(300)))
                        .itemSupplementaries {
                            ItemSupplementaryLayout(kind: "badge", size: .init(width: .absolute(8), height: .absolute(8)), itemAnchor: .topTrailing)
                        }
                } supplementaries: {
                    SectionSupplementary(UICollectionReusableView.self, kind: "badge", id: 0) { _, _ in }
                }
            }
            f.render()
            let a = try f.frame(0), b = try f.frame(2), tail = try f.frame(6)
            XCTAssertEqual(horizontal ? a.width : a.height, 92, accuracy: 0.5)
            XCTAssertEqual(horizontal ? b.minX - a.maxX : b.minY - a.maxY, 12, accuracy: 0.5)
            XCTAssertEqual(horizontal ? tail.minX - a.minX : tail.minY - a.minY, 320, accuracy: 0.5)
            XCTAssertEqual(tail.size, a.size)
            for i in 0..<7 {
                XCTAssertNotNil(f.collection.layoutAttributesForSupplementaryElement(ofKind: "badge", at: IndexPath(item: i, section: 0)))
            }
        }
    }
}
