import UIKit
import XCTest

@testable import ListKit

@MainActor final class CompleteSectionLayoutTests: XCTestCase {
    let title = "title"
    let card = "card"

    func boundary(_ kind: String, height: CGFloat = 36) -> BoundarySupplementaryLayout {
        .init(
            kind: kind, size: .init(width: .fractionalWidth(1), height: .absolute(height)), alignment: .top
        )
    }
    func content(_ kind: String, id: String? = nil, version: Int = 0)
    -> ListSectionSupplementary<Int>
    {
        let contentID = id ?? kind
        return SectionSupplementary(UICollectionReusableView.self, kind: kind, id: contentID) {
            _, _ in
        }.refreshID(version)
    }
    func testValueCopyAndRepeatedModifiersReplaceCollections() {
        let base = GridLayout(tracks: 2).boundarySupplementaries { boundary(title) }
        let changed = base.boundarySupplementaries { boundary("other") }
            .decorationItems { DecorationItemLayout(kind: card) }.itemMainAxisSize(.fixed(50)).trackSpacing(11).lineSpacing(11)
        XCTAssertEqual(base.options.boundaries.map(\.kind), [title])
        XCTAssertEqual(changed.options.boundaries.map(\.kind), ["other"])
        XCTAssertEqual(changed.trackSpacing, 11)
        XCTAssertEqual(changed.lineSpacing, 11)
        XCTAssertNil(changed.groupSpacing)
        let section = ListSection(0) {
        } layout: {
            changed
        } supplementaries: {
            content(title)
        }
        let replaced = section.layout { GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0) }
        XCTAssertTrue(replaced.layoutSource.options!.boundaries.isEmpty)
        XCTAssertNil(replaced.layoutSource.options!.decorations)
    }
    func testMissingContentAndWhenPresent() {
        let required = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                boundary(title)
            }
        }
        XCTAssertTrue(
            ListDiagnostics.validate([required]).contains { $0.message.contains("missing content") })
        let optional = required.layout {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                boundary(title).whenContentExists()
            }
        }
        XCTAssertTrue(ListDiagnostics.validate([optional]).isEmpty)
        XCTAssertTrue(optional.resolvedForTesting().boundarySupplementaryItems.isEmpty)
        let unused = ListSection(0) {
        } supplementaries: {
            content(title)
        }
        XCTAssertTrue(unused.resolvedForTesting().boundarySupplementaryItems.isEmpty)
    }
    func testDuplicateKindsAndConflictingAttachmentAreDiagnosed() {
        let duplicate = ListSection(0) {
        } supplementaries: {
            content(title, id: "one")
            content(title, id: "two")
        }
        XCTAssertTrue(
            ListDiagnostics.validate([duplicate]).contains { $0.kind == .duplicateSupplementaryKind })
        let conflict = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                boundary(title)
            }.itemSupplementaries {
                ItemSupplementaryLayout(
                    kind: title, size: .init(width: .absolute(10), height: .absolute(10)), itemAnchor: .top)
            }
        } supplementaries: {
            content(title)
        }
        XCTAssertTrue(
            ListDiagnostics.validate([conflict]).contains { $0.message.contains("layout kind") })
    }
    func testKindDoesNotDeterminePosition() {
        let section = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                boundary(UICollectionView.elementKindSectionFooter).pinToVisibleBounds()
            }
        } supplementaries: {
            content(UICollectionView.elementKindSectionFooter, id: "title", version: 4)
        }
        let result = section.resolvedForTesting()
        XCTAssertEqual(result.boundarySupplementaryItems.first?.alignment, .top)
        XCTAssertEqual(
            result.boundarySupplementaryItems.first?.elementKind,
            UICollectionView.elementKindSectionFooter)
        XCTAssertEqual(section.supplementaries.first?.kind, UICollectionView.elementKindSectionFooter)
    }
    func testDecorationCollectionsDefaultsExplicitEmptyAndReplacement() {
        let overlay = "overlay"
        let base = ListSection(0) {
        } decorations: {
            SectionDecoration(UICollectionReusableView.self, kind: card)
            SectionDecoration(UICollectionReusableView.self, kind: overlay)
        }
        XCTAssertEqual(base.resolvedForTesting().decorationItems.count, 2)
        let configured = base.layout {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).decorationItems {
                DecorationItemLayout(kind: card, backgroundInsets: .init(6), zIndex: -3)
                DecorationItemLayout(kind: overlay, zIndex: 2)
            }
        }
        let items = configured.resolvedForTesting().decorationItems
        XCTAssertEqual(items.map(\.zIndex), [-3, 2])
        XCTAssertEqual(items[0].contentInsets.leading, 6)
        XCTAssertTrue(
            base.layout { GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).decorationItems(.none) }
                .resolvedForTesting().decorationItems.isEmpty)
        XCTAssertEqual(base.resolvedForTesting().decorationItems[0].contentInsets.leading, 0)
    }
    func testMissingAndDuplicateDecorationKindsDiagnose() {
        let missing = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).decorationItems {
                DecorationItemLayout(kind: card)
            }
        }
        XCTAssertTrue(
            ListDiagnostics.validate([missing]).contains { $0.message.contains("missing decoration") })
        let duplicate = ListSection(0) {
        } decorations: {
            SectionDecoration(UICollectionReusableView.self, kind: card)
            SectionDecoration(UICollectionReusableView.self, kind: card)
        }
        XCTAssertTrue(
            ListDiagnostics.validate([duplicate]).contains {
                $0.message.contains("decoration logical kind")
            })
    }
    func testEnvironmentSelectsWholeLayoutIncludingDecorations() throws {
        let collection = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        let logicalKind = title
        let decoration = card
        adapter.apply(
            [
                ListSection(0) {
                } layout: {
                    EnvironmentLayout(layoutKey: 1) { environment in
                        if environment.container.effectiveContentSize.width > 500 {
                            GridLayout(tracks: 4).sectionInsets(.init(20)).boundarySupplementaries {
                                BoundarySupplementaryLayout(
                                    kind: logicalKind, size: .init(width: .fractionalWidth(1), height: .absolute(48)),
                                    alignment: .top
                                ).pinToVisibleBounds()
                            }.decorationItems { DecorationItemLayout(kind: decoration, backgroundInsets: .init(7)) }
                        } else {
                            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).sectionInsets(.init(8))
                                .decorationItems(.none)
                        }
                    }
                } supplementaries: {
                    content(title)
                } decorations: {
                    SectionDecoration(UICollectionReusableView.self, kind: card)
                }
            ], transaction: .disabled)
        let env = TestLayoutEnvironment()
        env.container = TestLayoutContainer(contentSize: .init(width: 768, height: 800))
        let wide = try XCTUnwrap(adapter.makeCompositionalSection(for: 0, environment: env))
        XCTAssertEqual(wide.boundarySupplementaryItems.count, 1)
        XCTAssertEqual(wide.decorationItems.first?.contentInsets.leading, 7)
        env.container = TestLayoutContainer(contentSize: .init(width: 240, height: 800))
        let narrow = try XCTUnwrap(adapter.makeCompositionalSection(for: 0, environment: env))
        XCTAssertTrue(narrow.boundarySupplementaryItems.isEmpty)
        XCTAssertTrue(narrow.decorationItems.isEmpty)
        XCTAssertEqual(narrow.contentInsets.leading, 8)
    }
    func testCustomInsetsMustBeConsumedAndProviderDefaultIsPreserved() async throws {
        let collection = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        func section(consume: Bool) -> ListSection<Int> {
            ListSection(0) {
            } layout: {
                CustomLayout(layoutKey: consume, sectionInsets: .init(18)) { context in
                    let value = ListSectionLayout.gridConfiguration(
                        GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                    ).makeCompositionalSection(
                        environment: context.environment, itemSupplementaries: [])
                    if consume { value.contentInsets = context.sectionInsets!.directionalEdgeInsets }
                    return value
                }
            }
        }
        await adapter.apply(options: .init(transaction: .disabled)) { section(consume: false) }
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(
            adapter.lastLayoutDiagnostics.contains { $0.message.contains("context.sectionInsets") })
        await adapter.apply(options: .init(transaction: .disabled)) { section(consume: true) }
        XCTAssertEqual(
            adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment())?.contentInsets
                .top, 18)
        XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
        let provider = ListSection(0) {
        } layout: {
            CustomLayout(layoutKey: 3) { context in
                let value = ListSectionLayout.gridConfiguration(
                    GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                ).makeCompositionalSection(
                    environment: context.environment, itemSupplementaries: [])
                value.contentInsets = .init(top: 9, leading: 8, bottom: 7, trailing: 6)
                return value
            }
        }
        XCTAssertEqual(provider.resolvedForTesting().contentInsets.top, 9)
    }
    func testSupplementaryRefreshDoesNotInvalidateButGeometryDoes() async {
        let collection = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        func section(_ height: CGFloat, _ version: Int) -> ListSection<Int> {
            ListSection(0) {
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                    boundary(title, height: height)
                }
            } supplementaries: {
                content(title, version: version)
            }
        }
        await adapter.apply(options: .init(transaction: .disabled)) { section(36, 0) }
        let generation = adapter.layoutInvalidationGeneration
        await adapter.apply(options: .init(transaction: .disabled)) { section(36, 1) }
        XCTAssertEqual(adapter.layoutInvalidationGeneration, generation)
        await adapter.apply(options: .init(transaction: .disabled)) { section(48, 1) }
        XCTAssertEqual(adapter.layoutInvalidationGeneration, generation + 1)
    }
}

