import UIKit
import XCTest

@testable import ListKit

@MainActor
final class DeclarativeLayoutTests: XCTestCase {
    func testLayoutSourceReplacementAndEmptyBranchReset() {
        let original = ListSection(0) {
        } layout: {
            GridLayout(tracks: 3)
        }
        let custom = original.layout {
            CustomLayout(layoutKey: 1) { context in
                ListSectionLayout.gridConfiguration(GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0))
                    .makeCompositionalSection(
                    environment: context.environment, itemSupplementaries: context.itemSupplementaries)
            }
        }
        guard case .custom = custom.layoutSource else { return XCTFail("custom source") }
        XCTAssertEqual(original.layoutSource, .builtIn(.gridConfiguration(GridLayout(tracks: 3))))
        XCTAssertEqual(custom.layout {}.layoutSource, .builtIn(.defaultLayout))
        XCTAssertEqual(
            original.layout { if false { GridLayout(tracks: 2) } }.layoutSource, .builtIn(.defaultLayout))
    }

    func testInvalidRulesAndDuplicateKindsDiagnosedBeforeApply() {
        let invalid = ListSection(0) {
        } layout: {
            GridLayout(tracks: [
                ListGridTrack(.adaptive(minimumForCount: .nan)), ListGridTrack(.fixed(-1), spacingAfter: .infinity),
            ])
            .itemMainAxisSize(.aspectRatio(0)).sectionInsets(.init(-1))
            .boundarySupplementaries {
                BoundarySupplementaryLayout(
                    kind: "same",
                    size: .init(width: .fractionalWidth(1), height: .estimated(44)), alignment: .top
                ).whenContentExists()
                BoundarySupplementaryLayout(
                    kind: "same",
                    size: .init(width: .fractionalWidth(1), height: .estimated(44)), alignment: .top
                ).whenContentExists()
            }

        } supplementaries: {
            SectionSupplementary(
                UICollectionReusableView.self, kind: "same", id: 1
            ) { _, _ in }
            SectionSupplementary(
                UICollectionReusableView.self, kind: "same", id: 2
            ) { _, _ in }
        }
        let issues = ListDiagnostics.validate([invalid])
        XCTAssertGreaterThanOrEqual(issues.filter { $0.kind == .invalidLayout }.count, 5)
        XCTAssertTrue(issues.contains { $0.kind == .duplicateSupplementaryKind })
        XCTAssertFalse(
            ListDiagnostics.validate([
                ListSection(0) {
                } layout: {
                    GridLayout(tracks: [])
                }
            ]).isEmpty)
    }

    func testNativeListRejectsItemSupplementary() {
        // Public API forbids this; inject malformed internal metadata to retain defensive validation coverage.
        var native = UIKitListLayout()
        native.options.items = [ItemSupplementaryLayout(
            kind: "badge", size: .init(width: .absolute(12), height: .absolute(12)), itemAnchor: .topTrailing
        ).whenContentExists()]
        let section = ListSection(0) {
        } layout: {
            native
        } supplementaries: {
            SectionSupplementary(
                UICollectionReusableView.self, kind: "badge", id: 0
            ) { _, _ in }
        }
        XCTAssertTrue(ListDiagnostics.validate([section]).contains { $0.kind == .invalidLayout })
    }

    func testAutomaticAxisAndEnvironmentSelectedInvalidLayoutHaveDiagnostics() {
        let fixture = LayoutFixture(width: 360, count: 1)
        defer { fixture.close() }
        fixture.apply(GridLayout(tracks: 2))
        XCTAssertNotNil(
            fixture.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
        fixture.render()
        fixture.adapter.apply(
            [
                ListSection(0) {
                } layout: {
                    EnvironmentLayout(layoutKey: 0) { _ in GridLayout(tracks: 0) }
                }
            ], transaction: .disabled)
        fixture.render()
        XCTAssertNil(
            fixture.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.contains { $0.message.contains("count") })
    }

    func testMixedItemSupplementaryReportsUIKitRestriction() {
        let f = LayoutFixture(width: 360, count: 1)
        defer { f.close() }
        f.adapter.apply(
            [
                ListSection(0) {
                    Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
                } layout: {
                    GridLayout(tracks: [ListGridTrack(.fixed(50)), ListGridTrack(.fixed(90))])
                        .itemSupplementaries {
                            ItemSupplementaryLayout(
                                kind: "badge",
                                size: .init(width: .absolute(10), height: .absolute(10)), itemAnchor: .topTrailing
                            ).whenContentExists()
                        }

                } supplementaries: {
                    SectionSupplementary(
                        UICollectionReusableView.self, kind: "badge", id: 0
                    ) { _, _ in }
                }
            ], transaction: .disabled)
        f.render()
        XCTAssertTrue(
            f.adapter.lastLayoutDiagnostics.contains { $0.message.contains("heterogeneous grid tracks") })
        XCTAssertEqual(f.collection.numberOfItems(inSection: 0), 1)  // safe fallback still renders content
    }

    func testHorizontalRowsRenderWithInsetsAndIncompleteColumns() throws {
        for height in [CGFloat(240), 390, 768] {
            let f = LayoutFixture(width: height, count: 7, horizontal: true)
            defer { f.close() }
            f.apply(
                GridLayout(tracks: 3).trackSpacing(10).lineSpacing(10).itemMainAxisSize(.aspectRatio(2))
                    .sectionInsets(.init(top: 17, leading: 5, bottom: 23, trailing: 9)))
            f.render()
            let cross = (height - 40 - 20) / 3
            for index in 0..<7 {
                let frame = try f.frame(index)
                XCTAssertEqual(frame.height, cross, accuracy: 0.6)
                XCTAssertEqual(frame.width, cross * 2, accuracy: 0.6)
                XCTAssertEqual(frame.minY, 17 + CGFloat(index % 3) * (cross + 10), accuracy: 0.6)
                XCTAssertEqual(frame.minX, 5 + CGFloat(index / 3) * (cross * 2 + 10), accuracy: 0.6)
            }
        }
    }

    func testEffectiveContainerInsetsAreAppliedOnce() throws {
        let f = LayoutFixture(width: 400, count: 3)
        defer { f.close() }
        f.apply(
            GridLayout(tracks: [ListGridTrack(.adaptive(minimumForCount: 80))]).trackSpacing(12).lineSpacing(12).sectionInsets(.init(20)))
        let env = TestLayoutEnvironment()
        env.container = InsetLayoutContainer()
        let adapter = f.adapter
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.contentInsetsReference = .none
        f.collection.collectionViewLayout = UICollectionViewCompositionalLayout(
            sectionProvider: { [weak adapter] index, _ in
                adapter?.makeCompositionalSection(for: index, environment: env)
            }, configuration: config)
        f.render()
        XCTAssertEqual(try f.frame(0).width, (360 - 40 - 24) / 3, accuracy: 0.6)
    }

    func testGridRenderedMatrixAndResize() throws {
        for width in [CGFloat(240), 390, 768] {
            for count in [0, 1, 2, 7, 20] {
                for spacing in [CGFloat(0), 12] {
                    let f = LayoutFixture(width: width, count: count)
                    defer { f.close() }
                    f.apply(
                        GridLayout(tracks: 3).itemMainAxisSize(.aspectRatio(1)).trackSpacing(spacing).lineSpacing(spacing).sectionInsets(
                            .init(top: 5, leading: 17, bottom: 9, trailing: 23)))
                    f.render()
                    XCTAssertEqual(f.collection.numberOfItems(inSection: 0), count)
                    let expected = (width - 40 - spacing * 2) / 3
                    for index in 0..<count {
                        let frame = try f.frame(index)
                        XCTAssertEqual(frame.width, expected, accuracy: 0.6)
                        XCTAssertEqual(frame.height, expected, accuracy: 0.6)
                        XCTAssertEqual(
                            frame.minX, 17 + CGFloat(index % 3) * (expected + spacing), accuracy: 0.6)
                        XCTAssertEqual(frame.minY, 5 + CGFloat(index / 3) * (expected + spacing), accuracy: 0.6)
                    }
                }
            }
        }
    }

    func testAdaptiveResizeAndStateApplyKeepTheSameLayoutInstance() throws {
        let f = LayoutFixture(width: 360, count: 7)
        defer { f.close() }
        f.apply(GridLayout(tracks: [ListGridTrack(.adaptive(minimumForCount: 100))]).itemMainAxisSize(.aspectRatio(1)).trackSpacing(10).lineSpacing(10))
        f.render()
        let layout = f.collection.collectionViewLayout
        XCTAssertEqual(try f.frame(2).minY, 0, accuracy: 0.5)
        f.collection.frame.size.width = 250
        f.render()
        XCTAssertEqual(try f.frame(2).minY, 130, accuracy: 0.5)
        f.apply(GridLayout(tracks: 1).trackSpacing(4).lineSpacing(4).itemMainAxisSize(.fixed(40)))
        f.render()
        XCTAssertTrue(f.collection.collectionViewLayout === layout)
        XCTAssertEqual(try f.frame(1).minY, 44, accuracy: 0.5)
        XCTAssertEqual(try f.frame(1).width, 250, accuracy: 0.5)
    }

    func testMixedTrackSpacingAlignmentAndRTL() throws {
        for rtl in [false, true] {
            let f = LayoutFixture(width: 400, count: 7, rtl: rtl)
            defer { f.close() }
            f.apply(
                GridLayout(tracks: [
                        ListGridTrack(.fixed(70), spacingAfter: 4), ListGridTrack(.fixed(90), spacingAfter: 17),
                        ListGridTrack(.fixed(60)),
                ]
                ).trackGroupAlignment(.end)
                .trackSpacing(12).lineSpacing(12).sectionInsets(.init(10)))
            f.render()
            // UIKit keeps logical layout attributes; compare rendered cells in window coordinates for RTL.
            let frames = try (0..<3).map { index in
                let cell = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: index, section: 0)))
                return cell.convert(cell.bounds, to: f.window)
            }
            XCTAssertEqual(frames.map(\.width), [70, 90, 60])
            if rtl {
                XCTAssertGreaterThan(frames[0].minX, frames[1].minX)
                XCTAssertEqual(frames[2].minX, 10, accuracy: 0.6)
                XCTAssertEqual(frames[0].minX - frames[1].maxX, 4, accuracy: 0.6)
                XCTAssertEqual(frames[1].minX - frames[2].maxX, 17, accuracy: 0.6)
            } else {
                XCTAssertEqual(frames[2].maxX, 390, accuracy: 0.6)
                XCTAssertEqual(frames[1].minX - frames[0].maxX, 4, accuracy: 0.6)
                XCTAssertEqual(frames[2].minX - frames[1].maxX, 17, accuracy: 0.6)
            }
        }
    }

    func testEnvironmentSwitchAndCustomSupplementaryPipeline() throws {
        let f = LayoutFixture(width: 360, count: 5)
        defer { f.close() }
        f.adapter.apply(
            [
                ListSection(0) {
                    for i in 0..<5 { Row(i, model: i, cell: UICollectionViewCell.self) { _, _, _ in } }
                } layout: {
                    EnvironmentLayout(layoutKey: "responsive") { env in
                        if env.container.effectiveContentSize.width >= 500 {
                            GridLayout(tracks: 4)
                        } else {
                            GridLayout(tracks: 2)
                        }
                    }
                }
            ], transaction: .disabled)
        f.render()
        XCTAssertGreaterThan(try f.frame(2).minY, 0)
        f.collection.frame.size.width = 600
        f.render()
        XCTAssertEqual(try f.frame(2).minY, 0, accuracy: 0.5)
        var receivedItems = 0
        let custom = ListSection(0) {
            Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
        } layout: {
            CustomLayout(layoutKey: 1) { context in
                receivedItems = context.itemSupplementaries.count
                XCTAssertEqual(context.section.id, 0)
                return ListSectionLayout.gridConfiguration(
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(60)).trackSpacing(0).lineSpacing(0)
                ).makeCompositionalSection(
                    environment: context.environment, itemSupplementaries: context.itemSupplementaries)
            }
            .boundarySupplementaries {
                BoundarySupplementaryLayout(
                    kind: UICollectionView.elementKindSectionHeader,
                    size: .init(width: .fractionalWidth(1), height: .absolute(30)), alignment: .top
                ).pinToVisibleBounds(true).whenContentExists()
            }
            .itemSupplementaries {
                ItemSupplementaryLayout(
                    kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)),
                    itemAnchor: .topTrailing
                ).whenContentExists()
            }
            .decorationItems {
                DecorationItemLayout(kind: "section-decoration", backgroundInsets: .zero, zIndex: -1)
                    .whenContentExists()
            }

        } supplementaries: {
            SectionSupplementary(
                UICollectionReusableView.self,
                kind: UICollectionView.elementKindSectionHeader, id: 0
            ) { _, _ in }

            SectionSupplementary(
                UICollectionReusableView.self, kind: "badge", id: 0
            ) { _, _ in }
        } decorations: {
            SectionDecoration(LayoutTestBackground.self, kind: "section-decoration")
        }
        f.adapter.apply([custom], transaction: .disabled)
        f.render()
        XCTAssertEqual(receivedItems, 1)
        XCTAssertNotNil(
            f.collection.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: "badge", at: IndexPath(item: 0, section: 0)))
        XCTAssertNotNil(
            f.collection.collectionViewLayout.layoutAttributesForDecorationView(
                ofKind: custom.decorations.first!.elementKind, at: IndexPath(item: 0, section: 0)))
        let resolved = try XCTUnwrap(
            f.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(resolved.boundarySupplementaryItems[0].pinToVisibleBounds)
    }

    func testCustomAndEnvironmentIDDriveInvalidation() {
        let f = LayoutFixture(width: 360, count: 1)
        defer { f.close() }
        func apply(_ id: Int) {
            f.adapter.apply(
                [
                    ListSection(0) {
                    } layout: {
                        EnvironmentLayout(layoutKey: id) { _ in GridLayout(tracks: id + 1) }
                    }
                ], transaction: .disabled)
            f.render()
        }
        apply(0)
        let baseline = f.adapter.layoutInvalidationGeneration
        apply(0)
        XCTAssertEqual(f.adapter.layoutInvalidationGeneration, baseline)
        apply(1)
        XCTAssertEqual(f.adapter.layoutInvalidationGeneration, baseline + 1)
    }
}

