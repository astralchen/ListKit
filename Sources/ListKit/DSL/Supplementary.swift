import UIKit
import ObjectiveC

// MARK: - Supplementary Model

/// 类型擦除后的 supplementary 描述。
///
/// - Note: 页面通常不直接创建它；`Header`、`Footer`、`SectionSupplementary`、
/// `Supplementary` 和 `ProviderSupplementary` 会在 section 构建阶段转成
/// `AnySupplementary`。
public struct AnySupplementary {
    public let identity: AnyListIdentity
    public let kind: String
    public let refreshID: AnyListID?
    public let refreshPolicy: RowRefreshPolicy

    let register: @MainActor (UICollectionView) -> Void
    let viewProvider: @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionReusableView
    let configureVisibleView: (@MainActor (UICollectionReusableView, ListContext) -> Void)?
    let tapHandler: (@MainActor (ListContext) -> Void)?
    let displayHandler: (@MainActor (UICollectionReusableView, ListContext) -> Void)?
    let endDisplayHandler: (@MainActor (UICollectionReusableView, ListContext) -> Void)?
}

/// Section header/footer/custom supplementary 的 SwiftUI-like builder 元素。
///
/// - Usage:
/// ```swift
/// ListSection(.main) { ... } header: {
///     if showHeader {
///         Header(TitleHeaderView.self, id: "title") { view, _ in
///             view.titleLabel.text = title
///         }
///         .layout(height: .estimated(44), pinned: true)
///     }
/// }
/// ```
public struct ListSectionSupplementary<SectionID> where SectionID: Hashable & Sendable {
    public let kind: String
    var layout: ListSupplementaryLayout?
    private let makeSupplementaryProvider: @MainActor (SectionID) -> AnySupplementary

    init(
        kind: String,
        layout: ListSupplementaryLayout? = nil,
        makeSupplementary: @escaping @MainActor (SectionID) -> AnySupplementary
    ) {
        self.kind = kind
        self.layout = layout
        self.makeSupplementaryProvider = makeSupplementary
    }

    @MainActor func makeSupplementary(sectionID: SectionID) -> AnySupplementary {
        makeSupplementaryProvider(sectionID)
    }