extension CompleteSectionLayoutTests {
    func testRenderedDecorationAndBoundaryMatrixAndPinning() async throws {
        for width in [CGFloat(240), 390, 768] {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 400))
            let controller = UIViewController()
            window.rootViewController = controller
            window.makeKeyAndVisible()
            let collection = UICollectionView(
                frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
            collection.contentInsetAdjustmentBehavior = .never
            controller.view.addSubview(collection)
            let adapter = CollectionListAdapter<Int>(collectionView: collection)
            collection.collectionViewLayout = adapter.makeCompositionalLayout()
            for count in [0, 1, 2, 7, 60] {
                for gap in [CGFloat(0), 10] {
                    await adapter.apply(options: .init(transaction: .disabled)) {
                        ListSection(0) {
                            for index in 0..<count {
                                Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                            }
                        } layout: {
                            GridLayout(tracks: 3).itemMainAxisSize(.aspectRatio(1)).trackSpacing(gap).lineSpacing(gap).sectionInsets(
                                .init(top: 8, leading: 12, bottom: 10, trailing: 20)
                            )
                            .boundarySupplementaries { boundary(title).pinToVisibleBounds().zIndex(2) }
                            .decorationItems { DecorationItemLayout(kind: card, backgroundInsets: .init(4), zIndex: -2) }
                        } supplementaries: {
                            content(title)
                        } decorations: {
                            SectionDecoration(UICollectionReusableView.self, kind: card)
                        }
                    }
                    collection.setContentOffset(.zero, animated: false)
                    collection.layoutIfNeeded()
                    let index = IndexPath(item: 0, section: 0)
                    let layout = collection.collectionViewLayout
                    let header = try XCTUnwrap(
                        layout.layoutAttributesForSupplementaryView(ofKind: title, at: index))
                    let decoration = try XCTUnwrap(
                        layout.layoutAttributesForDecorationView(
                            ofKind: SectionDecoration(UICollectionReusableView.self, kind: card).elementKind,
                            at: index))
                    XCTAssertEqual(header.frame.height, 36, accuracy: 1)
                    XCTAssertEqual(decoration.zIndex, -2)
                    XCTAssertTrue(decoration.frame.width.isFinite)
                    if count > 0 {
                        let cell = try XCTUnwrap(layout.layoutAttributesForItem(at: index))
                        XCTAssertEqual(cell.frame.width, (width - 32 - gap * 2) / 3, accuracy: 1)
                        XCTAssertEqual(cell.frame.height, cell.frame.width, accuracy: 1)
                        XCTAssertGreaterThanOrEqual(cell.frame.minY, header.frame.maxY - 1)
                    }
                    if count == 60 {
                        collection.setContentOffset(CGPoint(x: 0, y: 150), animated: false)
                        collection.layoutIfNeeded()
                        let pinned = try XCTUnwrap(
                            layout.layoutAttributesForSupplementaryView(ofKind: title, at: index))
                        XCTAssertEqual(pinned.frame.minY, 150, accuracy: 1)
                    }
                    XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
                }
            }
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testMultipleSameSideBoundariesRemainDistinctUIKitItems() {
        let toolbar = "toolbar"
        let section = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                boundary(title)
                boundary(toolbar, height: 24).absoluteOffset(CGPoint(x: 0, y: -36)).pinToVisibleBounds()
            }
        } supplementaries: {
            content(title)
            content(toolbar)
        }
        let items = section.resolvedForTesting().boundarySupplementaryItems
        XCTAssertEqual(items.map(\.elementKind), [title, toolbar])
        XCTAssertEqual(items.map(\.alignment), [.top, .top])
        XCTAssertEqual(items[1].offset.y, -36)
        XCTAssertTrue(items[1].pinToVisibleBounds)
    }
}

