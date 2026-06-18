import UIKit

// MARK: - Reusable

/// 可复用视图标记协议，默认用类型名作为 reuseIdentifier。
public protocol ReusableView: AnyObject {
    static var listReuseIdentifier: String { get }
}

public extension ReusableView {
    static var listReuseIdentifier: String { String(describing: Self.self) }
}

extension UICollectionReusableView: ReusableView {}

private struct ListReusableMetadata {
    let identifier: String
    let bundle: Bundle

    @MainActor func makeNib() -> UINib? {
        guard bundle.url(forResource: identifier, withExtension: "nib") != nil else {
            return nil
        }
        return UINib(nibName: identifier, bundle: bundle)
    }
}

private func listReusableMetadata<View>(for viewType: View.Type) -> ListReusableMetadata
    where View: UIView & ReusableView
{
    ListReusableMetadata(
        identifier: View.listReuseIdentifier,
        bundle: Bundle(for: viewType)
    )
}

/// `collectionView.lk` 命名空间，负责自动注册 class/nib 和类型安全 dequeue。
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
    ///   - kind: supplementary element kind。
    @MainActor public func register<View>(_ viewType: View.Type, ofKind kind: String) where View: UICollectionReusableView {
        let metadata = listReusableMetadata(for: viewType)
        if let nib = metadata.makeNib() {
            collectionView.register(
                nib,
                forSupplementaryViewOfKind: kind,
                withReuseIdentifier: metadata.identifier
            )
        } else {
            collectionView.register(viewType, forSupplementaryViewOfKind: kind, withReuseIdentifier: metadata.identifier)
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
    @available(iOS 14.0, tvOS 14.0, *)
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
    ///   - kind: supplementary element kind。
    ///   - configuration: UIKit registration 配置闭包。
    /// - Returns: nib-backed 或 class-backed 的 `UICollectionView.SupplementaryRegistration`。
    @available(iOS 14.0, tvOS 14.0, *)
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
    @MainActor public func dequeue<Cell>(_ cellType: Cell.Type, for indexPath: IndexPath) -> Cell where Cell: UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: Cell.listReuseIdentifier, for: indexPath) as! Cell
    }

    /// 类型安全 dequeue supplementary view。
    ///
    /// - Parameters:
    ///   - viewType: 要 dequeue 的 reusable view 类型。
    ///   - kind: supplementary element kind。
    ///   - indexPath: supplementary view 所在 index path。
    /// - Returns: 强类型 reusable view。
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

public extension UICollectionView {
    /// ListKit 默认 section 分隔线 decoration kind。
    class var elementKindSectionSeparatorDecoration: String {
        "UICollectionView.elementKindSectionSeparatorDecoration"
    }

    /// ListKit 默认 section 背景 decoration kind。
    class var elementKindSectionBackgroundDecoration: String {
        "UICollectionView.ElementKindSectionBackgroundDecoration"
    }

    /// section leading supplementary kind。
    class var elementKindSectionLeading: String {
        "UICollectionView.elementKindSectionLeading"
    }

    /// section trailing supplementary kind。
    class var elementKindSectionTrailing: String {
        "UICollectionView.elementKindSectionTrailing"
    }

    /// section header 顶部 padding supplementary kind。
    class var elementKindSectionHeaderTopPadding: String {
        "UICollectionView.elementKindSectionHeaderTopPadding"
    }

    /// section footer 底部 padding supplementary kind。
    class var elementKindSectionFooterBottomPadding: String {
        "UICollectionView.elementKindSectionFooterBottomPadding"
    }

    /// 使用 supplementary view 类型名生成 element kind。
    ///
    /// - Parameter viewType: supplementary view 类型。
    /// - Returns: 使用类型名生成的 element kind。
    static func elementKind<View>(for viewType: View.Type) -> String where View: UICollectionReusableView {
        String(describing: viewType)
    }

    /// ListKit 注册和 dequeue 命名空间。
    var lk: ListKitCollectionViewNamespace { ListKitCollectionViewNamespace(collectionView: self) }

    /// 迁移兼容入口；新代码优先使用 `collectionView.lk.register(Cell.self)`。
    @available(*, deprecated, message: "Migration-only compatibility. Prefer collectionView.lk.register(Cell.self).")
    @MainActor func register<Cell>(_ cellType: Cell.Type) where Cell: UICollectionViewCell {
        lk.register(cellType)
    }

    /// 迁移兼容入口；新代码优先使用 `collectionView.lk.register(View.self, ofKind: kind)`。
    @available(*, deprecated, message: "Migration-only compatibility. Prefer collectionView.lk.register(View.self, ofKind: kind).")
    @MainActor func register<View>(_ viewType: View.Type, forSupplementaryViewOfKind kind: String)
        where View: UICollectionReusableView
    {
        lk.register(viewType, ofKind: kind)
    }

    /// 迁移兼容入口；新代码优先使用 `collectionView.lk.register(supplementaryView: View.self)`。
    @available(*, deprecated, message: "Migration-only compatibility. Prefer collectionView.lk.register(supplementaryView: View.self).")
    @MainActor func register<View>(supplementaryView viewType: View.Type) where View: UICollectionReusableView {
        lk.register(supplementaryView: viewType)
    }

    /// 迁移兼容入口；新代码优先使用 `collectionView.lk.dequeue(Cell.self, for: indexPath)`。
    @available(*, deprecated, message: "Migration-only compatibility. Prefer collectionView.lk.dequeue(Cell.self, for: indexPath).")
    @MainActor func dequeueReusableCell<Cell>(withCellClass cellType: Cell.Type, for indexPath: IndexPath) -> Cell
        where Cell: UICollectionViewCell
    {
        lk.dequeue(cellType, for: indexPath)
    }

    /// 迁移兼容入口；新代码优先使用 `collectionView.lk.dequeue(View.self, ofKind: kind, for: indexPath)`。
    @available(*, deprecated, message: "Migration-only compatibility. Prefer collectionView.lk.dequeue(View.self, ofKind: kind, for: indexPath).")
    @MainActor func dequeueReusableSupplementaryView<View>(
        ofKind kind: String,
        withViewClass viewType: View.Type,
        for indexPath: IndexPath
    ) -> View where View: UICollectionReusableView {
        lk.dequeue(viewType, ofKind: kind, for: indexPath)
    }
}

public extension UICollectionViewLayout {
    /// 自动注册 decoration view class 或同名 nib。
    ///
    /// - Parameters:
    ///   - viewType: 要注册的 decoration view 类型。
    ///   - kind: decoration element kind。
    /// - Note: typed `ListBackgroundDecoration` 会通过 adapter 自动调用此 helper。
    @MainActor func registerDecorationView<View>(_ viewType: View.Type, forKind kind: String) where View: UICollectionReusableView {
        let metadata = listReusableMetadata(for: viewType)
        if let nib = metadata.makeNib() {
            register(nib, forDecorationViewOfKind: kind)
        } else {
            register(viewType, forDecorationViewOfKind: kind)
        }
    }
}