    /// 描述 supplementary 内容版本。
    ///
    /// - Parameter refreshID: 当前 supplementary 内容版本 id。
    /// - Returns: 应用内容版本后的 supplementary。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self where RefreshID: Hashable & Sendable {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: AnyListID(refreshID),
                refreshPolicy: supplementary.refreshPolicy,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                tapHandler: supplementary.tapHandler,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 覆盖 supplementary 的刷新策略。
    ///
    /// - Parameter policy: 当前 supplementary 的刷新策略。
    /// - Returns: 应用刷新策略后的 supplementary。
    public func refreshPolicy(_ policy: RowRefreshPolicy) -> Self {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: supplementary.refreshID,
                refreshPolicy: policy,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                tapHandler: supplementary.tapHandler,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 给 supplementary 安装 ListKit 管理的点击事件。
    ///
    /// - Parameter handler: supplementary 被点击时调用的闭包。
    /// - Returns: 绑定点击事件后的 supplementary。
    /// - Note: ListKit 只移除自己安装的点击手势，不会清理业务 view 已有手势。
    public func onTap(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: supplementary.refreshID,
                refreshPolicy: supplementary.refreshPolicy,
                register: supplementary.register,
                viewProvider: { collectionView, indexPath, context in
                    let view = supplementary.viewProvider(collectionView, indexPath, context)
                    ListTapHandlerInstaller.install(on: view, context: context, handler: handler)
                    return view
                },
                configureVisibleView: supplementary.configureVisibleView,
                tapHandler: handler,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 绑定 supplementary 即将展示事件。
    ///
    /// - Parameter handler: supplementary 即将展示时调用的闭包。
    /// - Returns: 绑定展示事件后的 supplementary。
    public func onDisplay(_ handler: @escaping @MainActor (UICollectionReusableView, ListContext) -> Void) -> Self {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: supplementary.refreshID,
                refreshPolicy: supplementary.refreshPolicy,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                tapHandler: supplementary.tapHandler,
                displayHandler: handler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 绑定 supplementary 结束展示事件。
    ///
    /// - Parameter handler: supplementary 结束展示时调用的闭包。
    /// - Returns: 绑定结束展示事件后的 supplementary。
    public func onEndDisplay(_ handler: @escaping @MainActor (UICollectionReusableView, ListContext) -> Void) -> Self {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: supplementary.refreshID,
                refreshPolicy: supplementary.refreshPolicy,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                configureVisibleView: supplementary.configureVisibleView,
                tapHandler: supplementary.tapHandler,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: handler
            )
        }
    }

    /// 配置 boundary supplementary 的布局；header 默认 `.top`，footer 默认 `.bottom`。
    ///
    /// - Parameters:
    ///   - alignment: boundary 对齐方式；为 `nil` 时 header 默认 `.top`、footer 默认 `.bottom`。
    ///   - width: supplementary 宽度。
    ///   - height: supplementary 高度。
    ///   - extendsBoundary: 是否延伸到 section 边界外。
    ///   - pinned: 是否随滚动吸顶或吸底。
    ///   - offset: boundary 偏移。
    ///   - zIndex: supplementary 层级。
    /// - Returns: 应用 layout 后的 supplementary。
    @MainActor public func layout(
        alignment: ListSupplementaryAnchor? = nil,
        width: ListLayoutDimension = .fractionalWidth(1),
        height: ListLayoutDimension = .estimated(44),
        extendsBoundary: Bool = false,
        pinned: Bool = false,
        offset: CGPoint = .zero,
        zIndex: Int = 0
    ) -> Self {
        boundary(
            alignment: alignment ?? defaultBoundaryAlignment,
            width: width,
            height: height,
            extendsBoundary: extendsBoundary,
            pinned: pinned,
            offset: offset,
            zIndex: zIndex
        )
    }

    /// 把 supplementary 放到 section boundary，例如 header/footer 或 section 角标。
    ///
    /// - Parameters:
    ///   - alignment: boundary 对齐方式；为 `nil` 时使用默认方向。
    ///   - width: supplementary 宽度。
    ///   - height: supplementary 高度。
    ///   - extendsBoundary: 是否延伸到 section 边界外。
    ///   - pinned: 是否随滚动吸顶或吸底。
    ///   - offset: boundary 偏移。
    ///   - zIndex: supplementary 层级。
    /// - Returns: 应用 boundary placement 后的 supplementary。
    @MainActor public func boundary(
        alignment: ListSupplementaryAnchor? = nil,
        width: ListLayoutDimension = .fractionalWidth(1),
        height: ListLayoutDimension = .estimated(44),
        extendsBoundary: Bool = false,
        pinned: Bool = false,
        offset: CGPoint = .zero,
        zIndex: Int = 0
    ) -> Self {
        var copy = self
        copy.layout = ListSupplementaryLayout(
            kind: kind,
            placement: .boundary(
                alignment: alignment ?? defaultBoundaryAlignment,
                extendsBoundary: extendsBoundary,
                pinToVisibleBounds: pinned,
                offset: ListLayoutPoint(offset)
            ),
            width: width,
            height: height,
            zIndex: zIndex
        )
        return copy
    }

    /// 把 supplementary 挂到每个 item 上。
    ///
    /// - Parameters:
    ///   - anchor: item 上的锚点。
    ///   - width: supplementary 宽度。
    ///   - height: supplementary 高度。
    ///   - fractionalOffset: 相对 item 的偏移。
    ///   - zIndex: supplementary 层级。
    /// - Returns: 应用 item-level placement 后的 supplementary。
    public func itemSupplementaryLayout(
        anchor: ListSupplementaryAnchor,
        width: ListLayoutDimension,
        height: ListLayoutDimension,
        fractionalOffset: CGPoint = .zero,
        zIndex: Int = 0
    ) -> Self {
        var copy = self
        copy.layout = ListSupplementaryLayout(
            kind: kind,
            placement: .itemSupplementary(anchor: anchor, fractionalOffset: ListLayoutPoint(fractionalOffset)),
            width: width,
            height: height,
            zIndex: zIndex
        )
        return copy
    }

    /// 快捷切换 boundary supplementary 的 pinned 状态。
    ///
    /// - Parameter isSticky: 是否随滚动吸顶或吸底。
    /// - Returns: 应用 pinned 状态后的 supplementary。
    @MainActor public func sticky(_ isSticky: Bool = true) -> Self {
        var layout = self.layout ?? ListSupplementaryLayout(
            kind: kind,
            placement: .boundary(
                alignment: defaultBoundaryAlignment,
                extendsBoundary: false,
                pinToVisibleBounds: false,
                offset: .zero
            )
        )
        layout = layout.pinningBoundaryToVisibleBounds(isSticky)

        var copy = self
        copy.layout = layout
        return copy
    }

    @MainActor private var defaultBoundaryAlignment: ListSupplementaryAnchor {
        kind == UICollectionView.elementKindSectionFooter ? .bottom : .top
    }

    private func mapSupplementary(
        _ transform: @escaping @MainActor (AnySupplementary) -> AnySupplementary
    ) -> Self {
        let provider = makeSupplementaryProvider
        return ListSectionSupplementary(kind: kind, layout: layout) { sectionID in
            transform(provider(sectionID))
        }
    }
}

/// 在 `ListSection` 的 `header:` builder 中声明 header。
///
/// - Parameters:
///   - viewType: header reusable view 类型。
///   - id: header 身份。
///   - configure: 配置 header view 的闭包。
/// - Returns: 可放入 `header:` builder 的 supplementary 描述。
@MainActor public func Header<SectionID, ID, View>(
    _ viewType: View.Type,
    id: ID,
    configure: @escaping @MainActor (View, ListContext) -> Void
) -> ListSectionSupplementary<SectionID>
    where SectionID: Hashable & Sendable, ID: Hashable & Sendable, View: UICollectionReusableView
{
    SectionSupplementary(UICollectionView.elementKindSectionHeader, viewType, id: id, configure: configure)
}

/// 在 `ListSection` 的 `footer:` builder 中声明 footer。
///
/// - Parameters:
///   - viewType: footer reusable view 类型。
///   - id: footer 身份。
///   - configure: 配置 footer view 的闭包。
/// - Returns: 可放入 `footer:` builder 的 supplementary 描述。
@MainActor public func Footer<SectionID, ID, View>(
    _ viewType: View.Type,
    id: ID,
    configure: @escaping @MainActor (View, ListContext) -> Void
) -> ListSectionSupplementary<SectionID>
    where SectionID: Hashable & Sendable, ID: Hashable & Sendable, View: UICollectionReusableView
{
    SectionSupplementary(UICollectionView.elementKindSectionFooter, viewType, id: id, configure: configure)
}

/// 声明自定义 kind 的 section supplementary。
///
/// - Parameters:
///   - kind: supplementary element kind。
///   - viewType: reusable view 类型。
///   - id: supplementary 身份。
///   - configure: 配置 reusable view 的闭包。
/// - Returns: 可放入 `supplementaries:` builder 的 supplementary 描述。
@MainActor public func SectionSupplementary<SectionID, ID, View>(
    _ kind: String,
    _ viewType: View.Type,
    id: ID,
    configure: @escaping @MainActor (View, ListContext) -> Void
) -> ListSectionSupplementary<SectionID>
    where SectionID: Hashable & Sendable, ID: Hashable & Sendable, View: UICollectionReusableView
{
    ListSectionSupplementary(kind: kind) { sectionID in
        Supplementary(kind, id: id, view: viewType, configure: configure)
            .eraseToAnySupplementary(sectionID: sectionID)
    }
}

/// Header/Footer/自定义 supplementary 的描述模型。
///
/// - Note: 页面通常通过 `ListSection.header(...)` / `footer(...)` 使用它；需要自定义 kind 时再直接用
/// `supplementary(_:_:id:configure:)`。
public struct Supplementary<ID, View> where ID: Hashable & Sendable, View: UICollectionReusableView {
    private let id: ID
    private let kind: String
    private let viewType: View.Type
    private let configure: @MainActor (View, ListContext) -> Void
    private var supplementaryRefreshID: AnyListID?
    private var supplementaryRefreshPolicy: RowRefreshPolicy = .automaticVisible
    private var supplementaryTapHandler: (@MainActor (ListContext) -> Void)?
    private var supplementaryDisplayHandler: (@MainActor (View, ListContext) -> Void)?
    private var supplementaryEndDisplayHandler: (@MainActor (View, ListContext) -> Void)?

