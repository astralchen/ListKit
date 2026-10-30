import UIKit
import XCTest

@testable import ListKit

/// 先用不同的真实 kind 验证 UIKit 的测量、indexPath 与 group 边界，不依赖 adapter 映射。
@MainActor
final class MeasuredBadgePrototypeTests: XCTestCase {
    func testExplicitMeasuredLinesWithDistinctBadgeKinds() throws {
        for horizontal in [false, true] {
            for orthogonal in [false, true] {
                for uniform in [false, true] {
                    if uniform { guard #available(iOS 17.0, *) else { continue } }
                    let f = LayoutFixture(width: 360, count: 8, horizontal: horizontal)
                    defer { f.close() }
                    let vertical = horizontal == orthogonal
                    let extents: [CGFloat] = [40, 100, 60, 70, 110, 90, 50, 80]
                    f.adapter.apply(transaction: .disabled) {
                        ListSection(0) {
                            for i in extents.indices {
                                Row(i, model: extents[i], cell: MeasuredBadgeCell.self) { cell, extent, _ in
                                    cell.vertical = vertical
                                    cell.extent = extent
                                }
                            }
                        } layout: {
                            CustomLayout(layoutKey: "prototype") { _ in
                                @MainActor func size(
                                    _ main: NSCollectionLayoutDimension, _ cross: NSCollectionLayoutDimension
                                ) -> NSCollectionLayoutSize {
                                    .init(
                                        widthDimension: vertical ? cross : main,
                                        heightDimension: vertical ? main : cross)
                                }
                                let units = (0..<3).map { line in
                                    let badge = NSCollectionLayoutSupplementaryItem(
                                        layoutSize: .init(
                                            widthDimension: .absolute(10), heightDimension: .absolute(10)),
                                        elementKind: "badge-\(line)",
                                        containerAnchor: .init(edges: [.top, .trailing]))
                                    var main = NSCollectionLayoutDimension.estimated(44)
                                    if #available(iOS 17.0, *), uniform {
                                        main = .uniformAcrossSiblings(estimate: 44)
                                    }
                                    let item = NSCollectionLayoutItem(
                                        layoutSize: size(main, .absolute(100)), supplementaryItems: [badge])
                                    let unit =
                                        vertical
                                        ? NSCollectionLayoutGroup.horizontal(
                                            layoutSize: size(.estimated(44), .absolute(210)), subitem: item,
                                            count: 2)
                                        : NSCollectionLayoutGroup.vertical(
                                            layoutSize: size(.estimated(44), .absolute(210)), subitem: item,
                                            count: 2)
                                    unit.interItemSpacing = .fixed(10)
                                    return unit
                                }
                                let group =
                                    vertical
                                    ? NSCollectionLayoutGroup.vertical(
                                        layoutSize: size(.estimated(152), .absolute(210)), subitems: units)
                                    : NSCollectionLayoutGroup.horizontal(
                                        layoutSize: size(.estimated(152), .absolute(210)), subitems: units)
                                group.interItemSpacing = .fixed(10)
                                let section = NSCollectionLayoutSection(group: group)
                                section.interGroupSpacing = 20
                                section.orthogonalScrollingBehavior = orthogonal ? .groupPaging : .none
                                return section
                            }
                        } supplementaries: {
                            for line in 0..<3 {
                                SectionSupplementary(
                                    UICollectionReusableView.self, kind: "badge-\(line)", id: line
                                ) { _, _ in }
                            }
                        }
                    }
                    f.render()
                    let expected: [CGFloat] = uniform ? [100, 100, 70, 70, 110, 110, 80, 80] : extents
                    for i in extents.indices {
                        let frame = try f.frame(i)
                        XCTAssertEqual(vertical ? frame.height : frame.width, expected[i], accuracy: 1)
                        let badge = try XCTUnwrap(
                            f.collection.layoutAttributesForSupplementaryElement(
                                ofKind: "badge-\((i / 2) % 3)",
                                at: IndexPath(item: (i / 6) * 2 + i % 2, section: 0)))
                        XCTAssertEqual(badge.frame.maxX, frame.maxX, accuracy: 1)
                        XCTAssertEqual(badge.frame.minY, frame.minY, accuracy: 1)
                    }
                    for (item, start) in [(2, CGFloat(110)), (4, 190), (6, 320)] {
                        let frame = try f.frame(item)
                        XCTAssertEqual(vertical ? frame.minY : frame.minX, start, accuracy: 1)
                    }
                }
            }
        }
    }
}

@MainActor
final class MeasuredBadgeCell: UICollectionViewCell {
    var vertical = true
    var extent: CGFloat = 44
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
        -> UICollectionViewLayoutAttributes
    {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        if vertical { result.size.height = extent } else { result.size.width = extent }
        return result
    }
}
