import UIKit
import XCTest
@testable import ListKit

@MainActor
final class UnifiedGridLayoutTests: XCTestCase {
    func testChangingNativeConfigurationUsesCurrentOuterDirection() throws {
        let f = LayoutFixture(width: 360, count: 6)
        defer { f.close() }
        f.apply(GridLayout(tracks: 2).itemMainAxisSize(.fixed(80)).trackSpacing(10).lineSpacing(10)); f.render()
        let layout = try XCTUnwrap(f.collection.collectionViewLayout as? UICollectionViewCompositionalLayout)
        XCTAssertEqual(try f.frame(0).height, 80, accuracy: 1)
        let configuration = layout.configuration
        configuration.scrollDirection = .horizontal
        layout.configuration = configuration
        f.render()
        XCTAssertEqual(try f.frame(0).width, 80, accuracy: 1)
        XCTAssertEqual(try f.frame(0).height, 695, accuracy: 1)
        XCTAssertEqual(try f.frame(1).minY - f.frame(0).minY, 705, accuracy: 1)
        XCTAssertTrue(layout === f.collection.collectionViewLayout)
    }

    func testMixedSectionsKeepIndependentAxesAndSelectionDuringSizeUpdate() throws {
        let f = LayoutFixture(width: 360, count: 6)
        defer { f.close() }
        func apply(_ height: CGFloat) {
            f.adapter.apply(transaction: .disabled) {
                for sectionID in 0..<3 {
                    ListSection(sectionID) {
                        for i in 0..<6 { Row(i, model: i, cell: UICollectionViewCell.self) { _, _, _ in } }
                    } layout: {
                        if sectionID == 1 {
                            GridLayout(tracks: 2).itemMainAxisSize(.fixed(80)).gridCrossAxisSize(.fixed(height))
                                .orthogonalScrolling(.continuous).trackSpacing(10).lineSpacing(10)
                        } else {
                            GridLayout(tracks: 2).itemMainAxisSize(.fixed(50)).trackSpacing(10).lineSpacing(10)
                        }
                    }.selectionMode(.single)
                }
            }
            f.render()
        }
        apply(110)
        func frame(_ item: Int, _ section: Int) throws -> CGRect {
            try XCTUnwrap(f.collection.layoutAttributesForItem(at: IndexPath(item: item, section: section)))
                .frame
        }
        XCTAssertEqual(try frame(0, 0).height, 50, accuracy: 1)
        XCTAssertEqual(try frame(0, 1).width, 80, accuracy: 1)
        XCTAssertEqual(try frame(0, 1).height, 50, accuracy: 1)
        XCTAssertEqual(try frame(0, 2).height, 50, accuracy: 1)
        f.collection.selectItem(at: IndexPath(item: 2, section: 1), animated: false, scrollPosition: [])
        XCTAssertEqual(f.collection.indexPathsForSelectedItems, [IndexPath(item: 2, section: 1)])
        apply(210)
        XCTAssertEqual(try frame(0, 1).height, 100, accuracy: 1)
        XCTAssertEqual(f.collection.indexPathsForSelectedItems, [IndexPath(item: 2, section: 1)])
    }

    func testDirectionMatrixAndItemDimensions() throws {
        for outer in [ListLayoutScrollDirection.vertical, .horizontal] {
            for orthogonal in [false, true] {
                let fixture = LayoutFixture(width: 360, count: 7, horizontal: outer == .horizontal)
                defer { fixture.close() }
                let vertical = orthogonal ? outer == .horizontal : outer == .vertical
                var grid = GridLayout(tracks: 2).itemMainAxisSize(.fixed(90)).trackSpacing(10).lineSpacing(10)
                if orthogonal {
                    grid = grid.orthogonalScrolling(.continuous)
                        .gridCrossAxisSize(.fixed(230))
                }
                fixture.apply(grid); fixture.render()
                XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
                let a = try fixture.frame(0), b = try fixture.frame(1), c = try fixture.frame(2)
                XCTAssertEqual(vertical ? a.height : a.width, 90, accuracy: 0.5)
                XCTAssertEqual(vertical ? a.width : a.height, orthogonal ? 110 : 175, accuracy: 0.5)
                XCTAssertEqual(vertical ? a.minY : a.minX, vertical ? b.minY : b.minX, accuracy: 0.5)
                XCTAssertEqual(vertical ? c.minY - a.minY : c.minX - a.minX, 100, accuracy: 0.5)
            }
        }
    }