    /// 创建 supplementary 描述。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - id: supplementary 身份。
    ///   - viewType: reusable view 类型。
    ///   - configure: 配置 reusable view 的闭包。
    public init(
        _ kind: String,
        id: ID,
        view viewType: View.Type,
        configure: @escaping @MainActor (View, ListContext) -> Void
    ) {
        self.id = id
        self.kind = kind
        self.viewType = viewType
        self.configure = configure
    }

    /// 设置 supplementary 内容刷新版本。
    ///
    /// - Parameter refreshID: 当前 supplementary 内容版本 id。
    /// - Returns: 应用内容版本后的 supplementary。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self where RefreshID: Hashable & Sendable {
        var copy = self
        copy.supplementaryRefreshID = AnyListID(refreshID)
        return copy
    }

    /// 覆盖 supplementary 刷新策略。
    ///
    /// - Parameter policy: 当前 supplementary 的刷新策略。
    /// - Returns: 应用刷新策略后的 supplementary。
    public func refreshPolicy(_ policy: RowRefreshPolicy) -> Self {
        var copy = self
        copy.supplementaryRefreshPolicy = policy
        return copy
    }

    /// 绑定点击事件。
    ///
    /// - Parameter handler: supplementary 被点击时调用的闭包。
    /// - Returns: 绑定点击事件后的 supplementary。
    public func onTap(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        var copy = self
        copy.supplementaryTapHandler = handler
        return copy
    }