extension CompleteSectionLayoutTests {
    func testDecorationLogicalKindsCanBeSharedAcrossSectionsAndEmptyEnvironmentKinds() {
        let first = ListSection(0) {
        } decorations: {
            SectionDecoration(UICollectionReusableView.self, kind: card)
        }
        let second = ListSection(1) {
        } decorations: {
            SectionDecoration(OtherDecorationView.self, kind: card)
        }
        XCTAssertEqual(first.decorations[0].kind, second.decorations[0].kind)
        XCTAssertNotEqual(first.decorations[0].elementKind, second.decorations[0].elementKind)
        XCTAssertTrue(ListDiagnostics.validate([first, second]).isEmpty)
        let invalid = ListSection(0) {
        } layout: {
            EnvironmentLayout(layoutKey: 0) { _ in GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0) }
        } supplementaries: {
            content("")
        }
        XCTAssertTrue(
            ListDiagnostics.validate([invalid]).contains {
                $0.message.contains("empty supplementary kind")
            })
    }

    func testRealBoundaryCollectionAndEnvironmentChanges() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let collection = UICollectionView(
            frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        controller.view.addSubview(collection)
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        let toolbar = "toolbar"
        let title = self.title
        var observedWidths: [CGFloat] = []
        collection.collectionViewLayout = adapter.makeCompositionalLayout()
        await adapter.apply(options: .init(transaction: .disabled)) {
            ListSection(0) {
                for index in 0..<30 {
                    Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                }
            } layout: {
                EnvironmentLayout(layoutKey: 1) { environment in
                    let _ = observedWidths.append(environment.container.effectiveContentSize.width)
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(60)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                        BoundarySupplementaryLayout(
                            kind: title, size: .init(width: .fractionalWidth(1), height: .absolute(36)),
                            alignment: .top)
                        BoundarySupplementaryLayout(
                            kind: toolbar, size: .init(width: .fractionalWidth(1), height: .absolute(24)),
                            alignment: .top
                        ).absoluteOffset(CGPoint(x: 0, y: -36))
                    }
                }
            } supplementaries: {
                content(title)
                content(toolbar)
            }
        }
        collection.layoutIfNeeded()
        let index = IndexPath(item: 0, section: 0)
        let layout = collection.collectionViewLayout
        let first = try XCTUnwrap(
            layout.layoutAttributesForSupplementaryView(ofKind: title, at: index))
        let second = try XCTUnwrap(
            layout.layoutAttributesForSupplementaryView(ofKind: toolbar, at: index))
        XCTAssertEqual(first.frame.height, 36, accuracy: 1)
        XCTAssertEqual(second.frame.height, 24, accuracy: 1)
        XCTAssertFalse(first.frame.intersects(second.frame))
        let countBeforeInsets = observedWidths.count
        collection.contentInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 30)
        collection.setNeedsLayout()
        collection.layoutIfNeeded()
        XCTAssertGreaterThan(observedWidths.count, countBeforeInsets)
        XCTAssertTrue(try XCTUnwrap(observedWidths.last).isFinite)
        let count = observedWidths.count
        collection.semanticContentAttribute = .forceRightToLeft
        collection.setNeedsLayout()
        collection.layoutIfNeeded()
        XCTAssertGreaterThan(observedWidths.count, count)
    }
}
private final class OtherDecorationView: UICollectionReusableView {}

extension CompleteSectionLayoutTests {
    func testEnvironmentInvalidGeometryIsDiagnosedBeforeUIKitConstruction() {
        let collection = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        let logicalKind = title
        adapter.apply(
            [
                ListSection(0) {
                } layout: {
                    EnvironmentLayout(layoutKey: 1) { _ in
                        GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).itemSupplementaries {
                            ItemSupplementaryLayout(
                                kind: logicalKind, size: .init(width: .absolute(-1), height: .absolute(20)), itemAnchor: .top)
                        }
                    }
                } supplementaries: {
                    content(title)
                }
            ], transaction: .disabled)
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(
            adapter.lastLayoutDiagnostics.contains { $0.message.contains("invalid dimensions") })
        let environment = TestLayoutEnvironment()
        environment.container = TestLayoutContainer(
            contentSize: .init(width: CGFloat.infinity, height: 400))
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, environment: environment))
        XCTAssertTrue(
            adapter.lastLayoutDiagnostics.contains { $0.message.contains("finite container") })
    }
}

extension CompleteSectionLayoutTests {
    func testOptionalSupplementaryExpressionsComposeWithRequiredContent() {
        let present: ListSectionSupplementary<Int>? = content(title)
        let absent: ListSectionSupplementary<Int>? = nil
        let section = ListSection(0) {
        } supplementaries: {
            present
            absent
            content("other")
        }
        XCTAssertEqual(section.supplementaries.map(\.kind), [title, "other"])
        XCTAssertTrue(ListDiagnostics.validate([section]).isEmpty)
    }

    func testNativeListOptionalItemRulesAgreeAcrossLayoutSources() async {
        for environmentDriven in [false, true] {
            for present in [false, true] {
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
                let controller = UIViewController()
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }
                let collection = UICollectionView(
                    frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
                controller.view.addSubview(collection)
                let adapter = CollectionListAdapter<Int>(collectionView: collection)
                collection.collectionViewLayout = adapter.makeCompositionalLayout()
                var native = UIKitListLayout()
                native.options.items = [
                    ItemSupplementaryLayout(
                        kind: title, size: .init(width: .absolute(12), height: .absolute(12)), itemAnchor: .top
                    ).whenContentExists()
                ]
                let section = ListSection(0) {
                    Row(0, model: 0, cell: UICollectionViewListCell.self) { _, _, _ in }
                } layout: {
                    if environmentDriven { EnvironmentLayout(layoutKey: 0) { _ in native } } else { native }
                } supplementaries: {
                    if present { content(title) }
                }
                let staticIssues = ListDiagnostics.validate([section])
                XCTAssertEqual(staticIssues.isEmpty, environmentDriven || !present)
                // 使用 disabled 让静态非法规则也到达 provider，独立验证运行路径。
                await adapter.apply(options: .init(transaction: .disabled, diagnostics: .disabled)) {
                    section
                }
                collection.layoutIfNeeded()
                XCTAssertNotNil(
                    collection.collectionViewLayout.layoutAttributesForItem(
                        at: IndexPath(item: 0, section: 0)))
                XCTAssertEqual(adapter.lastLayoutDiagnostics.isEmpty, !present)
            }
        }
    }

