import UIKit
import XCTest

@testable import ListKit

@MainActor
final class GridReviewRegressionTests: XCTestCase {
    func testFixedFrameReservesFullRegionWhenTracksDoNotFillIt() throws {
        for horizontal in [false, true] {
            for alignment in [ListGridTrackGroupAlignment.start, .center, .end] {
                for paged in [false, true] {
                    let f = LayoutFixture(width: 360, count: 8, horizontal: horizontal)
                    defer { f.close() }
                    let grid = GridLayout(tracks: [.init(.fixed(80))]).itemMainAxisSize(.fixed(90))
                        .gridCrossAxisSize(.fixed(220))
                        .trackGroupAlignment(alignment).trackSpacing(10).lineSpacing(10).orthogonalScrolling(.continuous)
                        .lineGrouping(paged ? .count(lines: 2, mainAxisSize: .fixed(320)) : .count(lines: 1))
                    f.adapter.apply(transaction: .disabled) {
                        ListSection(0) {
                            for i in 0..<8 {
                                Row(i, model: i, cell: UICollectionViewCell.self) { _, _, _ in }
                            }
                        } layout: {
                            grid
                        }
                        ListSection(1) {
                            Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
                        } layout: {
                            GridLayout(tracks: 1).itemMainAxisSize(.fixed(40))
                        }
                    }
                    f.render()
                    let first = try f.frame(0)
                    let following = try XCTUnwrap(
                        f.collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 1))
                    ).frame
                    XCTAssertEqual(
                        horizontal ? following.minX : following.minY, 220, accuracy: 0.5,
                        "frame must reserve full region: \(horizontal), \(alignment), \(paged)")
                    XCTAssertEqual(horizontal ? first.width : first.height, 80, accuracy: 0.5)
                    XCTAssertEqual(
                        horizontal ? first.minX : first.minY, 140 * alignment.fraction, accuracy: 0.5)
                }
            }
        }
    }

    func testEstimatedCrossSizeCannotBeUsedAsFinalAspectRatioInput() {
        for horizontal in [false, true] {
            let grid = GridLayout(tracks: 1).itemMainAxisSize(.aspectRatio(1))
                .gridCrossAxisSize(.estimated(80))
                .orthogonalScrolling(.continuous)
            XCTAssertFalse(
                grid.environmentValidationErrors(
                    in: TestLayoutEnvironment(),
                    scrollDirection: horizontal ? .horizontal : .vertical
                ).isEmpty)
        }
    }

    func testPagedMeasuredItemsKeepTheirPerUnitSizesWithoutBadges() throws {
        for horizontal in [false, true] {
            for uniform in [false, true] {
                let f = LayoutFixture(width: 360, count: 8, horizontal: horizontal)
                defer { f.close() }
                let extents: [CGFloat] = [40, 100, 60, 70, 110, 90, 50, 80]
                var size = ListGridItemMainAxisSize.estimated(44)
                if uniform {
                    guard #available(iOS 17.0, *) else { continue }
                    size = .uniform(estimated: 44)
                }
                f.adapter.apply(transaction: .disabled) {
                    ListSection(0) {
                        for i in extents.indices {
                            Row(i, model: extents[i], cell: ReviewSizingCell.self) { cell, extent, _ in
                                cell.horizontal = horizontal
                                cell.extent = extent
                            }
                        }
                    } layout: {
                        GridLayout(tracks: 2).itemMainAxisSize(size).lineGrouping(.count(lines: 3)).trackSpacing(10).lineSpacing(10).groupSpacing(20)
                    }
                }
                f.render()
                let expected: [CGFloat] = uniform ? [100, 100, 70, 70, 110, 110, 80, 80] : extents
                for i in extents.indices {
                    let frame = try f.frame(i)
                    XCTAssertEqual(horizontal ? frame.width : frame.height, expected[i], accuracy: 1)
                }
                let second = try f.frame(2)
                let third = try f.frame(4)
                let nextPage = try f.frame(6)
                XCTAssertEqual(horizontal ? second.minX : second.minY, 110, accuracy: 1)
                XCTAssertEqual(horizontal ? third.minX : third.minY, 190, accuracy: 1)
                XCTAssertEqual(horizontal ? nextPage.minX : nextPage.minY, 320, accuracy: 1)
            }
        }
    }

    func testMeasuredMultiUnitBadgesAreAcceptedBeforeUIKitConstruction() throws {
        for horizontal in [false, true] {
            for uniform in [false, true] {
                let f = LayoutFixture(width: 360, count: 8, horizontal: horizontal)
                defer { f.close() }
                var size = ListGridItemMainAxisSize.estimated(44)
                if uniform {
                    guard #available(iOS 17.0, *) else { continue }
                    size = .uniform(estimated: 44)
                }
                let grid = GridLayout(tracks: 2).itemMainAxisSize(size).lineGrouping(.count(lines: 3))
                    .itemSupplementaries {
                        ItemSupplementaryLayout(
                            kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)),
                            itemAnchor: .topTrailing)
                    }
                f.adapter.apply(transaction: .disabled) {
                    ListSection(0) {
                        Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
                    } layout: {
                        grid
                    } supplementaries: {
                        SectionSupplementary(UICollectionReusableView.self, kind: "badge", id: 0) { _, _ in }
                    }
                }
                XCTAssertNotNil(
                    f.adapter.makeCompositionalSection(
                        for: 0, environment: TestLayoutEnvironment(),
                        scrollDirection: horizontal ? .horizontal : .vertical))
                XCTAssertTrue(
                    f.adapter.lastLayoutDiagnostics.isEmpty
                )
            }
        }
    }

    func testFixedFrameRejectsOverflowingTracks() {
        let grid = GridLayout(tracks: [.init(.fixed(100)), .init(.fixed(100))])
            .gridCrossAxisSize(.fixed(150)).trackSpacing(10).lineSpacing(10)
        XCTAssertTrue(
            grid.environmentValidationErrors(in: TestLayoutEnvironment()).contains {
                $0.contains("overflow fixed gridCrossAxisSize")
            })
    }

    func testFixedHorizontalMigrationMatchesLegacyUIKitGeometry() throws {
        for width in [CGFloat(150), 240, 390, 600] {
            let f = LayoutFixture(width: width, count: 12)
            defer { f.close() }
            let migrated = GridLayout(tracks: 1).itemMainAxisSize(.fixed(92)).gridCrossAxisSize(.fixed(112)).trackSpacing(10).lineSpacing(10)
                .sectionInsets(.init(top: 8, leading: 14, bottom: 12, trailing: 14))
                .lineGrouping(.fitting(mainAxisSize: .fixed(width))).orthogonalScrolling(.continuousGroupLeadingBoundary)
            f.apply(migrated)
            f.render()
            let newFrames = try (0..<12).map { try f.frame($0) }
            f.collection.collectionViewLayout = UICollectionViewCompositionalLayout { _, _ in
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(widthDimension: .absolute(92), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(112)),
                    subitems: [item])
                group.interItemSpacing = .fixed(10)
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 10
                section.contentInsets = .init(top: 8, leading: 14, bottom: 12, trailing: 14)
                section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
                return section
            }
            f.render()
            for i in 0..<12 {
                let legacy = try f.frame(i)
                XCTAssertEqual(newFrames[i].minX, legacy.minX, accuracy: 0.5)
                XCTAssertEqual(newFrames[i].minY, legacy.minY, accuracy: 0.5)
                XCTAssertEqual(newFrames[i].width, legacy.width, accuracy: 0.5)
                XCTAssertEqual(newFrames[i].height, legacy.height, accuracy: 0.5)
            }
        }
    }
}

@MainActor
private final class ReviewSizingCell: UICollectionViewCell {
    var horizontal = false
    var extent: CGFloat = 44
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
        -> UICollectionViewLayoutAttributes
    {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        if horizontal { result.size.width = extent } else { result.size.height = extent }
        return result
    }
}