    /// 绑定展示事件。
    ///
    /// - Parameter handler: supplementary 即将展示时调用的闭包。
    /// - Returns: 绑定展示事件后的 supplementary。
    public func onDisplay(_ handler: @escaping @MainActor (View, ListContext) -> Void) -> Self {
        var copy = self
        copy.supplementaryDisplayHandler = handler
        return copy
    }

    /// 绑定结束展示事件。
    ///
    /// - Parameter handler: supplementary 结束展示时调用的闭包。
    /// - Returns: 绑定结束展示事件后的 supplementary。
    public func onEndDisplay(_ handler: @escaping @MainActor (View, ListContext) -> Void) -> Self {
        var copy = self
        copy.supplementaryEndDisplayHandler = handler
        return copy
    }

    @MainActor func eraseToAnySupplementary<SectionID>(sectionID: SectionID) -> AnySupplementary
        where SectionID: Hashable & Sendable
    {
        let identity = AnyListIdentity(
            sectionID: AnyListID(sectionID),
            rowID: AnyListID(id),
            presentationID: ObjectIdentifier(viewType),
            variant: AnyListID(kind)
        )
        let displayHandler: (@MainActor (UICollectionReusableView, ListContext) -> Void)?
        if let handler = supplementaryDisplayHandler {
            displayHandler = { view, context in
                guard let typedView = view as? View else { return }
                handler(typedView, context)
            }
        } else {
            displayHandler = nil
        }
        let endDisplayHandler: (@MainActor (UICollectionReusableView, ListContext) -> Void)?
        if let handler = supplementaryEndDisplayHandler {
            endDisplayHandler = { view, context in
                guard let typedView = view as? View else { return }
                handler(typedView, context)
            }
        } else {
            endDisplayHandler = nil
        }

        return AnySupplementary(
            identity: identity,
            kind: kind,
            refreshID: supplementaryRefreshID,
            refreshPolicy: supplementaryRefreshPolicy,
            register: { collectionView in
                collectionView.lk.register(viewType, ofKind: kind)
            },
            viewProvider: { collectionView, indexPath, context in
                let view = collectionView.lk.dequeue(viewType, ofKind: kind, for: indexPath)
                configure(view, context)
                ListTapHandlerInstaller.install(
                    on: view,
                    context: context,
                    handler: supplementaryTapHandler
                )
                return view
            },
            configureVisibleView: { view, context in
                guard let typedView = view as? View else { return }
                configure(typedView, context)
            },
            tapHandler: supplementaryTapHandler,
            displayHandler: displayHandler,
            endDisplayHandler: endDisplayHandler
        )
    }
}

/// Provider-backed supplementary escape hatch for mixed migration pages.
///
/// - Important: 正常页面优先使用 `Header`、`Footer`、`SectionSupplementary` 或
/// `ListSection.header/footer/supplementary`。只有旧页面已经封装了 view provider
/// 并且短期内不能拆开时，才使用这个迁移入口。
public struct ProviderSupplementary<ID> where ID: Hashable & Sendable {
    private let id: ID
    private let kind: String
    private let presentationID: ObjectIdentifier
    private let registerProvider: @MainActor (UICollectionView) -> Void
    private let viewProvider: @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionReusableView
    private var supplementaryRefreshID: AnyListID?
    private var supplementaryRefreshPolicy: RowRefreshPolicy = .automaticVisible
    private var supplementaryTapHandler: (@MainActor (ListContext) -> Void)?

    /// 用 view 类型作为展示 identity 的 ProviderSupplementary。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - id: supplementary 身份。
    ///   - viewType: 用于 presentation identity 和默认注册的 reusable view 类型。
    ///   - register: 可选的自定义注册闭包。
    ///   - viewProvider: 创建或 dequeue reusable view 的闭包。
    /// - Important: 此入口只用于迁移期保留旧 view provider。
    public init<View>(
        _ kind: String,
        id: ID,
        view viewType: View.Type,
        register: (@MainActor (UICollectionView) -> Void)? = nil,
        viewProvider: @escaping @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionReusableView
    ) where View: UICollectionReusableView {
        self.id = id
        self.kind = kind
        self.presentationID = ObjectIdentifier(viewType)
        self.registerProvider = register ?? { collectionView in
            collectionView.lk.register(viewType, ofKind: kind)
        }
        self.viewProvider = viewProvider
    }

