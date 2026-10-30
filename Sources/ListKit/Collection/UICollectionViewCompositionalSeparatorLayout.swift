import UIKit

final class SectionSeparatorDecorationView: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        guard let attributes = layoutAttributes as? SectionSeparatorLayoutAttributes else { return }
        backgroundColor = attributes.separatorColor
    }
}

final class SectionSeparatorLayoutAttributes: UICollectionViewLayoutAttributes {
    // NSObject.isEqual(_:) 是非隔离接口；颜色存储独立同步，比较不要求 MainActor。
    private nonisolated let colorStorage = SectionSeparatorColorStorage()

    @MainActor var separatorColor: UIColor {
        get { colorStorage.value }
        set { colorStorage.setValue(newValue) }
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! SectionSeparatorLayoutAttributes
        copy.separatorColor = separatorColor
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SectionSeparatorLayoutAttributes else { return false }
        let color = colorStorage.value
        let otherColor = other.colorStorage.value
        return color == otherColor && super.isEqual(object)
    }
}

/// 只有 UIColor 值跨隔离域共享；所有读写均由锁保护，且不在锁内执行颜色比较。
/// 为兼容 iOS 15 使用 NSLock；写入仍限定在 MainActor，非隔离调用只读取颜色快照。
/// @unchecked Sendable 的保证仅覆盖此私有存储，不扩展到 UIKit 布局属性对象。
private final class SectionSeparatorColorStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var color: UIColor = .separator

    var value: UIColor {
        lock.lock()
        defer { lock.unlock() }
        return color
    }

    @MainActor func setValue(_ newValue: UIColor) {
        lock.lock()
        defer { lock.unlock() }
        color = newValue
    }
}

/// 为单元格与附属视图添加底部分隔线的组合布局。
///
/// 分隔线通过装饰视图绘制，包含最后一个单元格，始终沿水平方向延伸。
open class UICollectionViewCompositionalSeparatorLayout: UICollectionViewCompositionalLayout {
    /// cell 底部分隔线的水平缩进，默认零；supplementary 的分隔线始终使用零 inset。
    /// 当前实现仅使用 leading / trailing，并分别映射为物理 left / right；不自动按 RTL 交换。
    /// top / bottom 当前不参与分隔线计算。
    open var separatorInsets: NSDirectionalEdgeInsets = .zero {
        didSet { invalidateLayout() }
    }

    /// 分隔线颜色，默认为系统分隔线色；修改后使布局失效，供后续布局更新读取。
    open var separatorColor: UIColor = .separator {
        didSet { invalidateLayout() }
    }

    /// 分隔线高度，单位为点；初始化时默认取 `1 / UIScreen.main.scale`。
    /// 默认值不会随后续窗口或显示器 scale 变化自动重算。
    open var separatorHeight: CGFloat = 1.0 / UIScreen.main.scale {
        didSet { invalidateLayout() }
    }

    /// 使用单个 section 创建 layout。
    ///
    /// - Parameter section: 组合布局使用的分区。
    public override init(section: NSCollectionLayoutSection) {
        super.init(section: section)
        commonInit()
    }

    /// 使用单个 section 和配置创建 layout。
    ///
    /// - Parameters:
    ///   - section: 组合布局使用的分区。
    ///   - configuration: compositional layout 配置。
    public override init(section: NSCollectionLayoutSection, configuration: UICollectionViewCompositionalLayoutConfiguration) {
        super.init(section: section, configuration: configuration)
        commonInit()
    }

    /// 使用 section provider 创建 layout。
    ///
    /// - Parameter sectionProvider: 根据分区索引和布局环境创建分区的闭包。
    public override init(sectionProvider: @escaping UICollectionViewCompositionalLayoutSectionProvider) {
        super.init(sectionProvider: sectionProvider)
        commonInit()
    }

    /// 使用 section provider 和配置创建 layout。
    ///
    /// - Parameters:
    ///   - sectionProvider: 根据分区索引和布局环境创建分区的闭包。
    ///   - configuration: compositional layout 配置。
    public override init(
        sectionProvider: @escaping UICollectionViewCompositionalLayoutSectionProvider,
        configuration: UICollectionViewCompositionalLayoutConfiguration
    ) {
        super.init(sectionProvider: sectionProvider, configuration: configuration)
        commonInit()
    }

    /// 从归档创建布局，并注册分隔线装饰视图。
    ///
    /// - Parameter coder: 包含布局配置的解码器。
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        register(SectionSeparatorDecorationView.self, forDecorationViewOfKind: UICollectionView.elementKindSectionSeparatorDecoration)
    }

    /// 返回指定区域内的布局属性，并为单元格与附属视图追加底部分隔线属性。
    ///
    /// - Parameter rect: 集合视图内容坐标系中的查询区域。
    /// - Returns: 原始布局属性与分隔线属性；父类没有布局结果或集合视图不可用时返回 `nil`。
    open override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard
            let baseAttributes = super.layoutAttributesForElements(in: rect),
            let collectionView
        else {
            return nil
        }

        var attributes = baseAttributes
        for attribute in baseAttributes {
            let lastItem = collectionView.numberOfItems(inSection: attribute.indexPath.section) - 1
            if attribute.representedElementCategory == .cell, attribute.indexPath.item <= lastItem {
                attributes.append(separatorAttributes(for: attribute, edgeInsets: UIEdgeInsets(
                    top: 0,
                    left: separatorInsets.leading,
                    bottom: 0,
                    right: separatorInsets.trailing
                )))
            } else if attribute.representedElementCategory == .supplementaryView {
                attributes.append(separatorAttributes(for: attribute, edgeInsets: .zero))
            }
        }
        return attributes
    }

    /// 返回指定装饰视图的布局属性。
    ///
    /// 分隔线使用当前颜色、高度和集合视图宽度创建基础属性，其他元素种类交由父类处理。
    ///
    /// - Parameters:
    ///   - elementKind: UIKit 装饰视图的元素种类。
    ///   - indexPath: 装饰视图的索引路径。
    /// - Returns: 对应的布局属性；其他元素种类沿用父类的返回值。
    open override func layoutAttributesForDecorationView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard elementKind == UICollectionView.elementKindSectionSeparatorDecoration else {
            return super.layoutAttributesForDecorationView(ofKind: elementKind, at: indexPath)
        }
        let attributes = SectionSeparatorLayoutAttributes(
            forDecorationViewOfKind: elementKind,
            with: indexPath
        )
        attributes.frame = CGRect(x: 0, y: 0, width: collectionView?.bounds.width ?? 0, height: separatorHeight)
        attributes.zIndex = 2
        attributes.separatorColor = separatorColor
        return attributes
    }

    private func separatorAttributes(
        for layoutAttributes: UICollectionViewLayoutAttributes,
        edgeInsets: UIEdgeInsets
    ) -> UICollectionViewLayoutAttributes {
        let indexPath = layoutAttributes.representedElementCategory == .supplementaryView
            ? IndexPath(index: layoutAttributes.indexPath.section)
            : layoutAttributes.indexPath
        let attributes = SectionSeparatorLayoutAttributes(
            forDecorationViewOfKind: UICollectionView.elementKindSectionSeparatorDecoration,
            with: indexPath
        )
        attributes.frame = CGRect(
            x: layoutAttributes.frame.minX,
            y: layoutAttributes.frame.maxY,
            width: layoutAttributes.frame.width,
            height: separatorHeight
        ).inset(by: edgeInsets)
        attributes.zIndex = 2
        attributes.separatorColor = separatorColor
        return attributes
    }
}