    func testEnvironmentResolutionFailuresDiagnoseAndRecover() async {
        let collection = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        let layouts: [ListSectionGridLayout] = [
            GridLayout(tracks: [ListGridTrack(.adaptive(minimumForCount: 0.01))]).trackSpacing(0).lineSpacing(0),
            GridLayout(tracks: [ListGridTrack(.fixed(100))]).itemMainAxisSize(
                .aspectRatio(CGFloat.leastNonzeroMagnitude)),
            GridLayout(tracks: [ListGridTrack(.fixed(100))]).itemMainAxisSize(
                .aspectRatio(CGFloat.greatestFiniteMagnitude)),
            GridLayout(tracks: [
                ListGridTrack(.fixed(CGFloat.greatestFiniteMagnitude)),
                ListGridTrack(.fixed(CGFloat.greatestFiniteMagnitude)),
            ]),
        ]
        for (index, grid) in layouts.enumerated() {
            let section = ListSection(42) {
            } layout: {
                grid
            }
            XCTAssertTrue(ListDiagnostics.validate([section]).isEmpty)
            await adapter.apply(options: .init(transaction: .disabled)) { section }
            XCTAssertNil(
                adapter.makeCompositionalSection(
                    for: 0, environment: TestLayoutEnvironment(),
                    scrollDirection: index == 2 ? .horizontal : .vertical))
            XCTAssertTrue(
                adapter.lastLayoutDiagnostics.contains { $0.message.contains("section 42") },
                "case \(index)")
        }
        await adapter.apply(options: .init(transaction: .disabled)) {
            ListSection(42) {
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: title, mainAxisSize: .aspectRatio(CGFloat.leastNonzeroMagnitude), sizingAxis: .vertical,
                        alignment: .top)
                }
            } supplementaries: {
                content(title)
            }
        }
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(
            adapter.lastLayoutDiagnostics.contains { $0.message.contains("boundary kind title") })
        await adapter.apply(options: .init(transaction: .disabled)) {
            ListSection(42) {
            } layout: {
                GridLayout(tracks: 3)
            }
        }
        XCTAssertNotNil(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
    }

    func testRenderedDecorationTypeReplacementAndBoundaryDecorationRemoval() async throws {
        for width in [CGFloat(240), 390, 768] {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 400))
            let controller = UIViewController()
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            let collection = UICollectionView(
                frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
            collection.contentInsetAdjustmentBehavior = .never
            controller.view.addSubview(collection)
            let adapter = CollectionListAdapter<Int>(collectionView: collection)
            let layout = adapter.makeCompositionalLayout()
            collection.collectionViewLayout = layout
            func section(second: Bool, boundaryVisible: Bool, decorationVisible: Bool) -> ListSection<Int>
            {
                ListSection(0) {
                    for index in 0..<20 {
                        Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                    }
                } layout: {
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).sectionInsets(.init(8))
                        .boundarySupplementaries { if boundaryVisible { boundary(title) } }
                        .decorationItems {
                            if decorationVisible { DecorationItemLayout(kind: "shared-card", backgroundInsets: .init(4)) }
                        }
                } supplementaries: {
                    content(title)  // 保留注册，只移除几何，不依赖删除内容触发 section reload。
                } decorations: {
                    if second {
                        SectionDecoration(ReplacementDecorationB.self, kind: "shared-card")
                    } else {
                        SectionDecoration(ReplacementDecorationA.self, kind: "shared-card")
                    }
                }.selectionMode(.single)
            }
            func descendants(_ view: UIView) -> [UIView] {
                view.subviews.flatMap { [$0] + descendants($0) }
            }
            func visibleDecorations() -> [UIView] {
                descendants(collection).filter {
                    ($0 is ReplacementDecorationA || $0 is ReplacementDecorationB)
                    && !$0.isHidden && $0.alpha > 0 && $0.window === window
                    && $0.convert($0.bounds, to: collection).intersects(collection.bounds)
                }
            }
            func capture(_ name: String) {
                guard width == 390 else { return }
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                    window.layer.render(in: context.cgContext)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let decorationA = SectionDecoration(
                ReplacementDecorationA.self, kind: "shared-card")
            let decorationB = SectionDecoration(
                ReplacementDecorationB.self, kind: "shared-card")
            XCTAssertEqual(decorationA.kind, decorationB.kind)
            XCTAssertNotEqual(decorationA.elementKind, decorationB.elementKind)
            let indexPath = IndexPath(item: 0, section: 0)
            await adapter.apply(options: .init(transaction: .disabled)) {
                section(second: false, boundaryVisible: true, decorationVisible: true)
            }
            collection.layoutIfNeeded()
            let original = try XCTUnwrap(visibleDecorations().first)
            XCTAssertTrue(original is ReplacementDecorationA)
            XCTAssertEqual(visibleDecorations().count, 1)
            let header = try XCTUnwrap(
                collection.supplementaryView(forElementKind: title, at: indexPath))
            let before = try XCTUnwrap(layout.layoutAttributesForItem(at: indexPath)).frame
            XCTAssertGreaterThanOrEqual(before.minY, header.frame.maxY)
            capture("decoration-type-a")
            collection.selectItem(at: indexPath, animated: false, scrollPosition: [])
            collection.setContentOffset(CGPoint(x: 0, y: 20), animated: false)
            collection.layoutIfNeeded()
            let selectedCell = collection.cellForItem(at: indexPath)

            await adapter.apply(options: .init(transaction: .disabled)) {
                section(second: true, boundaryVisible: true, decorationVisible: true)
            }
            collection.layoutIfNeeded()
            XCTAssertTrue(collection.collectionViewLayout === layout)
            XCTAssertEqual(collection.contentOffset.y, 20, accuracy: 0.5)
            XCTAssertEqual(collection.indexPathsForSelectedItems, [indexPath])
            XCTAssertTrue(collection.cellForItem(at: indexPath) === selectedCell)
            XCTAssertEqual(visibleDecorations().count, 1)
            XCTAssertTrue(visibleDecorations().first is ReplacementDecorationB)
            XCTAssertFalse(visibleDecorations().contains { $0 === original })
            capture("decoration-type-b")
            XCTAssertEqual(try XCTUnwrap(layout.layoutAttributesForItem(at: indexPath)).frame, before)

            await adapter.apply(options: .init(transaction: .disabled)) {
                section(second: true, boundaryVisible: false, decorationVisible: true)
            }
            collection.layoutIfNeeded()
            let after = try XCTUnwrap(layout.layoutAttributesForItem(at: indexPath)).frame
            XCTAssertLessThan(after.minY, before.minY)
            capture("boundary-removed")
            XCTAssertNil(collection.supplementaryView(forElementKind: title, at: indexPath))
            XCTAssertFalse(
                (layout.layoutAttributesForElements(in: collection.bounds) ?? []).contains {
                    $0.representedElementKind == title
                })
            XCTAssertEqual(visibleDecorations().count, 1)

            await adapter.apply(options: .init(transaction: .disabled)) {
                section(second: true, boundaryVisible: false, decorationVisible: false)
            }
            collection.layoutIfNeeded()
            XCTAssertTrue(visibleDecorations().isEmpty)
            capture("decoration-removed")
            XCTAssertFalse(
                (layout.layoutAttributesForElements(in: collection.bounds) ?? []).contains {
                    [decorationA.elementKind, decorationB.elementKind].contains(
                        $0.representedElementKind ?? "")
                })
            XCTAssertEqual(try XCTUnwrap(layout.layoutAttributesForItem(at: indexPath)).frame, after)
            XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
        }
    }
}
private final class ReplacementDecorationA: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBlue
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
private final class ReplacementDecorationB: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemOrange
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension CompleteSectionLayoutTests {
    func testCustomDecorationUsesResolvedRegistrationKind() throws {
        let registration = SectionDecoration(
            ReplacementDecorationA.self, kind: "custom-card")
        let logicalKind = registration.kind
        let section = ListSection(0) {
        } layout: {
            CustomLayout(layoutKey: 0) { context in
                let result = ListSectionLayout.gridConfiguration(
                    GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                ).makeCompositionalSection(
                    environment: context.environment, itemSupplementaries: [])
                XCTAssertEqual(context.decorationElementKind(for: logicalKind), registration.elementKind)
                result.decorationItems = [
                    .background(elementKind: context.decorationElementKind(for: logicalKind)!)
                ]
                return result
            }.decorationItems(.none)
        } decorations: {
            registration
        }
        XCTAssertEqual(
            section.resolvedForTesting().decorationItems.first?.elementKind, registration.elementKind)
        XCTAssertEqual(SectionDecoration(kind: logicalKind, elementKind: "raw-kind").elementKind, "raw-kind")
    }
}

