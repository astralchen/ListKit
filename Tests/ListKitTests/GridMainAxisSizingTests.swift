// Adapted from UIKitGridLayouts 89aa339cc5651147c3c6265c0c931dd701bb45a7.
// Copyright (c) 2026 Sondra. MIT: ThirdPartyNotices/UIKitGridLayouts-LICENSE.txt.
import UIKit
import XCTest

@testable import ListKit

/// 在 UIWindow 中触发真实 Auto Layout fitting，验证共用 Grid 生成器在两个主轴上的测量。
@MainActor
final class MainAxisSizingTests: XCTestCase {
    func testDefaultEstimatedCellsMeasureAndReloadInBothDirections() throws {
        for horizontal in [false, true] {
            for insetContent in [false, true] {
                try checkEstimated(horizontal: horizontal, insetContent: insetContent, size: nil)
            }
        }
    }

    func testVerticalEstimatedCellsAndReload() throws {
        try checkEstimated(horizontal: false, insetContent: false)
    }
    func testHorizontalEstimatedCellsAndReload() throws {
        try checkEstimated(horizontal: true, insetContent: false)
    }
    func testVerticalEstimatedWithInsetsAndReload() throws {
        try checkEstimated(horizontal: false, insetContent: true)
    }
    func testHorizontalEstimatedWithInsetsAndReload() throws {
        try checkEstimated(horizontal: true, insetContent: true)
    }

    private func checkEstimated(horizontal: Bool, insetContent: Bool, size: ListGridItemMainAxisSize? = .estimated(56)) throws {
        let f = SizingFixture(horizontal: horizontal, size: size, insetContent: insetContent)
        defer { f.close() }
        XCTAssertEqual(f.main(try f.frame(0)), 40, accuracy: 1)
        XCTAssertEqual(f.main(try f.frame(1)), 110, accuracy: 1)
        XCTAssertEqual(f.cross(try f.frame(0)), 100, accuracy: 1)
        XCTAssertEqual(f.cross(try f.frame(1)), 140, accuracy: 1)
        let next = try f.frame(2)
        XCTAssertGreaterThanOrEqual(f.start(next), f.end(try f.frame(1)) + 9)
        f.source.extents[0] = 170
        f.reload()
        XCTAssertEqual(f.main(try f.frame(0)), 170, accuracy: 1)
        XCTAssertGreaterThanOrEqual(f.start(try f.frame(2)), f.end(try f.frame(0)) + 9)
        f.source.extents = [30, 35, 45, 50]
        f.reload()
        XCTAssertEqual(f.main(try f.frame(0)), 30, accuracy: 1)
        XCTAssertEqual(f.main(try f.frame(1)), 35, accuracy: 1)
        XCTAssertLessThan(f.start(try f.frame(2)), f.start(next))
    }

    func testVerticalUniformCellsAndReload() throws {
        try checkUniform(horizontal: false, insetContent: false)
    }
    func testHorizontalUniformCellsAndReload() throws {
        try checkUniform(horizontal: true, insetContent: false)
    }
    func testVerticalUniformWithInsetsAndReload() throws {
        try checkUniform(horizontal: false, insetContent: true)
    }
    func testHorizontalUniformWithInsetsAndReload() throws {
        try checkUniform(horizontal: true, insetContent: true)
    }

