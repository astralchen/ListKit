import UIKit

// MARK: - Reusable

/// 可复用视图标记协议，默认用模块限定类型名作为 reuseIdentifier。
public protocol ReusableView: AnyObject {
    /// 注册和出队视图时使用的复用标识符。
    ///
    /// 默认实现使用包含模块名称的类型名称。
    static var listReuseIdentifier: String { get }
    /// 自动注册时查找的 nib 资源名称，不包含扩展名。
    ///
    /// 默认实现使用不含模块名称的类型名称，并在视图类型所属的资源包中查找。
    static var listNibName: String { get }
}

extension ReusableView {
    /// 默认复用标识符，使用包含模块名称的视图类型名称。
    public static var listReuseIdentifier: String { String(reflecting: Self.self) }
    /// 默认 nib 资源名称，使用不含模块名称的视图类型名称。
    public static var listNibName: String { String(describing: Self.self) }
}

extension UICollectionReusableView: ReusableView {}

/// 视图注册与出队共享的复用标识符和 nib 资源信息。
struct ListReusableMetadata {
    let identifier: String
    let nibName: String
    let bundle: Bundle

    /// 在视图类型所属的资源包中创建 nib；资源不存在时返回 `nil`，由调用方改用类注册。
    @MainActor func makeNib() -> UINib? {
        guard bundle.url(forResource: nibName, withExtension: "nib") != nil else {
            return nil
        }
        return UINib(nibName: nibName, bundle: bundle)
    }
}

/// 根据视图类型的复用协议配置和所属资源包生成注册信息。
func listReusableMetadata<View>(for viewType: View.Type) -> ListReusableMetadata
where View: UIView & ReusableView {
    ListReusableMetadata(
        identifier: View.listReuseIdentifier,
        nibName: View.listNibName,
        bundle: Bundle(for: viewType)
    )
}

/// 集合视图的复用工具，通过 `collectionView.lk` 访问。
///
/// 支持按视图类型自动注册类或同名 nib，并返回指定类型的复用视图。
public struct ListKitCollectionViewNamespace {
    let collectionView: UICollectionView

    /// 自动注册 cell class 或同名 nib。
    ///
    /// - Parameter cellType: 要注册的 cell 类型。
    @MainActor public func register<Cell>(_ cellType: Cell.Type) where Cell: UICollectionViewCell {
        let metadata = listReusableMetadata(for: cellType)
        if let nib = metadata.makeNib() {
            collectionView.register(nib, forCellWithReuseIdentifier: metadata.identifier)
        } else {
            collectionView.register(cellType, forCellWithReuseIdentifier: metadata.identifier)
        }
    }

    /// 自动注册 supplementary view class 或同名 nib。
    ///
    /// - Parameters:
    ///   - viewType: 要注册的 reusable view 类型。
    ///   - kind: 附属视图的 UIKit 元素种类。
    @MainActor public func register<View>(_ viewType: View.Type, ofKind kind: String)
    where View: UICollectionReusableView {
        let metadata = listReusableMetadata(for: viewType)
        if let nib = metadata.makeNib() {
            collectionView.register(
                nib,
                forSupplementaryViewOfKind: kind,
                withReuseIdentifier: metadata.identifier
            )
        } else {
            collectionView.register(
                viewType, forSupplementaryViewOfKind: kind, withReuseIdentifier: metadata.identifier)
        }
    }

    /// 创建支持同名 nib 自动检测的 cell registration。
    ///
    /// 标准 ListKit DSL 会自动注册和 dequeue；此 helper 主要用于手写 data source 或 provider 逃生口。
    ///
    /// - Parameters:
    ///   - cellType: 要创建 registration 的 cell 类型。
    ///   - configuration: UIKit registration 配置闭包。
    /// - Returns: nib-backed 或 class-backed 的 `UICollectionView.CellRegistration`。
    @available(iOS 15.0, tvOS 14.0, *)
    @available(watchOS, unavailable)
    @MainActor public func cellRegistration<Cell, Item>(
        _ cellType: Cell.Type,
        configuration: @escaping UICollectionView.CellRegistration<Cell, Item>.Handler
    ) -> UICollectionView.CellRegistration<Cell, Item> where Cell: UICollectionViewCell {
        let metadata = listReusableMetadata(for: cellType)
        if let nib = metadata.makeNib() {
            return UICollectionView.CellRegistration(cellNib: nib, handler: configuration)
        }
        return UICollectionView.CellRegistration(handler: configuration)
    }