extension CompleteSectionLayoutTests {
    func testDecorationKindsAndActiveGeometryConflicts() async {
        let alias = "alias"
        let typed = SectionDecoration(ReplacementDecorationA.self, kind: card)
        let manual = SectionDecoration(kind: alias, elementKind: typed.elementKind)
        XCTAssertEqual(typed.kind, card)
        XCTAssertEqual(manual.kind, alias)
        XCTAssertEqual(typed.elementKind, manual.elementKind)
        XCTAssertNotEqual(manual, SectionDecoration(kind: alias, elementKind: "different-registration"))
        XCTAssertEqual(
            Set([manual, SectionDecoration(kind: alias, elementKind: "different-registration")]).count, 2)
        let both = ListSection(0) {
        } decorations: {
            typed
            manual
        }
        let issues = ListDiagnostics.validate([both])
        XCTAssertTrue(
            issues.contains {
                $0.message.contains("duplicate decoration elementKind")
                && $0.message.contains("\(card), \(alias)") && $0.message.contains("section 0")
            })
        let onlyTyped = both.layout {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).decorationItems {
                DecorationItemLayout(kind: card)
            }
        }
        XCTAssertTrue(ListDiagnostics.validate([onlyTyped]).isEmpty)
        let card = self.card
        let environment = both.layout {
            EnvironmentLayout(layoutKey: 0) { _ in
                GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).decorationItems {
                    DecorationItemLayout(kind: card)
                }
            }
        }
        XCTAssertTrue(ListDiagnostics.validate([environment]).isEmpty)
        XCTAssertEqual(environment.resolvedForTesting().decorationItems.count, 1)
        let invalidEnvironment = both.layout {
            EnvironmentLayout(layoutKey: 1) { _ in GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0) }
        }
        XCTAssertTrue(ListDiagnostics.validate([invalidEnvironment]).isEmpty)
        let collection = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        await adapter.apply(options: .init(transaction: .disabled)) { invalidEnvironment }
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(
            adapter.lastLayoutDiagnostics.contains {
                $0.message.contains("duplicate decoration elementKind")
            })
        await adapter.apply(options: .init(transaction: .disabled)) { environment }
        XCTAssertNotNil(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
        let empty = ListSection(0) {
        } decorations: {
            SectionDecoration(kind: alias, elementKind: "")
        }
        XCTAssertTrue(
            ListDiagnostics.validate([empty]).contains { $0.message.contains("empty decoration") })
    }

    func testCustomDecorationRejectsActualElementKindCollision() {
        let registration = SectionDecoration(ReplacementDecorationA.self, kind: card)
        let section = ListSection(0) {
        } layout: {
            CustomLayout(layoutKey: 0) { context in
                let result = ListSectionLayout.gridConfiguration(
                    GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                ).makeCompositionalSection(
                    environment: context.environment, itemSupplementaries: [])
                result.decorationItems = [.background(elementKind: registration.elementKind)]
                return result
            }
        } decorations: {
            registration
        }
        let fixture = DecorationRenderingFixture(width: 390)
        defer { fixture.close() }
        fixture.adapter.apply([section], transaction: .disabled)
        XCTAssertNil(
            fixture.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(
            fixture.adapter.lastLayoutDiagnostics.contains {
                $0.message.contains("duplicate decoration elementKind")
                && $0.message.contains("provider and framework")
            })
    }

    func testRenderedMultiSectionDecorationTypeReplacement() async throws {
        for width in [CGFloat(240), 390, 768] {
            let fixture = DecorationRenderingFixture(width: width)
            defer { fixture.close() }
            func section(_ id: Int, second: Bool) -> ListSection<Int> {
                ListSection(id) {
                    for index in 0..<5 {
                        Row(id * 10 + index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                    }
                } layout: {
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).sectionInsets(.init(8))
                } decorations: {
                    if second {
                        SectionDecoration(ReplacementDecorationB.self, kind: card)
                    } else {
                        SectionDecoration(ReplacementDecorationA.self, kind: card)
                    }
                }.selectionMode(.single)
            }
            let first = section(0, second: false)
            await fixture.adapter.apply(options: .init(transaction: .disabled)) {
                first
                section(1, second: false)
            }
            fixture.collection.layoutIfNeeded()
            let index = IndexPath(item: 0, section: 0)
            fixture.collection.selectItem(at: index, animated: false, scrollPosition: [])
            fixture.collection.setContentOffset(CGPoint(x: 0, y: 20), animated: false)
            fixture.collection.layoutIfNeeded()
            let cell = try XCTUnwrap(fixture.collection.cellForItem(at: index))
            let firstFrame = try XCTUnwrap(fixture.layout.layoutAttributesForItem(at: index)).frame
            let firstDecorationFrame = try XCTUnwrap(
                fixture.layout.layoutAttributesForDecorationView(
                    ofKind: first.decorations[0].elementKind, at: index)
            ).frame
            XCTAssertEqual(fixture.visible(ReplacementDecorationA.self).count, 2)
            for useB in [true, false] {
                let second = section(1, second: useB)
                let summary = await fixture.adapter.apply(options: .init(transaction: .disabled)) {
                    first
                    second
                }
                fixture.collection.layoutIfNeeded()
                XCTAssertTrue(summary.diagnosticsIssues.isEmpty)
                XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
                XCTAssertTrue(fixture.collection.collectionViewLayout === fixture.layout)
                XCTAssertTrue(fixture.collection.cellForItem(at: index) === cell)
                XCTAssertEqual(fixture.collection.indexPathsForSelectedItems, [index])
                XCTAssertEqual(fixture.collection.contentOffset.y, 20, accuracy: 0.5)
                XCTAssertEqual(fixture.layout.layoutAttributesForItem(at: index)?.frame, firstFrame)
                XCTAssertEqual(
                    fixture.layout.layoutAttributesForDecorationView(
                        ofKind: first.decorations[0].elementKind, at: index)?.frame, firstDecorationFrame)
                XCTAssertEqual(fixture.visible(ReplacementDecorationA.self).count, useB ? 1 : 2)
                XCTAssertEqual(fixture.visible(ReplacementDecorationB.self).count, useB ? 1 : 0)
                let expectedFrame = try XCTUnwrap(
                    fixture.layout.layoutAttributesForDecorationView(
                        ofKind: second.decorations[0].elementKind, at: IndexPath(item: 0, section: 1))
                ).frame
                let views: [UIView] =
                useB
                ? fixture.visible(ReplacementDecorationB.self)
                : fixture.visible(ReplacementDecorationA.self)
                XCTAssertTrue(
                    views.contains { $0.convert($0.bounds, to: fixture.collection) == expectedFrame })
                fixture.capture("multi-section-\(useB ? "a-b" : "a-a")", in: self)
            }
        }
    }

    func testRenderedCustomAndFrameworkDecorationsCoexist() async throws {
        for width in [CGFloat(240), 390, 768] {
            let fixture = DecorationRenderingFixture(width: width)
            defer { fixture.close() }
            let rawKind = "shared-card"
            fixture.layout.registerDecorationView(ManualDecorationView.self, forKind: rawKind)
            func section(_ useB: Bool) -> ListSection<Int> {
                ListSection(0) {
                    for index in 0..<12 {
                        Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                    }
                } layout: {
                    CustomLayout(layoutKey: 0) { _ in
                        let size = NSCollectionLayoutSize(
                            widthDimension: .fractionalWidth(1), heightDimension: .absolute(40))
                        let item = NSCollectionLayoutItem(layoutSize: size)
                        let result = NSCollectionLayoutSection(
                            group: .horizontal(layoutSize: size, subitems: [item]))
                        let decoration = NSCollectionLayoutDecorationItem.background(elementKind: rawKind)
                        decoration.zIndex = -2
                        result.decorationItems = [decoration]
                        return result
                    }.decorationItems { DecorationItemLayout(kind: rawKind, backgroundInsets: .init(20)) }
                } decorations: {
                    if useB {
                        SectionDecoration(ReplacementDecorationB.self, kind: rawKind)
                    } else {
                        SectionDecoration(ReplacementDecorationA.self, kind: rawKind)
                    }
                }
            }
            for useB in [false, true, false] {
                let value = section(useB)
                let summary = await fixture.adapter.apply(options: .init(transaction: .disabled)) { value }
                fixture.collection.layoutIfNeeded()
                XCTAssertTrue(summary.diagnosticsIssues.isEmpty)
                XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
                // 多个 decoration 的 item 索引由 UIKit 分配，不能都假定为 0。
                let rendered =
                (fixture.layout.layoutAttributesForElements(in: fixture.collection.bounds) ?? [])
                    .filter { $0.representedElementCategory == .decorationView }
                XCTAssertEqual(rendered.count, 2)
                let raw = try XCTUnwrap(rendered.first { $0.representedElementKind == rawKind })
                let typed = try XCTUnwrap(
                    rendered.first { $0.representedElementKind == value.decorations[0].elementKind })
                let queried = try XCTUnwrap(
                    fixture.layout.layoutAttributesForDecorationView(
                        ofKind: value.decorations[0].elementKind, at: typed.indexPath))
                XCTAssertEqual(queried.representedElementKind, typed.representedElementKind)
                XCTAssertEqual(queried.frame, typed.frame)
                let typedViews: [UIView] =
                useB
                ? fixture.visible(ReplacementDecorationB.self)
                : fixture.visible(ReplacementDecorationA.self)
                XCTAssertEqual(
                    try XCTUnwrap(typedViews.first).convert(typedViews[0].bounds, to: fixture.collection),
                    typed.frame)
                XCTAssertEqual(raw.zIndex, -2)
                XCTAssertEqual(typed.zIndex, -1)
                XCTAssertEqual(raw.frame.insetBy(dx: 20, dy: 20), typed.frame)
                XCTAssertEqual(
                    try XCTUnwrap(fixture.visible(ManualDecorationView.self).first).frame, raw.frame)
                XCTAssertEqual(fixture.visible(ManualDecorationView.self).count, 1)
                XCTAssertEqual(fixture.visible(ReplacementDecorationA.self).count, useB ? 0 : 1)
                XCTAssertEqual(fixture.visible(ReplacementDecorationB.self).count, useB ? 1 : 0)
                fixture.capture("custom-coexist-\(useB ? "b" : "a")", in: self)
            }
        }
    }

    func testRenderedTypedManualConflictRejectsApplyAndRecovers() async throws {
        let fixture = DecorationRenderingFixture(width: 390)
        defer { fixture.close() }
        let alias = "manual"
        let typed = SectionDecoration(ReplacementDecorationA.self, kind: card)
        fixture.layout.registerDecorationView(ManualDecorationView.self, forKind: "manual-green")
        func section(manualKind: String, both: Bool) -> ListSection<Int> {
            ListSection(0) {
                for index in 0..<12 {
                    Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).decorationItems {
                    DecorationItemLayout(kind: card)
                    if both { DecorationItemLayout(kind: alias, backgroundInsets: .init(20)) }
                }
            } decorations: {
                typed
                SectionDecoration(kind: alias, elementKind: manualKind)
            }
        }
        await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            section(manualKind: typed.elementKind, both: false)
        }
        fixture.collection.layoutIfNeeded()
        let original = try XCTUnwrap(fixture.visible(ReplacementDecorationA.self).first)
        let index = IndexPath(item: 0, section: 0)
        let cell = try XCTUnwrap(fixture.collection.cellForItem(at: index))
        let frame = try XCTUnwrap(fixture.layout.layoutAttributesForItem(at: index)).frame
        let rejected = await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            section(manualKind: typed.elementKind, both: true)
        }
        fixture.collection.layoutIfNeeded()
        XCTAssertTrue(
            rejected.diagnosticsIssues.contains {
                $0.message.contains("duplicate decoration elementKind")
            })
        XCTAssertTrue(fixture.visible(ReplacementDecorationA.self).first === original)
        XCTAssertTrue(fixture.collection.cellForItem(at: index) === cell)
        XCTAssertEqual(fixture.layout.layoutAttributesForItem(at: index)?.frame, frame)
        XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)  // apply 前拒绝，不进入 provider 回退。
        fixture.capture("typed-manual-rejected-preserves-layout", in: self)
        let recovered = await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            section(manualKind: "manual-green", both: true)
        }
        fixture.collection.layoutIfNeeded()
        XCTAssertTrue(recovered.diagnosticsIssues.isEmpty)
        XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
        XCTAssertEqual(fixture.visible(ReplacementDecorationA.self).count, 1)
        XCTAssertEqual(fixture.visible(ManualDecorationView.self).count, 1)
        XCTAssertEqual(fixture.layout.layoutAttributesForItem(at: index)?.frame, frame)
        let manualAttributes = try XCTUnwrap(
            (fixture.layout.layoutAttributesForElements(in: fixture.collection.bounds) ?? []).first {
                $0.representedElementKind == "manual-green"
            })
        XCTAssertEqual(fixture.visible(ManualDecorationView.self).first?.frame, manualAttributes.frame)
        fixture.capture("typed-manual-recovered", in: self)
        // 仅变更手动注册标识也必须触发布局失效，不依赖几何或 logicalKind 变化。
        fixture.layout.registerDecorationView(ReplacementDecorationB.self, forKind: "manual-orange")
        await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            section(manualKind: "manual-orange", both: true)
        }
        fixture.collection.layoutIfNeeded()
        XCTAssertTrue(fixture.visible(ManualDecorationView.self).isEmpty)
        XCTAssertEqual(fixture.visible(ReplacementDecorationB.self).count, 1)
        XCTAssertEqual(fixture.layout.layoutAttributesForItem(at: index)?.frame, frame)
        await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            section(manualKind: typed.elementKind, both: false)
        }
        fixture.collection.layoutIfNeeded()
        XCTAssertTrue(fixture.visible(ManualDecorationView.self).isEmpty)
        XCTAssertTrue(fixture.visible(ReplacementDecorationB.self).isEmpty)
        XCTAssertEqual(fixture.visible(ReplacementDecorationA.self).count, 1)
        let remaining =
        (fixture.layout.layoutAttributesForElements(in: fixture.collection.bounds) ?? [])
            .filter { $0.representedElementCategory == .decorationView }
        XCTAssertEqual(remaining.map(\.representedElementKind), [typed.elementKind])
        XCTAssertFalse(remaining.contains { $0.representedElementKind == "manual-orange" })
        XCTAssertEqual(
            fixture.visible(ReplacementDecorationA.self).first?.frame, remaining.first?.frame)
        XCTAssertEqual(fixture.layout.layoutAttributesForItem(at: index)?.frame, frame)
        XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
        fixture.capture("typed-manual-removed", in: self)
    }
}

