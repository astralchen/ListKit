import Testing
import UIKit
@testable import Examples

@MainActor
struct ScrollEdgeEffectTests {
    @Test func demoScrollViewsHideSystemScrollEdgeEffects() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

        collectionView.configureDemoScrollEdgeEffects()

        if #available(iOS 26.0, *) {
            #expect(collectionView.topEdgeEffect.isHidden)
            #expect(collectionView.leftEdgeEffect.isHidden)
            #expect(collectionView.bottomEdgeEffect.isHidden)
            #expect(collectionView.rightEdgeEffect.isHidden)
        }
    }
}