    /// 创建支持同名 nib 自动检测的 supplementary registration。
    ///
    /// 标准 ListKit DSL 会自动注册和 dequeue；此 helper 主要用于手写 data source 或 provider 逃生口。
    ///
    /// - Parameters:
    ///   - viewType: 要创建 registration 的 supplementary view 类型。
    ///   - kind: 附属视图的 UIKit 元素种类。
    ///   - configuration: UIKit registration 配置闭包。
    /// - Returns: nib-backed 或 class-backed 的 `UICollectionView.SupplementaryRegistration`。
    @available(iOS 15.0, tvOS 14.0, *)
    @available(watchOS, unavailable)
    @MainActor public func supplementaryRegistration<View>(
        _ viewType: View.Type,
        ofKind kind: String,
        configuration: @escaping UICollectionView.SupplementaryRegistration<View>.Handler
    ) -> UICollectionView.SupplementaryRegistration<View> where View: UICollectionReusableView {
        let metadata = listReusableMetadata(for: viewType)
        if let nib = metadata.makeNib() {
            return UICollectionView.SupplementaryRegistration(
                supplementaryNib: nib,
                elementKind: kind,
                handler: configuration
            )
        }
        return UICollectionView.SupplementaryRegistration(elementKind: kind, handler: configuration)
    }

    /// 使用 view 类型名作为 supplementary kind 自动注册。
    ///
    /// - Parameter viewType: 要注册的 reusable view 类型。
    @MainActor public func register<View>(supplementaryView viewType: View.Type) where View: UICollectionReusableView {
        register(viewType, ofKind: UICollectionView.elementKind(for: viewType))
    }

    /// 类型安全 dequeue cell。
    ///
    /// - Parameters:
    ///   - cellType: 要 dequeue 的 cell 类型。
    ///   - indexPath: cell 所在 index path。
    /// - Returns: 强类型 cell。
    /// - Precondition: 已使用对应复用标识符注册兼容的单元格类型或 nib。
    @MainActor public func dequeue<Cell>(_ cellType: Cell.Type, for indexPath: IndexPath) -> Cell
    where Cell: UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: Cell.listReuseIdentifier, for: indexPath) as! Cell
    }

    /// 类型安全 dequeue supplementary view。
    ///
    /// - Parameters:
    ///   - viewType: 要 dequeue 的 reusable view 类型。
    ///   - kind: 附属视图的 UIKit 元素种类。
    ///   - indexPath: supplementary view 所在 index path。
    /// - Returns: 强类型 reusable view。
    /// - Precondition: 已为指定元素种类与复用标识符注册兼容的视图类型或 nib。
    @MainActor public func dequeue<View>(
        _ viewType: View.Type,
        ofKind kind: String,
        for indexPath: IndexPath
    ) -> View where View: UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: View.listReuseIdentifier,
            for: indexPath
        ) as! View
    }
}

extension UICollectionView {
    /// ListKit 默认 section 分隔线 decoration kind。
    public class var elementKindSectionSeparatorDecoration: String {
        "UICollectionView.elementKindSectionSeparatorDecoration"
    }

    /// 可供手动注册使用的 section 背景 elementKind 常量。
    /// typed SectionDecoration 不以此为默认值；查询时使用其 elementKind 或 context 映射。
    public class var elementKindSectionBackgroundDecoration: String {
        "UICollectionView.ElementKindSectionBackgroundDecoration"
    }

    /// 分区逻辑起始侧附属视图的元素种类。
    public class var elementKindSectionLeading: String {
        "UICollectionView.elementKindSectionLeading"
    }

    /// 分区逻辑结束侧附属视图的元素种类。
    public class var elementKindSectionTrailing: String {
        "UICollectionView.elementKindSectionTrailing"
    }

    /// section header 顶部 padding supplementary kind。
    public class var elementKindSectionHeaderTopPadding: String {
        "UICollectionView.elementKindSectionHeaderTopPadding"
    }

    /// section footer 底部 padding supplementary kind。
    public class var elementKindSectionFooterBottomPadding: String {
        "UICollectionView.elementKindSectionFooterBottomPadding"
    }

    /// 使用 supplementary view 的模块限定类型名生成 element kind。
    ///
    /// - Parameter viewType: supplementary view 类型。
    /// - Returns: 使用类型名生成的 element kind。
    public static func elementKind<View>(for viewType: View.Type) -> String where View: UICollectionReusableView {
        String(reflecting: viewType)
    }

    /// ListKit 注册和 dequeue 命名空间。
    public var lk: ListKitCollectionViewNamespace { ListKitCollectionViewNamespace(collectionView: self) }
}

extension UICollectionViewLayout {
    /// 自动注册 decoration view class 或同名 nib。
    ///
    /// - Parameters:
    ///   - viewType: 要注册的 decoration view 类型。
    ///   - kind: 装饰视图的 UIKit 元素种类。
    /// - Note: typed `SectionDecoration` 会通过 adapter 自动调用此 helper。
    @MainActor public func registerDecorationView<View>(_ viewType: View.Type, forKind kind: String)
    where View: UICollectionReusableView {
        let metadata = listReusableMetadata(for: viewType)
        if let nib = metadata.makeNib() {
            register(nib, forDecorationViewOfKind: kind)
        } else {
            register(viewType, forDecorationViewOfKind: kind)
        }
    }
}
