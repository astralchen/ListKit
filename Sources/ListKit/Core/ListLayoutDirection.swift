import UIKit

/// 两种列表共用的方向覆盖；只在首次显式设置时保存原环境，取消覆盖后恢复。
@MainActor
final class ListLayoutDirectionOverride {
    private var originalSemantic: UISemanticContentAttribute?
    private var originalTrait: UITraitEnvironmentLayoutDirection?

    func apply(_ direction: UITraitEnvironmentLayoutDirection, to view: UIView) {
        switch direction {
        case .leftToRight, .rightToLeft:
            if originalSemantic == nil {
                originalSemantic = view.semanticContentAttribute
                if #available(iOS 17.0, *), view.traitOverrides.contains(UITraitLayoutDirection.self) {
                    originalTrait = view.traitOverrides.layoutDirection
                }
            }
            view.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
            if #available(iOS 17.0, *) {
                view.traitOverrides.layoutDirection = direction
            }
        case .unspecified:
            guard let originalSemantic else { return }
            view.semanticContentAttribute = originalSemantic
            if #available(iOS 17.0, *) {
                if let originalTrait {
                    view.traitOverrides.layoutDirection = originalTrait
                } else {
                    view.traitOverrides.remove(UITraitLayoutDirection.self)
                }
            }
            self.originalSemantic = nil
            originalTrait = nil
        @unknown default:
            return
        }
        if #available(iOS 17.0, *) { view.updateTraitsIfNeeded() }
        view.setNeedsLayout()
    }

    /// 完成方向变化后的布局，保留 UIKit 的自动指示器布局行为。
    func refreshScrollIndicators(in scrollView: UIScrollView) {
        scrollView.layoutIfNeeded()
        guard scrollView is UITableView else { return }
        // UITableView 会缓存原生指示器所在侧；重设相同 insets 不能清除此缓存。
        // 通过公开的自动边距开关触发重算，并在本次调用内恢复业务设置。
        recalculateScrollIndicatorInsets(in: scrollView)
    }

    func recalculateScrollIndicatorInsets(in scrollView: UIScrollView) {
        let automaticallyAdjusts = scrollView.automaticallyAdjustsScrollIndicatorInsets
        scrollView.automaticallyAdjustsScrollIndicatorInsets = !automaticallyAdjusts
        scrollView.layoutIfNeeded()
        scrollView.automaticallyAdjustsScrollIndicatorInsets = automaticallyAdjusts
        scrollView.layoutIfNeeded()
    }
}

/// iOS 15/16 没有 UIView.traitOverrides；向布局 DSL 提供与显式方向一致的环境。
final class ListDirectionLayoutEnvironment: NSObject, NSCollectionLayoutEnvironment {
    let container: any NSCollectionLayoutContainer
    let traitCollection: UITraitCollection

    init(_ environment: any NSCollectionLayoutEnvironment, direction: UITraitEnvironmentLayoutDirection) {
        container = environment.container
        traitCollection = UITraitCollection(traitsFrom: [
            environment.traitCollection, UITraitCollection(layoutDirection: direction),
        ])
    }
}
