import ListKit
import UIKit

final class TestLayoutContainer: NSObject, NSCollectionLayoutContainer {
    let contentSize: CGSize
    init(contentSize: CGSize) { self.contentSize = contentSize }
    var effectiveContentSize: CGSize { contentSize }
    var contentInsets: NSDirectionalEdgeInsets { .zero }
    var effectiveContentInsets: NSDirectionalEdgeInsets { .zero }
}
final class TestLayoutEnvironment: NSObject, NSCollectionLayoutEnvironment {
    var container: any NSCollectionLayoutContainer = TestLayoutContainer(
        contentSize: CGSize(width: 390, height: 800))
    var traitCollection: UITraitCollection = UITraitCollection()
}

extension ListSection {
    var declaredLayout: ListSectionLayout? {
        guard case .builtIn(let value) = layoutSource else { return nil }
        return value
    }
    @MainActor func resolvedForTesting() -> NSCollectionLayoutSection {
        let collection = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<SectionID>(collectionView: collection)
        adapter.apply([self], transaction: .disabled)
        return adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment())!
    }
}