    /// 完全自定义 presentation identity 的 ProviderSupplementary。
    ///
    /// - Parameters:
    ///   - kind: supplementary element kind。
    ///   - id: supplementary 身份。
    ///   - presentationID: 自定义展示身份。
    ///   - register: 注册 reusable view 的闭包。
    ///   - viewProvider: 创建或 dequeue reusable view 的闭包。
    /// - Important: 仅用于无法用具体 reusable view 类型表达 presentation identity 的迁移场景。
    public init(
        _ kind: String,
        id: ID,
        presentationID: ObjectIdentifier,
        register: @escaping @MainActor (UICollectionView) -> Void,
        viewProvider: @escaping @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionReusableView
    ) {
        self.id = id
        self.kind = kind
        self.presentationID = presentationID
        self.registerProvider = register
        self.viewProvider = viewProvider
    }

    /// 设置内容刷新版本。
    ///
    /// - Parameter refreshID: 当前 supplementary 内容版本 id。
    /// - Returns: 应用内容版本后的 provider supplementary。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self where RefreshID: Hashable & Sendable {
        var copy = self
        copy.supplementaryRefreshID = AnyListID(refreshID)
        return copy
    }

    /// 覆盖刷新策略。
    ///
    /// - Parameter policy: 当前 supplementary 的刷新策略。
    /// - Returns: 应用刷新策略后的 provider supplementary。
    public func refreshPolicy(_ policy: RowRefreshPolicy) -> Self {
        var copy = self
        copy.supplementaryRefreshPolicy = policy
        return copy
    }

    /// 绑定点击事件。
    ///
    /// - Parameter handler: supplementary 被点击时调用的闭包。
    /// - Returns: 绑定点击事件后的 provider supplementary。
    public func onTap(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        var copy = self
        copy.supplementaryTapHandler = handler
        return copy
    }

    @MainActor func eraseToAnySupplementary<SectionID>(sectionID: SectionID) -> AnySupplementary
        where SectionID: Hashable & Sendable
    {
        let identity = AnyListIdentity(
            sectionID: AnyListID(sectionID),
            rowID: AnyListID(id),
            presentationID: presentationID,
            variant: AnyListID(kind)
        )

        return AnySupplementary(
            identity: identity,
            kind: kind,
            refreshID: supplementaryRefreshID,
            refreshPolicy: supplementaryRefreshPolicy,
            register: registerProvider,
            viewProvider: { collectionView, indexPath, context in
                let view = viewProvider(collectionView, indexPath, context)
                ListTapHandlerInstaller.install(
                    on: view,
                    context: context,
                    handler: supplementaryTapHandler
                )
                return view
            },
            configureVisibleView: nil,
            tapHandler: supplementaryTapHandler,
            displayHandler: nil,
            endDisplayHandler: nil
        )
    }
}

// MARK: - Tap Handler Installer

nonisolated(unsafe) private var tapProxyKey: UInt8 = 0

@MainActor
private final class TapProxy: NSObject {
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func invoke() {
        handler()
    }
}

private final class ListTapGestureRecognizer: UITapGestureRecognizer {}

/// 内部点击事件安装器。
///
/// - Important: Supplementary view 会被复用，所以每次配置时先移除旧 tap 手势，再安装新的闭包代理。
/// `TapProxy` 通过 associated object 持有，避免 UIKit gesture target 被提前释放。
@MainActor
enum ListTapHandlerInstaller {
    static func install(
        on view: UICollectionReusableView,
        handler: (@MainActor () -> Void)?
    ) {
        view.gestureRecognizers?.forEach { recognizer in
            if recognizer is ListTapGestureRecognizer {
                view.removeGestureRecognizer(recognizer)
            }
        }
        objc_setAssociatedObject(view, &tapProxyKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        guard let handler else { return }
        let proxy = TapProxy(handler: handler)
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(ListTapGestureRecognizer(target: proxy, action: #selector(TapProxy.invoke)))
        objc_setAssociatedObject(view, &tapProxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func install(
        on view: UICollectionReusableView,
        context: ListContext,
        handler: (@MainActor (ListContext) -> Void)?
    ) {
        guard let handler else {
            install(on: view, handler: nil)
            return
        }
        install(on: view) {
            handler(context)
        }
    }
}
