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
    var separatorColor: UIColor = .separator

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! SectionSeparatorLayoutAttributes
        copy.separatorColor = separatorColor
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SectionSeparatorLayoutAttributes,
              other.separatorColor == separatorColor else { return false }
        return super.isEqual(object)
    }
}

/// 支持轻量分隔线 decoration 的 compositional layout。
///
/// - Note: 这是 CellKit 迁移期保留的 UIKit 工具能力。新接入代码如果只需要普通 ListKit DSL，
/// 优先使用 `adapter.makeCompositionalLayout()`；只有确实需要布局层自动画分隔线时
/// 才使用这个 layout 子类。
open class UICollectionViewCompositionalSeparatorLayout: UICollectionViewCompositionalLayout {
    /// 分隔线相对 item frame 的显式 inset，默认不额外缩进。
    ///
    /// item frame 已经包含 compositional layout、safe area 和 Section content inset
    /// 的解析结果，因此这里不提供含义不明确的“自动 inset”哨兵值。
    open var separatorInsets: NSDirectionalEdgeInsets = .zero {
        didSet { invalidateLayout() }
    }

    /// 当前 layout 实例的分隔线颜色。修改后会自动刷新 decoration view。
    open var separatorColor: UIColor = .separator {
        didSet { invalidateLayout() }
    }

    /// 分隔线高度，默认一像素。
    open var separatorHeight: CGFloat = 1.0 / UIScreen.main.scale {
        didSet { invalidateLayout() }
    }

    /// 使用单个 section 创建 layout。
    ///
    /// - Parameter section: compositional layout section。
    public override init(section: NSCollectionLayoutSection) {
        super.init(section: section)
        commonInit()
    }

    /// 使用单个 section 和配置创建 layout。
    ///
    /// - Parameters:
    ///   - section: compositional layout section。
    ///   - configuration: compositional layout 配置。
    public override init(section: NSCollectionLayoutSection, configuration: UICollectionViewCompositionalLayoutConfiguration) {
        super.init(section: section, configuration: configuration)
        commonInit()
    }

    /// 使用 section provider 创建 layout。
    ///
    /// - Parameter sectionProvider: compositional layout section provider。
    public override init(sectionProvider: @escaping UICollectionViewCompositionalLayoutSectionProvider) {
        super.init(sectionProvider: sectionProvider)
        commonInit()
    }

    /// 使用 section provider 和配置创建 layout。
    ///
    /// - Parameters:
    ///   - sectionProvider: compositional layout section provider。
    ///   - configuration: compositional layout 配置。
    public override init(
        sectionProvider: @escaping UICollectionViewCompositionalLayoutSectionProvider,
        configuration: UICollectionViewCompositionalLayoutConfiguration
    ) {
        super.init(sectionProvider: sectionProvider, configuration: configuration)
        commonInit()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        register(SectionSeparatorDecorationView.self, forDecorationViewOfKind: UICollectionView.elementKindSectionSeparatorDecoration)
    }

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