    private func checkUniform(horizontal: Bool, insetContent: Bool) throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Uniform requires iOS 17") }
        let f = SizingFixture(horizontal: horizontal, size: .uniform(estimated: 56), insetContent: insetContent)
        defer { f.close() }
        // 最后一个不满组，不能继承上一组尺寸或跨 section 取最大值。
        f.source.extents = [40, 110, 60, 80, 50]
        f.reload()
        func check(_ expected: [CGFloat]) throws {
            for (index, value) in expected.enumerated() {
                XCTAssertEqual(f.main(try f.frame(index)), value, accuracy: 1)
                XCTAssertEqual(
                    f.cross(try f.frame(index)), index.isMultiple(of: 2) ? 100 : 140, accuracy: 1)
            }
            for index in [2, 4] {
                XCTAssertEqual(f.start(try f.frame(index)), f.end(try f.frame(index - 1)) + 10, accuracy: 1)
            }
        }
        try check([110, 110, 80, 80, 50])
        f.source.extents[0] = 170
        f.reload()
        try check([170, 170, 80, 80, 50])
        f.source.extents = [30, 35, 45, 50, 25]
        f.reload()
        try check([35, 35, 50, 50, 25])
    }

    func testAdaptiveUniformRecomputesGroupMembershipOnResize() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Uniform requires iOS 17") }
        for horizontal in [false, true] {
            let f = SizingFixture(horizontal: horizontal, size: .uniform(estimated: 56), adaptive: true)
            defer { f.close() }
            // 360 pt 容纳三条轨道；缩到 270 pt 后变为两条，第二组重新取最大值。
            for index in 0..<3 { XCTAssertEqual(f.main(try f.frame(index)), 110, accuracy: 1) }
            XCTAssertEqual(f.main(try f.frame(3)), 80, accuracy: 1)
            f.collection.frame.size =
            horizontal ? CGSize(width: 1200, height: 270) : CGSize(width: 270, height: 1200)
            f.collection.collectionViewLayout.invalidateLayout()
            f.settle()
            for (index, value) in [CGFloat(110), 110, 80, 80].enumerated() {
                XCTAssertEqual(f.main(try f.frame(index)), value, accuracy: 1)
            }
        }
    }

    func testUniformItemsAndEstimatedBoundariesMeasureIndependently() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Uniform requires iOS 17") }
        for horizontal in [false, true] {
            let f = SizingFixture(
                horizontal: horizontal, size: .uniform(estimated: 56), boundary: .estimated(20))
            defer { f.close() }
            XCTAssertEqual(
                f.main(try f.boundary(UICollectionView.elementKindSectionHeader)), 75, accuracy: 1)
            XCTAssertEqual(
                f.main(try f.boundary(UICollectionView.elementKindSectionFooter)), 65, accuracy: 1)
        }
    }

    func testFixedIgnoresContentInBothAxes() throws {
        for horizontal in [false, true] {
            let f = SizingFixture(horizontal: horizontal, size: .fixed(56))
            defer { f.close() }
            for i in 0..<4 { XCTAssertEqual(f.main(try f.frame(i)), 56, accuracy: 0.5) }
        }
    }

    func testRatioUsesEachTrackAndLargestGroupWithAndWithoutInsets() throws {
        for horizontal in [false, true] {
            for insetContent in [false, true] {
                let f = SizingFixture(horizontal: horizontal, size: .aspectRatio(2), insetContent: insetContent)
                defer { f.close() }
                for i in 0..<4 {
                    let frame = try f.frame(i)
                    XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.001)
                }
                XCTAssertEqual(f.main(try f.frame(1)), horizontal ? 280 : 70, accuracy: 0.5)
                XCTAssertEqual(f.start(try f.frame(2)), f.end(try f.frame(1)) + 10, accuracy: 0.5)
            }
        }
    }

    func testAdaptiveRatioRecomputesOnResize() throws {
        for horizontal in [false, true] {
            let f = SizingFixture(horizontal: horizontal, size: .aspectRatio(1), adaptive: true)
            defer { f.close() }
            let before = try f.frame(0)
            f.collection.frame.size =
            horizontal ? CGSize(width: 600, height: 270) : CGSize(width: 270, height: 600)
            f.collection.collectionViewLayout.invalidateLayout()
            f.settle()
            let after = try f.frame(0)
            XCTAssertEqual(after.width, after.height, accuracy: 0.5)
            XCTAssertNotEqual(f.cross(before), f.cross(after))
        }
    }

    func testEstimatedBoundariesInBothAxes() throws {
        for horizontal in [false, true] {
            let f = SizingFixture(horizontal: horizontal, size: .fixed(56), boundary: .estimated(20))
            defer { f.close() }
            let header = try f.boundary(UICollectionView.elementKindSectionHeader)
            let footer = try f.boundary(UICollectionView.elementKindSectionFooter)
            XCTAssertEqual(f.main(header), 75, accuracy: 1)
            XCTAssertEqual(f.main(footer), 65, accuracy: 1)
            XCTAssertGreaterThanOrEqual(f.start(try f.frame(0)), f.end(header))
            XCTAssertGreaterThanOrEqual(f.start(footer), f.end(try f.frame(3)))
        }
    }

    func testRatioBoundariesRespectSectionInsets() throws {
        for horizontal in [false, true] {
            let f = SizingFixture(
                horizontal: horizontal, size: .fixed(56), insetContent: true, boundary: .aspectRatio(2))
            defer { f.close() }
            for kind in [
                UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter,
            ] {
                let frame = try f.boundary(kind)
                XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.001)
                XCTAssertEqual(f.cross(frame), 320, accuracy: 0.5)
            }
        }
    }
    func testNestedContentGroupsPreservePerUnitSelfSizingAndUniformScope() throws {
        for horizontal in [false, true] {
            var sizes: [ListGridItemMainAxisSize] = [.estimated(56)]
            if #available(iOS 17.0, *) { sizes.append(.uniform(estimated: 56)) }
            for (index, size) in sizes.enumerated() {
                let f = SizingFixture(horizontal: horizontal, size: size, grouping: .count(lines: 2))
                defer { f.close() }
                let expected: [CGFloat] = index == 0 ? [40, 110, 60, 80] : [110, 110, 80, 80]
                for (item, extent) in expected.enumerated() {
                    XCTAssertEqual(f.main(try f.frame(item)), extent, accuracy: 1)
                }
                XCTAssertEqual(f.start(try f.frame(2)), f.end(try f.frame(1)) + 10, accuracy: 1)
                f.source.extents = [50, 150, 30, 40, 70]
                f.reload()
                XCTAssertEqual(f.main(try f.frame(2)), index == 0 ? 30 : 40, accuracy: 1)
                XCTAssertEqual(f.start(try f.frame(4)), f.end(try f.frame(3)) + 10, accuracy: 1)
            }
        }
    }

}