@MainActor private final class DecorationRenderingFixture {
    let window: UIWindow
    let collection: UICollectionView
    let adapter: CollectionListAdapter<Int>
    let layout: UICollectionViewCompositionalLayout
    init(width: CGFloat) {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        collection = UICollectionView(
            frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        controller.view.addSubview(collection)
        adapter = CollectionListAdapter<Int>(collectionView: collection)
        layout = adapter.makeCompositionalLayout()
        collection.collectionViewLayout = layout
    }
    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
    func visible<T: UIView>(_ type: T.Type) -> [T] {
        func descendants(_ view: UIView) -> [UIView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        return descendants(collection).compactMap { $0 as? T }.filter {
            !$0.isHidden && $0.alpha > 0 && $0.window === window
            && $0.convert($0.bounds, to: collection).intersects(collection.bounds)
        }
    }
    func captureCollection(_ name: String, in test: XCTestCase) {
        let image = UIGraphicsImageRenderer(bounds: collection.bounds).image {
            collection.layer.render(in: $0.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
    func capture(_ name: String, in test: XCTestCase) {
        guard window.bounds.width == 390 else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image {
            window.layer.render(in: $0.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
private final class ManualDecorationView: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension CompleteSectionLayoutTests {
    func testRenderedEnvironmentDecorationSwitchesOnContainerWidthAlone() async throws {
        let fixture = DecorationRenderingFixture(width: 768)
        defer { fixture.close() }
        fixture.collection.frame.size.width = 240
        let logicalKind = card
        let registration = SectionDecoration(ReplacementDecorationA.self, kind: logicalKind)
        let rowCount = 20
        let itemHeight: CGFloat = 40
        let sectionInset: CGFloat = 8
        let decorationInset: CGFloat = 12
        var observedWidths: [CGFloat] = []
        let section = ListSection(0) {
            for index in 0..<rowCount {
                Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
            }
        } layout: {
            EnvironmentLayout(layoutKey: "constant-environment") { environment in
                let width = environment.container.effectiveContentSize.width
                let _ = observedWidths.append(width)
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(itemHeight)).trackSpacing(0).lineSpacing(0).sectionInsets(
                    .init(sectionInset)
                )
                    .decorationItems {
                        if width >= 500 {
                            DecorationItemLayout(kind: logicalKind, backgroundInsets: .init(decorationInset), zIndex: -3)
                        }
                    }
            }
        } decorations: {
            registration
        }.selectionMode(.single)
        var applyCount = 0
        await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            let _ = { applyCount += 1 }()
            section
        }
        fixture.collection.layoutIfNeeded()
        let index = IndexPath(item: 0, section: 0)
        fixture.collection.selectItem(at: index, animated: false, scrollPosition: [])
        fixture.collection.setContentOffset(CGPoint(x: 0, y: 20), animated: false)
        fixture.collection.layoutIfNeeded()
        let generation = fixture.adapter.layoutInvalidationGeneration
        XCTAssertTrue(fixture.visible(ReplacementDecorationA.self).isEmpty)
        var previousCount = observedWidths.count
        var firstWideAttributesFrame: CGRect?
        var firstWideViewFrame: CGRect?
        var wideVisitCount = 0
        // 不再 apply、不更换布局或 selector ID，也不手动 invalidateLayout。
        for (step, width) in [CGFloat(390), 768, 600, 390, 768, 240].enumerated() {
            fixture.collection.frame.size.width = width
            fixture.collection.layoutIfNeeded()
            XCTAssertGreaterThan(observedWidths.count, previousCount)
            XCTAssertEqual(try XCTUnwrap(observedWidths.last), width, accuracy: 0.5)
            previousCount = observedWidths.count
            XCTAssertEqual(applyCount, 1)
            XCTAssertEqual(fixture.adapter.layoutInvalidationGeneration, generation)
            XCTAssertTrue(fixture.collection.collectionViewLayout === fixture.layout)
            XCTAssertEqual(fixture.collection.indexPathsForSelectedItems, [index])
            XCTAssertEqual(fixture.collection.contentOffset.y, 20, accuracy: 0.5)
            let cellAttributes = try XCTUnwrap(fixture.layout.layoutAttributesForItem(at: index))
            XCTAssertEqual(cellAttributes.frame.width, width - 2 * sectionInset, accuracy: 0.5)
            let cell = try XCTUnwrap(fixture.collection.cellForItem(at: index))
            XCTAssertEqual(cell.convert(cell.bounds, to: fixture.collection), cellAttributes.frame)
            let decorations =
            (fixture.layout.layoutAttributesForElements(in: fixture.collection.bounds) ?? [])
                .filter { $0.representedElementCategory == .decorationView }
            if width >= 500 {
                XCTAssertEqual(decorations.count, 1)
                let attributes = try XCTUnwrap(decorations.first)
                XCTAssertEqual(attributes.representedElementKind, registration.elementKind)
                XCTAssertEqual(attributes.zIndex, -3)
                XCTAssertEqual(fixture.visible(ReplacementDecorationA.self).count, 1)
                let view = try XCTUnwrap(fixture.visible(ReplacementDecorationA.self).first)
                let viewFrame = view.convert(view.bounds, to: fixture.collection)
                // 预期值来自固定行高、零间距和声明的 inset，不从测量到的 attributes 推导。
                let sectionHeight = CGFloat(rowCount) * itemHeight + 2 * sectionInset
                let expectedFrame = CGRect(
                    x: decorationInset, y: decorationInset,
                    width: width - 2 * decorationInset,
                    height: sectionHeight - 2 * decorationInset)
                XCTAssertEqual(attributes.frame, expectedFrame)
                XCTAssertEqual(viewFrame, expectedFrame)
                XCTAssertEqual(attributes.frame.minX, 12, accuracy: 0.5)
                XCTAssertEqual(width - attributes.frame.maxX, 12, accuracy: 0.5)
                XCTAssertEqual(attributes.frame.minY, 12, accuracy: 0.5)
                XCTAssertEqual(sectionHeight - attributes.frame.maxY, 12, accuracy: 0.5)
                XCTAssertEqual(attributes.frame.width, width == 768 ? 744 : 576, accuracy: 0.5)
                if width == 768 {
                    wideVisitCount += 1
                    if let firstWideAttributesFrame, let firstWideViewFrame {
                        XCTAssertEqual(attributes.frame, firstWideAttributesFrame)
                        XCTAssertEqual(viewFrame, firstWideViewFrame)
                    } else {
                        firstWideAttributesFrame = attributes.frame
                        firstWideViewFrame = viewFrame
                    }
                }
            } else {
                XCTAssertTrue(decorations.isEmpty)
                XCTAssertTrue(fixture.visible(ReplacementDecorationA.self).isEmpty)
            }
            XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
            fixture.captureCollection("environment-width-\(step)-\(Int(width))", in: self)
        }
        XCTAssertEqual(wideVisitCount, 2)
    }

    func testRenderedCustomContextReadsUpdatedManualElementKind() async throws {
        for width in [CGFloat(240), 390, 768] {
            let fixture = DecorationRenderingFixture(width: width)
            defer { fixture.close() }
            let logicalKind = "provider-manual"
            let greenKind = "context-manual-green"
            let orangeKind = "context-manual-orange"
            fixture.layout.registerDecorationView(ManualDecorationView.self, forKind: greenKind)
            fixture.layout.registerDecorationView(ReplacementDecorationB.self, forKind: orangeKind)
            var observedKinds: [String] = []
            // 整个切换过程复用同一个 provider；闭包只捕获 logicalKind，不捕获待更新的 kind。
            let custom: ListCustomLayout<Int> = CustomLayout(layoutKey: "constant-custom", sectionInsets: .init(8)) { context in
                guard let kind = context.decorationElementKind(for: logicalKind) else {
                    XCTFail("Missing manual decoration mapping")
                    return ListSectionLayout.gridConfiguration(
                        GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                    ).makeCompositionalSection(
                        environment: context.environment, itemSupplementaries: [])
                }
                observedKinds.append(kind)
                let size = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .absolute(40))
                let item = NSCollectionLayoutItem(layoutSize: size)
                let result = NSCollectionLayoutSection(
                    group: .horizontal(layoutSize: size, subitems: [item]))
                result.contentInsets = context.sectionInsets!.directionalEdgeInsets
                let decoration = NSCollectionLayoutDecorationItem.background(elementKind: kind)
                decoration.contentInsets = .init(top: 4, leading: 4, bottom: 4, trailing: 4)
                decoration.zIndex = -3
                result.decorationItems = [decoration]
                return result
            }.decorationItems(.none)
            func section(_ elementKind: String) -> ListSection<Int> {
                ListSection(0) {
                    for index in 0..<20 {
                        Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                    }
                } layout: {
                    custom
                } decorations: {
                    SectionDecoration(kind: logicalKind, elementKind: elementKind)
                }.selectionMode(.single)
            }
            let original = section(greenKind)
            await fixture.adapter.apply(options: .init(transaction: .disabled)) { original }
            fixture.collection.layoutIfNeeded()
            let index = IndexPath(item: 0, section: 0)
            fixture.collection.selectItem(at: index, animated: false, scrollPosition: [])
            fixture.collection.setContentOffset(CGPoint(x: 0, y: 20), animated: false)
            fixture.collection.layoutIfNeeded()
            let cell = try XCTUnwrap(fixture.collection.cellForItem(at: index))
            let cellFrame = try XCTUnwrap(fixture.layout.layoutAttributesForItem(at: index)).frame
            let decorationFrame = try XCTUnwrap(fixture.visible(ManualDecorationView.self).first).frame
            XCTAssertEqual(observedKinds.last, greenKind)
            XCTAssertEqual(fixture.visible(ManualDecorationView.self).count, 1)
            for kind in [orangeKind, greenKind] {
                let value = section(kind)
                XCTAssertEqual(value.layoutSource, original.layoutSource)
                XCTAssertEqual(value.decorations[0].kind, original.decorations[0].kind)
                let count = observedKinds.count
                let generation = fixture.adapter.layoutInvalidationGeneration
                let summary = await fixture.adapter.apply(options: .init(transaction: .disabled)) { value }
                fixture.collection.layoutIfNeeded()
                XCTAssertTrue(summary.diagnosticsIssues.isEmpty)
                XCTAssertTrue(fixture.adapter.lastLayoutDiagnostics.isEmpty)
                XCTAssertGreaterThan(fixture.adapter.layoutInvalidationGeneration, generation)
                XCTAssertGreaterThan(observedKinds.count, count)
                XCTAssertTrue(observedKinds.dropFirst(count).allSatisfy { $0 == kind })
                XCTAssertTrue(fixture.collection.collectionViewLayout === fixture.layout)
                XCTAssertTrue(fixture.collection.cellForItem(at: index) === cell)
                XCTAssertEqual(fixture.collection.indexPathsForSelectedItems, [index])
                XCTAssertEqual(fixture.collection.contentOffset.y, 20, accuracy: 0.5)
                XCTAssertEqual(fixture.layout.layoutAttributesForItem(at: index)?.frame, cellFrame)
                let attributes =
                (fixture.layout.layoutAttributesForElements(in: fixture.collection.bounds) ?? [])
                    .filter { $0.representedElementCategory == .decorationView }
                XCTAssertEqual(attributes.map(\.representedElementKind), [kind])
                XCTAssertEqual(attributes.first?.zIndex, -3)
                XCTAssertEqual(attributes.first?.frame, decorationFrame)
                let isOrange = kind == orangeKind
                XCTAssertEqual(fixture.visible(ManualDecorationView.self).count, isOrange ? 0 : 1)
                XCTAssertEqual(fixture.visible(ReplacementDecorationB.self).count, isOrange ? 1 : 0)
                let views: [UIView] =
                isOrange
                ? fixture.visible(ReplacementDecorationB.self)
                : fixture.visible(ManualDecorationView.self)
                let view = try XCTUnwrap(views.first)
                XCTAssertEqual(view.convert(view.bounds, to: fixture.collection), decorationFrame)
                fixture.capture("custom-context-\(isOrange ? "orange" : "green")", in: self)
            }
        }
    }
}
