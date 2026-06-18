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