@MainActor
private final class SizingFixture {
    let horizontal: Bool
    let source = SizingSource()
    let collection: UICollectionView
    let window: UIWindow
    init(
        horizontal: Bool, size: ListGridItemMainAxisSize? = nil, insetContent: Bool = false,
        boundary: ListBoundaryMainAxisSize? = nil, adaptive: Bool = false, grouping: ListGridLineGrouping = .count(lines: 1)
    ) {
        self.horizontal = horizontal
        source.horizontal = horizontal
        let tracks =
        adaptive
        ? [ListGridTrack(.adaptive(minimumForCount: 90), spacingAfter: 10)]
        : [
            ListGridTrack(.fixed(100), spacingAfter: 10), ListGridTrack(.fixed(140), spacingAfter: 10),
        ]
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = horizontal ? .horizontal : .vertical
        config.contentInsetsReference = .none
        let layout = UICollectionViewCompositionalLayout(
            sectionProvider: { _, env in
                let insets = insetContent ? ListLayoutInsets(20) : .zero
                var grid = GridLayout(tracks: tracks)
                    .trackSpacing(10).lineSpacing(10).sectionInsets(insets).lineGrouping(grouping)
                if let size { grid = grid.itemMainAxisSize(size) }
                let result = ListSectionLayout.gridConfiguration(grid).makeCompositionalSection(
                    environment: env, itemSupplementaries: [],
                    scrollDirection: horizontal ? .horizontal : .vertical)
                if let boundary {
                    let cross =
                    (horizontal
                     ? env.container.effectiveContentSize.height
                     : env.container.effectiveContentSize.width) - (insetContent ? 40 : 0)
                    result.boundarySupplementaryItems = [
                        UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter,
                    ].map { kind in
                        let main = boundary.measurement.dimension(
                            crossExtent: cross, isVertical: !horizontal, uniformSiblings: false)
                        let isHeader = kind == UICollectionView.elementKindSectionHeader
                        return NSCollectionLayoutBoundarySupplementaryItem(
                            layoutSize: .init(
                                widthDimension: horizontal ? main : .fractionalWidth(1),
                                heightDimension: horizontal ? .fractionalHeight(1) : main), elementKind: kind,
                            alignment: horizontal
                            ? (isHeader ? .leading : .trailing) : (isHeader ? .top : .bottom))
                    }
                }
                return result
            }, configuration: config)
        let rect =
        horizontal
        ? CGRect(x: 0, y: 0, width: 1200, height: 360) : CGRect(x: 0, y: 0, width: 360, height: 1200)
        collection = UICollectionView(frame: rect, collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(SizingCell.self, forCellWithReuseIdentifier: "cell")
        for kind in [
            UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter,
        ] {
            collection.register(
                SizingBoundary.self, forSupplementaryViewOfKind: kind, withReuseIdentifier: "boundary")
        }
        collection.dataSource = source
        let controller = UIViewController()
        window = UIWindow(frame: rect)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.addSubview(collection)
        reload()
    }
    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
    func reload() {
        collection.reloadData()
        settle()
    }
    func settle() {
        for _ in 0..<8 {
            window.layoutIfNeeded()
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    func frame(_ i: Int) throws -> CGRect {
        try XCTUnwrap(
            collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: i, section: 0))
        ).frame
    }
    func boundary(_ kind: String) throws -> CGRect {
        try XCTUnwrap(
            collection.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: kind, at: IndexPath(item: 0, section: 0))
        ).frame
    }
    func main(_ r: CGRect) -> CGFloat { horizontal ? r.width : r.height }
    func cross(_ r: CGRect) -> CGFloat { horizontal ? r.height : r.width }
    func start(_ r: CGRect) -> CGFloat { horizontal ? r.minX : r.minY }
    func end(_ r: CGRect) -> CGFloat { horizontal ? r.maxX : r.maxY }
}

