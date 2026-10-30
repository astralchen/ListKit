import UIKit
import XCTest

@testable import ListKit

@MainActor final class SupplementaryIdentityReplacementTests: XCTestCase {
    func testSameKindBoundaryBusinessIDReplacementPreservesSelectionAndScroll() async throws {
        try await checkReplacement(itemSupplementary: false, changesType: false)
    }

    func testSameKindBoundaryViewTypeReplacementPreservesSelectionAndScroll() async throws {
        try await checkReplacement(itemSupplementary: false, changesType: true)
    }

    func testSameKindItemBusinessIDReplacementPreservesSelectionAndScroll() async throws {
        try await checkReplacement(itemSupplementary: true, changesType: false)
    }

    func testSameKindItemViewTypeReplacementPreservesSelectionAndScroll() async throws {
        try await checkReplacement(itemSupplementary: true, changesType: true)
    }

    func testReplacementReloadIsScopedAndDoesNotReloadInsertedOrDeletedSections() async throws {
        let fixture = ReplacementFixture()
        defer { fixture.close() }
        func section(_ id: Int, version: Int) -> ListSection<Int> {
            ListSection(id) {
                Row(0, model: id, cell: UICollectionViewCell.self) { _, _, _ in }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0).boundarySupplementaries {
                    for kind in ["title", "toolbar"] {
                        BoundarySupplementaryLayout(
                            kind: kind, size: .init(width: .fractionalWidth(1), height: .absolute(20)),
                            alignment: kind == "title" ? .top : .bottom)
                    }
                }
            } supplementaries: {
                for kind in ["title", "toolbar"] {
                    SectionSupplementary(ReplacementA.self, kind: kind, id: version) { view, _ in
                        view.value = "\(id):\(version)"
                    }.refreshID(0).refresh(when: .never)
                }
            }
        }
        await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            section(0, version: 0)
            section(1, version: 0)
        }
        fixture.collection.layoutIfNeeded()
        let unchangedIndex = IndexPath(item: 0, section: 1)
        let unchanged = try XCTUnwrap(fixture.collection.supplementaryView(forElementKind: "title", at: unchangedIndex))
        let replacement = await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            section(0, version: 1)
            section(1, version: 0)
            section(2, version: 0)
        }
        fixture.collection.layoutIfNeeded()
        // Two replaced kinds in section 0 must coalesce to one reload; section 2 is an insertion.
        XCTAssertEqual(replacement.refreshMetrics.reloadedSectionCount, 1)
        XCTAssertEqual(replacement.insertedSectionCount, 1)
        XCTAssertTrue(fixture.collection.supplementaryView(forElementKind: "title", at: unchangedIndex) === unchanged)
        for kind in ["title", "toolbar"] {
            XCTAssertEqual(
                (fixture.collection.supplementaryView(forElementKind: kind, at: IndexPath(item: 0, section: 0)) as? ReplacementA)?.value,
                "0:1")
        }
        let deletion = await fixture.adapter.apply(options: .init(transaction: .disabled)) {
            section(1, version: 0)
            section(2, version: 0)
        }
        fixture.collection.layoutIfNeeded()
        XCTAssertEqual(deletion.refreshMetrics.reloadedSectionCount, 0)
        XCTAssertEqual(deletion.deletedSectionCount, 1)
        XCTAssertEqual(
            (fixture.collection.supplementaryView(forElementKind: "title", at: IndexPath(item: 0, section: 0)) as? ReplacementA)?.value,
            "1:0")
    }

    private func checkReplacement(itemSupplementary: Bool, changesType: Bool) async throws {
        for animated in [false, true] {
            let fixture = ReplacementFixture()
            defer { fixture.close() }
            let collection = fixture.collection
            let adapter = fixture.adapter
            let transaction = ListTransaction(animation: animated ? .enabled : .disabled)
            func section(_ stage: Int, version: Int, trigger: ListRefreshTrigger) -> ListSection<Int> {
                let contentID = changesType || stage == 0 ? "first" : "second"
                return ListSection(0) {
                    for index in 0..<30 {
                        Row(index, model: index, cell: UICollectionViewCell.self) { _, _, _ in }
                            .refresh(.init(trigger: .everyApply, scope: .allMatching, action: .reconfigure(layout: .none)))
                    }
                } layout: {
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(40)).trackSpacing(0).lineSpacing(0)
                        .boundarySupplementaries {
                            if !itemSupplementary {
                                BoundarySupplementaryLayout(
                                    kind: "shared", size: .init(width: .fractionalWidth(1), height: .absolute(36)),
                                    alignment: .top).pinToVisibleBounds()
                            }
                        }
                        .itemSupplementaries {
                            if itemSupplementary {
                                ItemSupplementaryLayout(
                                    kind: "shared", size: .init(width: .absolute(20), height: .absolute(20)),
                                    itemAnchor: .topTrailing)
                            }
                        }
                } supplementaries: {
                    if changesType && stage > 0 {
                        SectionSupplementary(ReplacementB.self, kind: "shared", id: contentID) { view, _ in
                            view.value = "\(stage):\(version)"
                        }.refreshID(version).refresh(when: trigger)
                    } else {
                        SectionSupplementary(ReplacementA.self, kind: "shared", id: contentID) { view, _ in
                            view.value = "\(stage):\(version)"
                        }.refreshID(version).refresh(when: trigger)
                    }
                }.selectionMode(.single)
            }

            await adapter.apply(options: .init(transaction: .disabled)) {
                section(0, version: 0, trigger: .never)
            }
            collection.layoutIfNeeded()
            let selected = IndexPath(item: 4, section: 0)
            collection.selectItem(at: selected, animated: false, scrollPosition: [])
            collection.setContentOffset(CGPoint(x: 0, y: 80), animated: false)
            collection.layoutIfNeeded()
            let target = IndexPath(item: itemSupplementary ? 4 : 0, section: 0)
            let original = try XCTUnwrap(collection.supplementaryView(forElementKind: "shared", at: target) as? ReplacementA)
            XCTAssertEqual(original.value, "0:0")
            let offset = collection.contentOffset
            let frame = try XCTUnwrap(collection.collectionViewLayout.layoutAttributesForItem(at: selected)).frame

            // A new identity must replace old content even with the same refreshID and a `.never` policy.
            let replacement = await adapter.apply(options: .init(transaction: transaction)) {
                section(1, version: 0, trigger: .never)
            }
            collection.layoutIfNeeded()
            let replaced = try XCTUnwrap(collection.supplementaryView(forElementKind: "shared", at: target) as? ReplacementView)
            XCTAssertEqual(replaced.value, "1:0")
            XCTAssertEqual(replaced is ReplacementB, changesType)
            if changesType { XCTAssertFalse(replaced === original) }
            XCTAssertEqual(replacement.refreshMetrics.reloadedSectionCount, 1)
            XCTAssertEqual(replacement.refreshMetrics.snapshotReconfiguredRowCount, 0)
            XCTAssertEqual(replacement.refreshMetrics.visibleReconfiguredSupplementaryCount, 0)
            XCTAssertEqual(replacement.supplementaryRefreshIDChangedCount, 0)
            XCTAssertEqual(collection.indexPathsForSelectedItems, [selected])
            XCTAssertEqual(collection.contentOffset.y, offset.y, accuracy: 1)
            XCTAssertEqual(collection.collectionViewLayout.layoutAttributesForItem(at: selected)?.frame, frame)

            let policyChange = await adapter.apply(options: .init(transaction: transaction)) {
                section(1, version: 0, trigger: .refreshIDChanges)
            }
            collection.layoutIfNeeded()
            XCTAssertEqual(policyChange.refreshMetrics.reloadedSectionCount, 0)
            XCTAssertEqual(policyChange.refreshMetrics.visibleReconfiguredSupplementaryCount, 0)
            XCTAssertTrue(collection.supplementaryView(forElementKind: "shared", at: target) === replaced)

            // With identity stable, refreshID changes must reconfigure the existing views, not reload the section.
            let generation = adapter.layoutInvalidationGeneration
            let refresh = await adapter.apply(options: .init(transaction: transaction)) {
                section(1, version: 1, trigger: .refreshIDChanges)
            }
            collection.layoutIfNeeded()
            XCTAssertTrue(collection.supplementaryView(forElementKind: "shared", at: target) === replaced)
            XCTAssertEqual(replaced.value, "1:1")
            XCTAssertEqual(refresh.refreshMetrics.reloadedSectionCount, 0)
            XCTAssertGreaterThan(refresh.refreshMetrics.visibleReconfiguredSupplementaryCount, 0)
            XCTAssertEqual(refresh.supplementaryRefreshIDChangedCount, 1)
            XCTAssertEqual(adapter.layoutInvalidationGeneration, generation)
            XCTAssertEqual(collection.indexPathsForSelectedItems, [selected])
            XCTAssertEqual(collection.contentOffset.y, offset.y, accuracy: 1)
            XCTAssertEqual(collection.collectionViewLayout.layoutAttributesForItem(at: selected)?.frame, frame)
            XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
        }
    }
}

@MainActor private final class ReplacementFixture {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
    let collection: UICollectionView
    let adapter: CollectionListAdapter<Int>

    init() {
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        collection = UICollectionView(frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        controller.view.addSubview(collection)
        adapter = CollectionListAdapter<Int>(collectionView: collection)
        collection.collectionViewLayout = adapter.makeCompositionalLayout()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}

private class ReplacementView: UICollectionReusableView { var value = "" }
private final class ReplacementA: ReplacementView {}
private final class ReplacementB: ReplacementView {}
