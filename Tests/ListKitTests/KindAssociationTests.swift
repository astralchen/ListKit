import UIKit
import XCTest

@testable import ListKit

@MainActor final class KindAssociationTests: XCTestCase {
    func testExplicitKindsAndWrappersPreserveIdentityAndRefreshMetadata() {
        // Explicit kinds are passed through verbatim, without generated defaults.
        for kind in ["title", "app.title", UICollectionView.elementKindSectionHeader] {
            let original = Supplementary(kind, id: "title", view: UICollectionReusableView.self) { _, _ in }
                .refreshID(7)
            let direct: ListSectionSupplementary<Int> = SectionSupplementary(
                UICollectionReusableView.self, kind: kind, id: "title"
            ) { _, _ in }.refreshID(7)
            let wrapped: ListSectionSupplementary<Int> = SectionSupplementary(original)
            let expected = original.eraseToAnySupplementary(sectionID: 42)
            for migrated in [direct, wrapped] {
                let actual = migrated.makeSupplementary(sectionID: 42)
                XCTAssertEqual(actual.kind, kind)
                XCTAssertEqual(actual.identity, expected.identity)
                XCTAssertEqual(actual.refreshID, expected.refreshID)
                XCTAssertEqual(actual.refreshRule, expected.refreshRule)
            }
        }
    }

