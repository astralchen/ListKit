import UIKit

/// 保存业务物理边距，并计算 UIKit 镜像轨道需要的临时边距。
@MainActor
final class CollectionVerticalIndicatorInsets {
    private weak var collectionView: UICollectionView?
    private var adjustment: (requested: UIEdgeInsets, applied: UIEdgeInsets)?
    var isEnabled = true
    var isExplicitlyRightToLeft = false

    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
    }

    func requested(in collection: UICollectionView) -> UIEdgeInsets {
        var insets = collection.verticalScrollIndicatorInsets
        if collectionView === collection, let adjustment {
            if insets.left == adjustment.applied.left { insets.left = adjustment.requested.left }
            if insets.right == adjustment.applied.right { insets.right = adjustment.requested.right }
        }
        return insets
    }

    func setRequested(_ insets: UIEdgeInsets, in collection: UICollectionView) {
        adjustment = nil
        collection.verticalScrollIndicatorInsets = insets
    }

    func update(in collection: UICollectionView, direction: UICollectionView.ScrollDirection) {
        guard collectionView === collection, isEnabled, isExplicitlyRightToLeft,
              #available(iOS 26, *), let window = collection.window, direction == .vertical,
              collection.effectiveUserInterfaceLayoutDirection == .rightToLeft,
              collection.showsVerticalScrollIndicator else {
            restore(in: collection)
            return
        }
        // 受影响的版本公开 transform 仍为 identity；通过 convert 检查实际坐标方向。
        let origin = collection.bounds.origin
        let next = CGPoint(x: origin.x + 1, y: origin.y)
        guard collection.convert(next, to: window).x < collection.convert(origin, to: window).x else {
            restore(in: collection)
            return
        }

        let insets = requested(in: collection)
        let width = collection.bounds.width
        // 像素对照中滑块宽 3pt、默认离边 3pt。非零 left 统一走镜像轨道，
        // 此时窗口中的横坐标为 width - 6 - appliedLeft。
        let safeLeft = collection.automaticallyAdjustsScrollIndicatorInsets ? collection.safeAreaInsets.left : 0
        let targetLeft = max(insets.left, safeLeft)
        let appliedLeft = width - 9 - targetLeft
        guard appliedLeft.isFinite, appliedLeft > 0 else {
            restore(in: collection)
            return
        }

        var nativeInsets = insets
        nativeInsets.left = appliedLeft
        // 对侧边距会限制镜像轨道能靠左到什么位置；只在需要时放宽此限制。
        nativeInsets.right = min(insets.right, targetLeft)
        adjustment = (insets, nativeInsets)
        if collection.verticalScrollIndicatorInsets != nativeInsets {
            collection.verticalScrollIndicatorInsets = nativeInsets
        }
    }

    @discardableResult
    func restore(in collection: UICollectionView) -> Bool {
        guard collectionView === collection, adjustment != nil else { return false }
        let insets = requested(in: collection)
        adjustment = nil
        guard collection.verticalScrollIndicatorInsets != insets else { return false }
        collection.verticalScrollIndicatorInsets = insets
        return true
    }
}
