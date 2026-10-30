import UIKit

/// 容器变化时，重新计算绝对尺寸轨道，以及根据环境选择的完整布局。
final class ListCollectionLayout: UICollectionViewCompositionalLayout {
    /// 当界面方向与布局基准方向相反时，允许 UIKit 水平翻转布局。
    override var flipsHorizontallyInOppositeLayoutDirection: Bool { true }
    /// 以从左到右作为布局基准方向，配合水平翻转适配从右到左的界面。
    override var developmentLayoutDirection: UIUserInterfaceLayoutDirection { .leftToRight }

    /// 当前监听的集合视图；弱引用避免延长视图生命周期，也用于防止重复注册监听。
    private weak var observedCollection: UICollectionView?
    /// 保留内容边距的观察令牌，使监听在布局存续期间保持有效。
    private var insetObservation: NSKeyValueObservation?
    /// 保留系统调整后内容边距的观察令牌，以响应安全区等因素引起的边距变化。
    private var adjustedInsetObservation: NSKeyValueObservation?

    /// 为集合视图注册边距监听；切换视图时替换观察令牌，边距实际变化后使布局失效。
    private func observeInsets(of collection: UICollectionView) {
        guard observedCollection !== collection else { return }
        observedCollection = collection
        insetObservation = collection.observe(\.contentInset, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue != change.newValue else { return }
            MainActor.assumeIsolated { self?.invalidateLayout() }
        }
        adjustedInsetObservation = collection.observe(\.adjustedContentInset, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue != change.newValue else { return }
            MainActor.assumeIsolated { self?.invalidateLayout() }
        }
    }

    /// 上次准备布局时的容器尺寸；为空表示尚未建立环境快照。
    private var previousSize: CGSize?
    /// 上次准备布局时系统调整后的内容边距。
    private var previousInsets: UIEdgeInsets?
    /// 上次准备布局时的安全区边距，独立于内容边距参与变化检测。
    private var previousSafeArea: UIEdgeInsets?
    /// 上次准备布局时实际生效的界面布局方向。
    private var previousDirection: UIUserInterfaceLayoutDirection?
    /// 上次准备布局时的特征集合，用于检测尺寸类别、文字大小等环境变化。
    private var previousTraits: UITraitCollection?
    /// 上次准备布局时配置的主滚动方向。
    private var previousScrollDirection: UICollectionView.ScrollDirection?

    /// 更新边距监听与环境快照；已有快照且环境变化时，使布局失效后交由 UIKit 准备布局。
    override func prepare() {
        if let collectionView {
            observeInsets(of: collectionView)
            // 首次准备仅建立快照，后续才比较环境，避免首次布局时额外触发失效。
            let changed = previousSize != nil && (
                previousSize != collectionView.bounds.size
                || previousInsets != collectionView.adjustedContentInset
                || previousSafeArea != collectionView.safeAreaInsets
                || previousDirection != collectionView.effectiveUserInterfaceLayoutDirection
                    || previousTraits != collectionView.traitCollection
                    || previousScrollDirection != configuration.scrollDirection)
            // 在触发布局失效前保存当前环境，避免重复检测到同一次变化。
            previousSize = collectionView.bounds.size
            previousInsets = collectionView.adjustedContentInset
            previousSafeArea = collectionView.safeAreaInsets
            previousDirection = collectionView.effectiveUserInterfaceLayoutDirection
            previousTraits = collectionView.traitCollection
            previousScrollDirection = configuration.scrollDirection
            if changed { invalidateLayout() }
        }
        super.prepare()
    }

    /// 容器尺寸变化时要求重新布局；其他边界变化沿用父类的失效判断。
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
        || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
}

/// 布局提供者持有此对象，通过弱引用访问布局以避免循环引用；解析时读取当前 UIKit 布局配置。
@MainActor
final class ListLayoutDirectionSource {
    /// 弱引用实际布局，供解析时读取最新滚动方向，避免与布局提供者形成循环引用。
    weak var layout: UICollectionViewCompositionalLayout?
    /// 尚未关联布局或布局已释放时使用的初始滚动方向。
    let initial: ListLayoutScrollDirection
    /// 保存回退方向，实际布局可在创建后再关联。
    init(initial: ListLayoutScrollDirection) { self.initial = initial }
    /// 优先读取当前 UIKit 布局配置中的滚动方向，布局不可用时返回初始值。
    var current: ListLayoutScrollDirection {
        guard let layout else { return initial }
        return layout.configuration.scrollDirection == .horizontal ? .horizontal : .vertical
    }
}