    func testTwoByThreeGroupsTailAndIndependentSpacing() throws {
        for outer in [ListLayoutScrollDirection.vertical, .horizontal] {
            let fixture = LayoutFixture(width: 360, count: 7, horizontal: outer == .horizontal)
            defer { fixture.close() }
            let grid = GridLayout(tracks: 2).itemMainAxisSize(.fillGroup).trackSpacing(10).lineSpacing(10)
                .gridCrossAxisSize(.fixed(230))
                .orthogonalScrolling(.groupPaging)
                .lineGrouping(.count(lines: 3, mainAxisSize: .fixed(320))).groupSpacing(20)
            fixture.apply(grid); fixture.render()
            let vertical = outer == .horizontal
            let first = try fixture.frame(0), third = try fixture.frame(2), tail = try fixture.frame(6)
            XCTAssertEqual(vertical ? first.height : first.width, 100, accuracy: 0.5)
            XCTAssertEqual(vertical ? third.minY - first.minY : third.minX - first.minX, 110, accuracy: 0.5)
            XCTAssertEqual(vertical ? tail.minY - first.minY : tail.minX - first.minX, 340, accuracy: 0.5)
            XCTAssertEqual(first.size, tail.size)
        }
    }

    func testFitRetainsFullViewportGroupWithInsets() throws {
        let f = LayoutFixture(width: 390, count: 8)
        defer { f.close() }
        f.apply(
            GridLayout(tracks: 1).itemMainAxisSize(.fixed(92)).gridCrossAxisSize(.fixed(112))
                .trackSpacing(10).lineSpacing(10).sectionInsets(.init(leading: 14, trailing: 14))
                .lineGrouping(.fitting(mainAxisSize: .fractionalViewport(1)))
                .orthogonalScrolling(.continuousGroupLeadingBoundary))
        f.render()
        let first = try f.frame(0), second = try f.frame(1), next = try f.frame(3)
        XCTAssertEqual(first.size, CGSize(width: 92, height: 112))
        XCTAssertEqual(second.minX - first.minX, 102, accuracy: 0.5)
        XCTAssertEqual(next.minX - first.minX, 372, accuracy: 0.5)
    }