@MainActor
private final class SizingSource: NSObject, UICollectionViewDataSource {
    var horizontal = false
    var extents: [CGFloat] = [40, 110, 60, 80]
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
    -> Int
    { extents.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
    -> UICollectionViewCell
    {
        let cell =
        collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SizingCell
        cell.content.horizontal = horizontal
        cell.content.extent = extents[indexPath.item]
        return cell
    }
    func collectionView(
        _ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let view =
        collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: "boundary", for: indexPath) as! SizingBoundary
        view.content.horizontal = horizontal
        view.content.extent = kind == UICollectionView.elementKindSectionHeader ? 75 : 65
        return view
    }
}

@MainActor
private final class SizingContent: UIView {
    var horizontal = false
    var extent: CGFloat = 40 { didSet { invalidateIntrinsicContentSize() } }
    override var intrinsicContentSize: CGSize {
        horizontal
        ? CGSize(width: extent, height: UIView.noIntrinsicMetric)
        : CGSize(width: UIView.noIntrinsicMetric, height: extent)
    }
    func pin(to parent: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
    func fit(_ attributes: UICollectionViewLayoutAttributes, in view: UIView)
    -> UICollectionViewLayoutAttributes
    {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        let target =
        horizontal
        ? CGSize(width: 0, height: attributes.size.height)
        : CGSize(width: attributes.size.width, height: 0)
        let size = view.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: horizontal ? .fittingSizeLevel : .required,
            verticalFittingPriority: horizontal ? .required : .fittingSizeLevel)
        if horizontal {
            result.size.width = ceil(size.width)
        } else {
            result.size.height = ceil(size.height)
        }
        return result
    }
}

@MainActor
private final class SizingCell: UICollectionViewCell {
    let content = SizingContent()
    override init(frame: CGRect) {
        super.init(frame: frame)
        content.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
    -> UICollectionViewLayoutAttributes
    {
        content.fit(attributes, in: contentView)
    }
}

@MainActor
private final class SizingBoundary: UICollectionReusableView {
    let content = SizingContent()
    override init(frame: CGRect) {
        super.init(frame: frame)
        content.pin(to: self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
    -> UICollectionViewLayoutAttributes
    {
        content.fit(attributes, in: self)
    }
}