    func testKindsRemainDistinctWithoutImplicitPrefixing() {
        let kinds = ["title", "app.title"]
        let section = ListSection(0) {} layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                for kind in kinds {
                    BoundarySupplementaryLayout(
                        kind: kind,
                        size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                        alignment: .top)
                }
            }
        } supplementaries: {
            for kind in kinds {
                SectionSupplementary(UICollectionReusableView.self, kind: kind, id: "same-content-id") { _, _ in }
            }
        }
        XCTAssertTrue(ListDiagnostics.validate([section]).isEmpty)
        XCTAssertEqual(section.resolvedForTesting().boundarySupplementaryItems.map(\.elementKind), kinds)
        XCTAssertNotEqual(section.supplementaries[0].identity, section.supplementaries[1].identity)
    }

    func testSharedKindRoutesProviderContentBySection() throws {
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        var receivedSections: [Int] = []
        let sections = [1, 2].map { sectionID in
            ListSection(sectionID) {} layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: "shared", size: .init(width: .fractionalWidth(1), height: .absolute(30)),
                        alignment: .top)
                }
            } supplementaries: {
                SectionSupplementary(
                    ProviderSupplementary("shared", id: "title", view: UICollectionReusableView.self) { _, _, _ in
                        receivedSections.append(sectionID)
                        return UICollectionReusableView()
                    })
            }
        }
        XCTAssertTrue(ListDiagnostics.validate(sections).isEmpty)
        adapter.apply(sections, transaction: .disabled)
        let source = try XCTUnwrap(collection.dataSource as? UICollectionViewDiffableDataSource<AnyListID, AnyListIdentity>)
        for index in 0..<2 {
            let layout = try XCTUnwrap(adapter.makeCompositionalSection(for: index, environment: TestLayoutEnvironment()))
            XCTAssertEqual(layout.boundarySupplementaryItems.first?.elementKind, "shared")
            XCTAssertNotNil(source.supplementaryViewProvider?(collection, "shared", IndexPath(item: 0, section: index)))
        }
        XCTAssertEqual(receivedSections, [1, 2])
    }

    func testDecorationUsesLogicalKindAndViewTypeForActualRegistration() {
        for logicalKind in ["card", "app.card"] {
            let declaration = SectionDecoration(UICollectionReusableView.self, kind: logicalKind)
            let expected = "ListKit.TypedDecoration.\(logicalKind.utf8.count):\(logicalKind):\(NSStringFromClass(UICollectionReusableView.self))"
            let section = ListSection(0) {} layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0).decorationItems {
                    DecorationItemLayout(kind: logicalKind)
                }
            } decorations: {
                declaration
            }
            XCTAssertEqual(declaration.elementKind, expected)
            XCTAssertEqual(section.resolvedForTesting().decorationItems.first?.elementKind, expected)
        }
        let manual = SectionDecoration(kind: "card", elementKind: "external.registration")
        XCTAssertEqual(manual.elementKind, "external.registration")
    }

    func testRemovingLegacyPrefixesReplacesViewsAndSubsequentRefreshReusesNewHeader() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        controller.view.addSubview(collection)
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        let layout = adapter.makeCompositionalLayout()
        collection.collectionViewLayout = layout

        func section(headerKind: String, decorationKind: String, version: Int, present: Bool = true) -> ListSection<Int> {
            ListSection(0) {
                for index in 0..<30 {
                    Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: headerKind, size: .init(width: .fractionalWidth(1), height: .absolute(36)),
                        alignment: .top).pinToVisibleBounds().whenContentExists()
                }.decorationItems {
                    DecorationItemLayout(kind: decorationKind).whenContentExists()
                }
            } supplementaries: {
                if present {
                    SectionSupplementary(KindMigrationHeader.self, kind: headerKind, id: "title") { view, _ in
                        view.version = version
                    }.refreshID(version)
                }
            } decorations: {
                if present { SectionDecoration(KindMigrationDecoration.self, kind: decorationKind) }
            }.selectionMode(.single)
        }
        func visibleDecorations() -> [KindMigrationDecoration] {
            func descendants(_ view: UIView) -> [UIView] {
                view.subviews.flatMap { [$0] + descendants($0) }
            }
            return descendants(collection).compactMap { $0 as? KindMigrationDecoration }.filter {
                !$0.isHidden && $0.window === window && $0.convert($0.bounds, to: collection).intersects(collection.bounds)
            }
        }
        let legacy = section(headerKind: "ListKit.Supplementary.title", decorationKind: "ListKit.Decoration.card", version: 1)
        let migrated = section(headerKind: "title", decorationKind: "card", version: 1)
        XCTAssertNotEqual(legacy.supplementaries[0].identity, migrated.supplementaries[0].identity)
        XCTAssertNotEqual(legacy.decorations[0].elementKind, migrated.decorations[0].elementKind)
        await adapter.apply(options: .init(transaction: .disabled)) { legacy }
        collection.layoutIfNeeded()
        let index = IndexPath(item: 0, section: 0)
        let selected = IndexPath(item: 3, section: 0)
        collection.selectItem(at: selected, animated: false, scrollPosition: [])
        collection.setContentOffset(CGPoint(x: 0, y: 80), animated: false)
        collection.layoutIfNeeded()
        let oldHeader = try XCTUnwrap(collection.supplementaryView(forElementKind: legacy.supplementaries[0].kind, at: index))
        let oldDecoration = try XCTUnwrap(visibleDecorations().first)
        let offset = collection.contentOffset
        let frame = try XCTUnwrap(layout.layoutAttributesForItem(at: selected)).frame
        let generation = adapter.layoutInvalidationGeneration

        await adapter.apply(options: .init(transaction: .disabled)) { migrated }
        collection.layoutIfNeeded()
        let header = try XCTUnwrap(collection.supplementaryView(forElementKind: "title", at: index) as? KindMigrationHeader)
        XCTAssertFalse(header === oldHeader)
        XCTAssertNil(collection.supplementaryView(forElementKind: legacy.supplementaries[0].kind, at: index))
        XCTAssertNil(layout.layoutAttributesForSupplementaryView(ofKind: legacy.supplementaries[0].kind, at: index))
        XCTAssertFalse(try XCTUnwrap(visibleDecorations().first) === oldDecoration)
        XCTAssertEqual(visibleDecorations().count, 1)
        XCTAssertNil(layout.layoutAttributesForDecorationView(ofKind: legacy.decorations[0].elementKind, at: index))
        XCTAssertNotNil(layout.layoutAttributesForDecorationView(ofKind: migrated.decorations[0].elementKind, at: index))
        XCTAssertGreaterThan(adapter.layoutInvalidationGeneration, generation)
        XCTAssertEqual(collection.indexPathsForSelectedItems, [selected])
        XCTAssertEqual(collection.contentOffset.y, offset.y, accuracy: 1)
        XCTAssertEqual(layout.layoutAttributesForItem(at: selected)?.frame, frame)

        let migratedGeneration = adapter.layoutInvalidationGeneration
        let refreshed = await adapter.apply(options: .init(transaction: .disabled)) {
            section(headerKind: "title", decorationKind: "card", version: 2)
        }
        collection.layoutIfNeeded()
        XCTAssertTrue(collection.supplementaryView(forElementKind: "title", at: index) === header)
        XCTAssertEqual(header.version, 2)
        XCTAssertEqual(refreshed.supplementaryRefreshIDChangedCount, 1)
        XCTAssertEqual(adapter.layoutInvalidationGeneration, migratedGeneration)

        await adapter.apply(options: .init(transaction: .disabled)) {
            section(headerKind: "title", decorationKind: "card", version: 2, present: false)
        }
        collection.layoutIfNeeded()
        XCTAssertNil(collection.supplementaryView(forElementKind: "title", at: index))
        XCTAssertTrue(visibleDecorations().isEmpty)
        await adapter.apply(options: .init(transaction: .disabled)) { migrated }
        collection.layoutIfNeeded()
        XCTAssertNotNil(collection.supplementaryView(forElementKind: "title", at: index))
        XCTAssertEqual(visibleDecorations().count, 1)
        XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
    }
}

private final class KindMigrationHeader: UICollectionReusableView {
    var version = 0
}

private final class KindMigrationDecoration: UICollectionReusableView {}
