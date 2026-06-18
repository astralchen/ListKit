import UIKit

final class SectionSeparatorDecorationView: UICollectionReusableView {
    static var separatorColor: UIColor = .separator

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.separatorColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 支持轻量分隔线 decoration 的 compositional layout。
///
/// - Note: 这是 CellKit 迁移期保留的 UIKit 工具能力。新页面如果只需要普通 ListKit DSL，
/// 优先使用 `adapter.makeCompositionalLayout()`；只有确实需要布局层自动画分隔线时
/// 才使用这个 layout 子类。
open class UICollectionViewCompositionalSeparatorLayout: UICollectionViewCompositionalLayout {
    /// 自动沿用系统默认 inset 的哨兵值。
    public static let automaticInsets = NSDirectionalEdgeInsets(
        top: UIView.noIntrinsicMetric,
        leading: UIView.noIntrinsicMetric,
        bottom: UIView.noIntrinsicMetric,
        trailing: UIView.noIntrinsicMetric
    )

    /// 分隔线 inset。修改后会自动 invalidate layout。
    open var separatorInsets: NSDirectionalEdgeInsets = .zero {
        didSet { invalidateLayout() }
    }

    /// 分隔线颜色。修改后会自动刷新 decoration view。
    open var separatorColor: UIColor = .separator {
        didSet {
            SectionSeparatorDecorationView.separatorColor = separatorColor
            invalidateLayout()
        }
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
        let attributes = UICollectionViewLayoutAttributes(forDecorationViewOfKind: elementKind, with: indexPath)
        attributes.frame = CGRect(x: 0, y: 0, width: collectionView?.bounds.width ?? 0, height: separatorHeight)
        attributes.zIndex = 2
        return attributes
    }

    private func separatorAttributes(
        for layoutAttributes: UICollectionViewLayoutAttributes,
        edgeInsets: UIEdgeInsets
    ) -> UICollectionViewLayoutAttributes {
        let indexPath = layoutAttributes.representedElementCategory == .supplementaryView
            ? IndexPath(index: layoutAttributes.indexPath.section)
            : layoutAttributes.indexPath
        let attributes = UICollectionViewLayoutAttributes(
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
        return attributes
    }
}