    func testAlignmentBothAxesAndRTL() throws {
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for alignment in [ListGridTrackGroupAlignment.start, .center, .end] {
                    let f = LayoutFixture(width: 360, count: 4, rtl: rtl, horizontal: horizontal)
                    defer { f.close() }
                    f.apply(
                        GridLayout(tracks: [.init(.fixed(70)), .init(.fixed(90))])
                            .itemMainAxisSize(.fixed(50)).trackSpacing(10).lineSpacing(10).trackGroupAlignment(alignment))
                    f.render()
                    let frames = try (0..<2).map { index in
                        let cell = try XCTUnwrap(
                            f.collection.cellForItem(at: IndexPath(item: index, section: 0)))
                        return cell.convert(cell.bounds, to: f.window)
                    }
                    let a = frames[0], b = frames[1]
                    let leading = horizontal ? min(a.minY, b.minY) : min(a.minX, b.minX)
                    let fraction = !horizontal && rtl ? 1 - alignment.fraction : alignment.fraction
                    XCTAssertEqual(leading, 190 * fraction, accuracy: 0.5)
                }
            }
        }
    }

    func testRelativeDimensionsAndContentGroup() throws {
        let f = LayoutFixture(width: 360, count: 4)
        defer { f.close() }
        f.apply(
            GridLayout(tracks: 1).itemMainAxisSize(.fractionalViewport(0.5))
                .gridCrossAxisSize(.fixed(80)).orthogonalScrolling(.continuous).trackSpacing(10).lineSpacing(10))
        f.render()
        XCTAssertEqual(try f.frame(0).width, 180, accuracy: 0.5)
        f.apply(
            GridLayout(tracks: 1).itemMainAxisSize(.fractionalGroup(0.4))
                .gridCrossAxisSize(.fixed(80)).orthogonalScrolling(.continuous)
                .lineGrouping(.count(lines: 2, mainAxisSize: .fixed(300))).trackSpacing(10).lineSpacing(10).groupSpacing(20))
        f.render()
        XCTAssertEqual(try f.frame(0).width, 120, accuracy: 0.5)
        XCTAssertEqual(try f.frame(2).minX - f.frame(0).minX, 320, accuracy: 0.5)
        f.apply(GridLayout(tracks: 1).itemMainAxisSize(.fixed(70)).lineGrouping(.count(lines: 2)).trackSpacing(10).lineSpacing(10).groupSpacing(20))
        f.render()
        XCTAssertEqual(try f.frame(2).minY - f.frame(0).minY, 170, accuracy: 0.5)
    }

    func testInvalidConstraintsDiagnoseBeforeUIKit() {
        let env = TestLayoutEnvironment()
        let invalid: [ListSectionGridLayout] = [
            GridLayout(tracks: 1).itemMainAxisSize(.fillGroup),
            GridLayout(tracks: 1).itemMainAxisSize(.fractionalGroup(1)),
            GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).lineGrouping(.count(lines: 3, mainAxisSize: .fixed(200))),
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).lineGrouping(.fitting(mainAxisSize: .fixed(300))),
            GridLayout(tracks: 1).gridCrossAxisSize(.fixed(0)),
            GridLayout(tracks: 2).gridCrossAxisSize(.estimated(100)),
            GridLayout(tracks: 1).gridCrossAxisSize(.fixed(.nan)),
            GridLayout(tracks: 1).groupSpacing(-1),
            GridLayout(tracks: 1).lineGrouping(.count(lines: 0)),
            GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).lineGrouping(.fitting(mainAxisSize: .fixed(10))),
        ]
        for grid in invalid { XCTAssertFalse(grid.environmentValidationErrors(in: env).isEmpty, "\(grid)") }
    }

    func testValueSemanticsModifierOrderAndFrameReplacement() {
        let base = GridLayout(tracks: 2)
        XCTAssertEqual(base.crossAlignment, .start)
        let a = base.gridCrossAxisSize(.fixed(200)).orthogonalScrolling(.groupPaging)
            .lineGrouping(.count(lines: 3, mainAxisSize: .fixed(300))).itemMainAxisSize(.fillGroup).trackGroupAlignment(.end)
        let b = base.trackGroupAlignment(.end).itemMainAxisSize(.fillGroup).lineGrouping(.count(lines: 3, mainAxisSize: .fixed(300)))
            .orthogonalScrolling(.groupPaging).gridCrossAxisSize(.fixed(200))
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
        XCTAssertNotEqual(base, a)
        XCTAssertEqual(base.gridCrossAxisSize(.fixed(100)).gridCrossAxisSize(.fixed(200)), base.gridCrossAxisSize(.fixed(200)))
        XCTAssertEqual(base.trackSpacing(2).lineSpacing(2).trackSpacing(9).lineSpacing(9), base.trackSpacing(9).lineSpacing(9))
        XCTAssertEqual(base.gridCrossAxisSize(.estimated(100)).gridCrossAxisSize(.fixed(200)), base.gridCrossAxisSize(.fixed(200)))
        XCTAssertNotEqual(a, a.groupSpacing(99))
    }

    func testAdaptiveGroupCountsResolvedTracks() throws {
        let grid = GridLayout(tracks: [.init(.adaptive(minimumForCount: 100))]).trackSpacing(10).lineSpacing(10)
            .itemMainAxisSize(.fixed(50)).lineGrouping(.count(lines: 3))
        let geometry = try grid.geometry(in: TestLayoutEnvironment(), scrollDirection: .vertical)
        XCTAssertEqual(geometry.tracks.count, 3)
        XCTAssertEqual(geometry.count, 3)
        XCTAssertEqual(geometry.groupExtent, 170)
    }

    func testFrameGroupAndAxisChangesInvalidateExistingLayout() throws {
        let f = LayoutFixture(width: 360, count: 8)
        defer { f.close() }
        let grid = GridLayout(tracks: 1).itemMainAxisSize(.fixed(80)).gridCrossAxisSize(.fixed(100))
            .orthogonalScrolling(.continuous)
        f.apply(grid); f.render()
        let layout = f.collection.collectionViewLayout
        f.apply(grid.gridCrossAxisSize(.fixed(150)).lineGrouping(.count(lines: 2)).groupSpacing(30)); f.render()
        XCTAssertTrue(layout === f.collection.collectionViewLayout)
        XCTAssertEqual(try f.frame(0).height, 150, accuracy: 0.5)
        XCTAssertEqual(try f.frame(2).minX - f.frame(0).minX, 190, accuracy: 0.5)
    }
    func testEstimatedCrossFrameMeasuresActualCellInBothDirections() throws {
        for outerHorizontal in [false, true] {
            let f = LayoutFixture(width: 360, count: 1, horizontal: outerHorizontal)
            defer { f.close() }
            f.adapter.apply(
                [
                    ListSection(0) {
                        Row(0, model: outerHorizontal, cell: CrossSizingCell.self) { cell, horizontal, _ in
                            cell.horizontal = horizontal
                        }
                    } layout: {
                        GridLayout(tracks: 1).itemMainAxisSize(.fixed(90))
                            .gridCrossAxisSize(.estimated(40))
                            .orthogonalScrolling(.continuous)
                    }
                ], transaction: .disabled)
            f.render()
            let cell = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: 0, section: 0)))
            XCTAssertEqual(outerHorizontal ? cell.frame.width : cell.frame.height, 120, accuracy: 1)
            XCTAssertEqual(outerHorizontal ? cell.frame.height : cell.frame.width, 90, accuracy: 1)
        }
    }

    func testPagedGridRetainsItemBadges() throws {
        let f = LayoutFixture(width: 360, count: 7)
        defer { f.close() }
        f.adapter.apply(
            [
                ListSection(0) {
                    for i in 0..<7 { Row(i, model: i, cell: UICollectionViewCell.self) { _, _, _ in } }
                } layout: {
                    GridLayout(tracks: 2).itemMainAxisSize(.fillGroup).gridCrossAxisSize(.fixed(220)).trackSpacing(10).lineSpacing(10)
                        .lineGrouping(.count(lines: 3, mainAxisSize: .fixed(320))).orthogonalScrolling(.groupPaging)
                        .itemSupplementaries {
                            ItemSupplementaryLayout(
                                kind: "badge", size: .init(width: .absolute(12), height: .absolute(12)),
                                itemAnchor: .topTrailing)
                        }
                } supplementaries: {
                    SectionSupplementary(UICollectionReusableView.self, kind: "badge", id: 0) { _, _ in }
                }
            ], transaction: .disabled)
        f.render()
        XCTAssertTrue(f.adapter.lastLayoutDiagnostics.isEmpty)
        for i in 0..<6 {
            let attributes = try XCTUnwrap(
                f.collection.collectionViewLayout.layoutAttributesForSupplementaryView(
                    ofKind: "badge", at: IndexPath(item: i, section: 0)))
            let cell = try f.frame(i)
            XCTAssertEqual(attributes.frame.maxX, cell.maxX, accuracy: 1)
            XCTAssertEqual(attributes.frame.minY, cell.minY, accuracy: 1)
        }
    }

    func testExplicitGroupDoesNotRepeatContentToFillSlack() throws {
        let f = LayoutFixture(width: 360, count: 3)
        defer { f.close() }
        f.apply(
            GridLayout(tracks: 1).itemMainAxisSize(.fixed(30)).trackSpacing(10).lineSpacing(10).groupSpacing(20)
                .lineGrouping(.count(lines: 1, mainAxisSize: .fixed(300))).gridCrossAxisSize(.fixed(100)).orthogonalScrolling(.continuous))
        f.render()
        XCTAssertEqual(try f.frame(1).minX - f.frame(0).minX, 320, accuracy: 1)
    }

}

@MainActor
private final class CrossSizingCell: UICollectionViewCell {
    var horizontal = false
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
        -> UICollectionViewLayoutAttributes
    {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        if horizontal { result.size.width = 120 } else { result.size.height = 120 }
        return result
    }
}