@MainActor
final class LayoutFixture {
    let window: UIWindow
    let collection: UICollectionView
    let adapter: CollectionListAdapter<Int>
    let count: Int
    init(width: CGFloat, count: Int, rtl: Bool = false, horizontal: Bool = false) {
        self.count = count
        collection = UICollectionView(
            frame: CGRect(
                x: 0, y: 0, width: horizontal ? 1400 : width, height: horizontal ? width : 1400),
            collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        collection.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        if #available(iOS 17.0, *) {
            collection.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
        }
        adapter = CollectionListAdapter(collectionView: collection)
        collection.collectionViewLayout = adapter.makeCompositionalLayout(
            configuration: .init(
                scrollDirection: horizontal ? .horizontal : .vertical, contentInsetsReference: .none))
        window = UIWindow(frame: collection.frame)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        controller.view.addSubview(collection)
    }
    func apply(_ grid: ListSectionGridLayout) {
        adapter.apply(
            [
                ListSection(0) {
                    for i in 0..<count {
                        Row(i, model: i, cell: UICollectionViewCell.self) { cell, _, _ in
                            cell.backgroundColor = .systemBlue
                        }
                    }
                } layout: {
                    grid
                }
            ], transaction: .disabled)
    }
    func render() {
        for _ in 0..<3 {
            window.layoutIfNeeded()
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    func frame(_ index: Int) throws -> CGRect {
        try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: index, section: 0))).frame
    }
    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}
private final class LayoutTestBackground: UICollectionReusableView {}

private final class InsetLayoutContainer: NSObject, NSCollectionLayoutContainer {
    let contentSize = CGSize(width: 400, height: 300)
    let effectiveContentSize = CGSize(width: 360, height: 260)
    let contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    var effectiveContentInsets: NSDirectionalEdgeInsets { contentInsets }
}
