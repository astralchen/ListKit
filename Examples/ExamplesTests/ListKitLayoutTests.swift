import Testing
import UIKit
import ListKit

@MainActor
struct ListKitLayoutTests {
    @Test func listLayoutDoesNotCreateHorizontalOrthogonalScrolling() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: "A", cell: UICollectionViewCell.self) { _, _, _ in }
            } layout: {
                ListLayout(itemHeight: .absolute(44))
            }
        }

        let section = adapter.makeCompositionalSection(for: 0)

        #expect(section?.orthogonalScrollingBehavior == UICollectionLayoutSectionOrthogonalScrollingBehavior.none)
    }

    @Test func horizontalLayoutCreatesHorizontalOrthogonalScrolling() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: "A", cell: UICollectionViewCell.self) { _, _, _ in }
            } layout: {
                HorizontalLayout(itemWidth: .absolute(92), itemHeight: .absolute(112))
            }
        }

        let section = adapter.makeCompositionalSection(for: 0)

        #expect(section?.orthogonalScrollingBehavior == .continuous)
    }

    @Test func horizontalLayoutSupportsPagingBehavior() {
        let section = ListSection(0) {
            Row(1, model: "A", cell: UICollectionViewCell.self) { _, _, _ in }
        } layout: {
            HorizontalLayout(scrollingBehavior: .groupPagingCentered)
        }

        #expect(section.makeCompositionalLayoutSection().orthogonalScrollingBehavior == .groupPagingCentered)
    }

    @Test func disclosureGroupBuildsHierarchicalRows() {
        let section = ListSection(0) {
            DisclosureGroup(
                Row("parent", model: "Parent", cell: UICollectionViewListCell.self) { _, _, _ in }
                    .outlineDisclosure(),
                isExpanded: true
            ) {
                Row("child", model: "Child", cell: UICollectionViewListCell.self) { _, _, _ in }
            }
        } layout: {
            UIKitListLayout(appearance: .insetGrouped)
        }

        #expect(section.hasOutlineHierarchy)
        #expect(section.rows.count == 2)
        #expect(section.outlineRoots.first?.children.count == 1)
        #expect(section.outlineRoots.first?.isExpanded == true)
        #expect(section.rows.first?.showsOutlineDisclosure == true)
        #expect(section.sectionLayout == .uiKitListConfiguration(.init(appearance: .insetGrouped)))
    }

    @Test func hierarchicalIndexTitleAlwaysMapsToAnAppliedItem() async {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = await adapter.apply(
            options: .init(animatingDifferences: false, applicationMode: .reloadData)
        ) {
            ListSection(0) {
                DisclosureGroup(
                    Row("parent", model: "Parent", cell: UICollectionViewListCell.self) { _, _, _ in }
                        .outlineDisclosure(),
                    isExpanded: true
                ) {
                    Row("child", model: "Child", cell: UICollectionViewListCell.self) { _, _, _ in }
                }
            } layout: {
                UIKitListLayout(appearance: .insetGrouped)
            }
            .indexTitle("A")
        }

        #expect(adapter.indexTitles(for: collectionView) == ["A"])
        let indexPath = adapter.collectionView(collectionView, indexPathForIndexTitle: "A", at: 0)
        #expect(indexPath == IndexPath(item: 0, section: 0))
        #expect(adapter.rowIdentifier(at: indexPath, as: String.self) == "parent")
    }

    @Test func gridLayoutDoesNotCreateHorizontalOrthogonalScrolling() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: "A", cell: UICollectionViewCell.self) { _, _, _ in }
            } layout: {
                GridLayout(columns: 2, itemHeight: .absolute(86))
            }
        }

        let section = adapter.makeCompositionalSection(for: 0)

        #expect(section?.orthogonalScrollingBehavior == UICollectionLayoutSectionOrthogonalScrollingBehavior.none)
    }
}
