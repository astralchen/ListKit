import UIKit
import XCTest
@testable import ListKit

@MainActor
final class GridDynamicTypeTests: XCTestCase {
    func testDefaultEstimatedGridRespondsToPreferredContentSizeCategory() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Trait override fixture requires iOS 17") }
        for badges in [false, true] {
        for tracks in [1, 2] {
            let f = LayoutFixture(width: 360, count: 4)
            defer { f.close() }
            f.collection.traitOverrides.preferredContentSizeCategory = .large
            f.adapter.apply([ListSection(0) {
                for i in 0..<4 {
                    Row(i, model: "Layout text", cell: DynamicGridCell.self) { cell, text, _ in
                        cell.label.text = text
                    }
                }
            } layout: {
                GridLayout(tracks: tracks).lineGrouping(.count(lines: 2)).trackSpacing(10).lineSpacing(10)
                    .itemSupplementaries {
                        if badges {
                            ItemSupplementaryLayout(kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)), itemAnchor: .topTrailing)
                        }
                    }
            } supplementaries: {
                if badges {
                    SectionSupplementary(UICollectionReusableView.self, kind: "badge", id: 0) { _, _ in }
                }
            }], transaction: .disabled)
            f.render()
            let old = try f.frame(0)
            f.collection.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            f.render()
            let new = try f.frame(0)
            XCTAssertGreaterThan(new.height, old.height)
            XCTAssertEqual(new.width, old.width, accuracy: 1)
            let cell = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: 0, section: 0)))
            XCTAssertEqual(cell.frame.height, new.height, accuracy: 1)
            XCTAssertGreaterThanOrEqual(try f.frame(tracks).minY, new.maxY + 9)
            if badges {
                for i in 0..<4 {
                    let address = try XCTUnwrap(f.adapter.supplementaryElement(ofKind: "badge", at: IndexPath(item: i, section: 0)))
                    let badge = try XCTUnwrap(f.collection.layoutAttributesForSupplementaryElement(ofKind: address.elementKind, at: address.indexPath))
                    XCTAssertEqual(badge.frame.minY, try f.frame(i).minY, accuracy: 1)
                }
            }
        }
        }
    }
}

@MainActor
private final class DynamicGridCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        label.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
    }
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let value = attributes.copy() as! UICollectionViewLayoutAttributes
        value.size.height = ceil(contentView.systemLayoutSizeFitting(
            CGSize(width: attributes.size.width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
        return value
    }
}
