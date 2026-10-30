import ObjectiveC
import UIKit

// MARK: - Supplementary Model

/// 附属视图内容的类型擦除描述，几何信息由分区布局保存。
public struct AnySupplementary {
    /// 包含 Section、supplementary ID、view 类型和展示变体的稳定 identity。
    public let identity: AnyListIdentity
    /// 关联内容与几何的业务 kind；自适应多 line Grid 可映射为多个实际 UIKit elementKind。
    public let kind: String
    /// 调用方提供的内容版本，配合刷新规则决定是否重配可见视图或重载所属分区。
    public let refreshID: AnyListID?
    /// identity 保持不变时使用的 supplementary 刷新规则。
    public let refreshRule: ListSupplementaryRefreshRule

    let register: @MainActor (UICollectionView, String) -> Void
    let viewProvider: @MainActor (UICollectionView, String, IndexPath, ListContext) -> UICollectionReusableView
    let supportsElementKindMapping: Bool
    let configureVisibleView: (@MainActor (UICollectionReusableView, ListContext) -> Void)?
    let tapHandler: (@MainActor (ListContext) -> Void)?
    let displayHandler: (@MainActor (UICollectionReusableView, ListContext) -> Void)?
    let endDisplayHandler: (@MainActor (UICollectionReusableView, ListContext) -> Void)?
}

/// 通过业务元素种类与布局关联的分区附属视图内容。
public struct ListSectionSupplementary<SectionID> where SectionID: Hashable & Sendable {
    /// 关联内容与几何的业务 kind；自适应多 line Grid 可映射为多个实际 UIKit elementKind。
    public let kind: String
    private let makeSupplementaryProvider: @MainActor (SectionID) -> AnySupplementary

    init(
        kind: String,
        makeSupplementary: @escaping @MainActor (SectionID) -> AnySupplementary
    ) {
        self.kind = kind
        self.makeSupplementaryProvider = makeSupplementary
    }
    @MainActor func makeSupplementary(sectionID: SectionID) -> AnySupplementary {
        makeSupplementaryProvider(sectionID)
    }

    /// 描述 supplementary 内容版本。
    ///
    /// - Parameter refreshID: 当前 supplementary 内容版本 id。
    /// - Returns: 应用内容版本后的 supplementary。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self
    where RefreshID: Hashable & Sendable {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: AnyListID(refreshID),
                refreshRule: supplementary.refreshRule,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                supportsElementKindMapping: supplementary.supportsElementKindMapping,
                configureVisibleView: supplementary.configureVisibleView,
                tapHandler: supplementary.tapHandler,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 设置 supplementary 的完整刷新规则。
    public func refresh(_ rule: ListSupplementaryRefreshRule) -> Self {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: supplementary.refreshID,
                refreshRule: rule,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                supportsElementKindMapping: supplementary.supportsElementKindMapping,
                configureVisibleView: supplementary.configureVisibleView,
                tapHandler: supplementary.tapHandler,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: supplementary.endDisplayHandler
            )
        }
    }

    /// 分别设置 supplementary 刷新触发和执行动作。
    public func refresh(
        when trigger: ListRefreshTrigger,
        action: ListSupplementaryRefreshAction = .reconfigureVisible(layout: .none)
    ) -> Self {
        refresh(ListSupplementaryRefreshRule(trigger: trigger, action: action))
    }

    /// 给 supplementary 安装 ListKit 管理的点击事件。
    ///
    /// - Parameter handler: supplementary 被点击时调用的闭包。
    /// - Returns: 绑定点击事件后的 supplementary。
    /// - Note: ListKit 只移除自己安装的点击手势，不会清理 view 上已有的其他手势。
    public func onTap(_ handler: @escaping @MainActor (ListContext) -> Void) -> Self {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: supplementary.refreshID,
                refreshRule: supplementary.refreshRule,
                register: supplementary.register,
                viewProvider: { collectionView, elementKind, indexPath, context in
                    let view = supplementary.viewProvider(collectionView, elementKind, indexPath, context)
                    ListTapHandlerInstaller.install(on: view, context: context, handler: handler)
                    return view
                },
                supportsElementKindMapping: supplementary.supportsElementKindMapping,
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
    public func onDisplay(
        _ handler: @escaping @MainActor (UICollectionReusableView, ListContext) -> Void
    ) -> Self {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: supplementary.refreshID,
                refreshRule: supplementary.refreshRule,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                supportsElementKindMapping: supplementary.supportsElementKindMapping,
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
    public func onEndDisplay(
        _ handler: @escaping @MainActor (UICollectionReusableView, ListContext) -> Void
    ) -> Self {
        mapSupplementary { supplementary in
            AnySupplementary(
                identity: supplementary.identity,
                kind: supplementary.kind,
                refreshID: supplementary.refreshID,
                refreshRule: supplementary.refreshRule,
                register: supplementary.register,
                viewProvider: supplementary.viewProvider,
                supportsElementKindMapping: supplementary.supportsElementKindMapping,
                configureVisibleView: supplementary.configureVisibleView,
                tapHandler: supplementary.tapHandler,
                displayHandler: supplementary.displayHandler,
                endDisplayHandler: handler
            )
        }
    }

    private func mapSupplementary(
        _ transform: @escaping @MainActor (AnySupplementary) -> AnySupplementary
    ) -> Self {
        let provider = makeSupplementaryProvider
        return ListSectionSupplementary(kind: kind) { sectionID in
            transform(provider(sectionID))
        }
    }
}

/// 使用指定视图类型和业务身份创建分区附属视图。
///
/// `kind` 须非空且在分区内唯一，用于关联内容与几何；多行自适应网格可映射为不同的 UIKit 地址。
/// `id` 标识业务内容，业务种类或视图类型变化时展示身份也随之变化。
///
/// - Parameters:
///   - viewType: 自动注册和出队的附属视图类型。
///   - kind: 与布局几何声明对应的业务元素种类。
///   - id: 附属视图内容的稳定标识符。
///   - configure: 在主执行器上配置视图的闭包。
/// - Returns: 可放入分区附属视图构建器的内容声明。
@MainActor public func SectionSupplementary<SectionID, ID, View>(
    _ viewType: View.Type, kind: String, id: ID,
    configure: @escaping @MainActor (View, ListContext) -> Void
) -> ListSectionSupplementary<SectionID>
where SectionID: Hashable & Sendable, ID: Hashable & Sendable, View: UICollectionReusableView {
    return ListSectionSupplementary(kind: kind) { sectionID in
        Supplementary(kind, id: id, view: viewType, configure: configure).eraseToAnySupplementary(
            sectionID: sectionID)
    }
}

/// 将已有的附属视图描述关联到所在分区。
///
/// - Parameter supplementary: 包含内容提供者、刷新规则与事件的附属视图描述。
/// - Returns: 保留原元素种类与配置的分区附属视图声明。
@MainActor public func SectionSupplementary<SectionID, ID, View>(
    _ supplementary: Supplementary<ID, View>
) -> ListSectionSupplementary<SectionID>
where SectionID: Hashable & Sendable, ID: Hashable & Sendable, View: UICollectionReusableView {
    ListSectionSupplementary(kind: supplementary.kind) {
        supplementary.eraseToAnySupplementary(sectionID: $0)
    }
}

/// 将已有的附属视图描述关联到所在分区。
///
/// - Parameter supplementary: 包含内容提供者、刷新规则与事件的附属视图描述。
/// - Returns: 保留原元素种类与配置的分区附属视图声明。
@MainActor public func SectionSupplementary<SectionID, ID>(
    _ supplementary: ProviderSupplementary<ID>
) -> ListSectionSupplementary<SectionID>
where SectionID: Hashable & Sendable, ID: Hashable & Sendable {
    ListSectionSupplementary(kind: supplementary.kind) {
        supplementary.eraseToAnySupplementary(sectionID: $0)
    }
}

/// 自定义 supplementary 的描述模型。
///
/// - Note: 常规声明使用 SectionSupplementary；此值可独立组合刷新与事件后放入 supplementary builder。
public struct Supplementary<ID, View>
where ID: Hashable & Sendable, View: UICollectionReusableView {
    private let id: ID
    let kind: String
    private let viewType: View.Type
    private let configure: @MainActor (View, ListContext) -> Void
    private var supplementaryRefreshID: AnyListID?
    private var supplementaryRefreshRule: ListSupplementaryRefreshRule = .automatic
    private var supplementaryTapHandler: (@MainActor (ListContext) -> Void)?
    private var supplementaryDisplayHandler: (@MainActor (View, ListContext) -> Void)?
    private var supplementaryEndDisplayHandler: (@MainActor (View, ListContext) -> Void)?

    /// 创建 supplementary 描述。
    ///
    /// - Parameters:
    ///   - kind: 附属视图的 UIKit 元素种类。
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
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self
    where RefreshID: Hashable & Sendable {
        var copy = self
        copy.supplementaryRefreshID = AnyListID(refreshID)
        return copy
    }

    /// 设置 supplementary 的完整刷新规则。
    public func refresh(_ rule: ListSupplementaryRefreshRule) -> Self {
        var copy = self
        copy.supplementaryRefreshRule = rule
        return copy
    }

    /// 返回使用指定触发条件和动作的附属视图描述副本。
    ///
    /// - Parameters:
    ///   - trigger: 应用列表更新时的刷新触发条件。
    ///   - action: 刷新动作，默认重配可见视图且不额外使布局失效。
    /// - Returns: 应用刷新规则后的描述副本。
    public func refresh(
        when trigger: ListRefreshTrigger,
        action: ListSupplementaryRefreshAction = .reconfigureVisible(layout: .none)
    ) -> Self {
        refresh(ListSupplementaryRefreshRule(trigger: trigger, action: action))
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
    where SectionID: Hashable & Sendable {
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
            refreshRule: supplementaryRefreshRule,
            register: { collectionView, elementKind in
                collectionView.lk.register(viewType, ofKind: elementKind)
            },
            viewProvider: { collectionView, elementKind, indexPath, context in
                let view = collectionView.lk.dequeue(viewType, ofKind: elementKind, for: indexPath)
                configure(view, context)
                ListTapHandlerInstaller.install(
                    on: view,
                    context: context,
                    handler: supplementaryTapHandler
                )
                return view
            },
            supportsElementKindMapping: true,
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

/// 由调用方控制注册和出队的附属视图描述。
///
/// 此类型不提供可见视图的原地配置闭包。默认 `reconfigureVisible` 动作不会重新执行提供者；
/// 需要由刷新规则更新内容时，使用 `reloadSection`，该动作也会重载分区中的条目。
public struct ProviderSupplementary<ID> where ID: Hashable & Sendable {
    private let id: ID
    let kind: String
    private let presentationID: ObjectIdentifier
    private let registerProvider: @MainActor (UICollectionView, String) -> Void
    private let supportsElementKindMapping: Bool
    private let viewProvider: @MainActor (UICollectionView, String, IndexPath, ListContext) -> UICollectionReusableView
    private var supplementaryRefreshID: AnyListID?
    private var supplementaryRefreshRule: ListSupplementaryRefreshRule = .automatic
    private var supplementaryTapHandler: (@MainActor (ListContext) -> Void)?

    /// 用 view 类型作为展示 identity 的 ProviderSupplementary。
    ///
    /// - Parameters:
    ///   - kind: 附属视图的 UIKit 元素种类。
    ///   - id: supplementary 身份。
    ///   - viewType: 用于 presentation identity 和默认注册的 reusable view 类型。
    ///   - register: 可选的自定义注册闭包。
    ///   - viewProvider: 创建或 dequeue reusable view 的闭包。
    /// - Important: 此重载不支持内部元素种类映射；需要映射时使用接收实际元素种类的重载。
    ///   提供者须使用传入的索引路径出队视图。
    public init<View>(
        _ kind: String,
        id: ID,
        view viewType: View.Type,
        register: (@MainActor (UICollectionView) -> Void)? = nil,
        viewProvider:
            @escaping @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionReusableView
    ) where View: UICollectionReusableView {
        self.id = id
        self.kind = kind
        self.presentationID = ObjectIdentifier(viewType)
        self.registerProvider = { collectionView, _ in
            if let register { register(collectionView) }
            else { collectionView.lk.register(viewType, ofKind: kind) }
        }
        self.viewProvider = { collectionView, _, indexPath, context in
            viewProvider(collectionView, indexPath, context)
        }
        self.supportsElementKindMapping = false
    }

    /// 完全自定义 presentation identity 的 ProviderSupplementary。
    ///
    /// - Parameters:
    ///   - kind: 附属视图的 UIKit 元素种类。
    ///   - id: supplementary 身份。
    ///   - presentationID: 自定义展示身份。
    ///   - register: 注册 reusable view 的闭包。
    ///   - viewProvider: 创建或 dequeue reusable view 的闭包。
    /// - Important: 此重载不支持内部元素种类映射；需要映射时使用接收实际元素种类的重载。
    public init(
        _ kind: String,
        id: ID,
        presentationID: ObjectIdentifier,
        register: @escaping @MainActor (UICollectionView) -> Void,
        viewProvider:
            @escaping @MainActor (UICollectionView, IndexPath, ListContext) -> UICollectionReusableView
    ) {
        self.id = id
        self.kind = kind
        self.presentationID = presentationID
        self.registerProvider = { collectionView, _ in register(collectionView) }
        self.viewProvider = { collectionView, _, indexPath, context in
            viewProvider(collectionView, indexPath, context)
        }
        self.supportsElementKindMapping = false
    }

    /// 支持布局内部 kind 映射的 provider。elementKind 与 indexPath 是本次 UIKit 请求，必须原样用于 dequeue。
    /// context.indexPath 则是所属业务 item 的位置；不能用它替代 supplementary 的 dequeue indexPath。
    public init<View>(
        _ kind: String, id: ID, view viewType: View.Type,
        register: (@MainActor (UICollectionView, String) -> Void)? = nil,
        viewProvider: @escaping @MainActor (UICollectionView, String, IndexPath, ListContext) -> UICollectionReusableView
    ) where View: UICollectionReusableView {
        self.id = id
        self.kind = kind
        self.presentationID = ObjectIdentifier(viewType)
        self.registerProvider = register ?? { collectionView, elementKind in
            collectionView.lk.register(viewType, ofKind: elementKind)
        }
        self.viewProvider = viewProvider
        self.supportsElementKindMapping = true
    }

    /// 自定义展示身份的映射 provider；注册和 dequeue 都必须使用传入的实际 elementKind。
    public init(
        _ kind: String, id: ID, presentationID: ObjectIdentifier,
        register: @escaping @MainActor (UICollectionView, String) -> Void,
        viewProvider: @escaping @MainActor (UICollectionView, String, IndexPath, ListContext) -> UICollectionReusableView
    ) {
        self.id = id
        self.kind = kind
        self.presentationID = presentationID
        self.registerProvider = register
        self.viewProvider = viewProvider
        self.supportsElementKindMapping = true
    }

    /// 设置内容刷新版本。
    ///
    /// - Parameter refreshID: 当前 supplementary 内容版本 id。
    /// - Returns: 应用内容版本后的 provider supplementary。
    public func refreshID<RefreshID>(_ refreshID: RefreshID) -> Self
    where RefreshID: Hashable & Sendable {
        var copy = self
        copy.supplementaryRefreshID = AnyListID(refreshID)
        return copy
    }

    /// 设置附属视图的刷新规则；可见重配动作不会再次调用此类型的提供者。
    public func refresh(_ rule: ListSupplementaryRefreshRule) -> Self {
        var copy = self
        copy.supplementaryRefreshRule = rule
        return copy
    }

    /// 返回使用指定触发条件和动作的附属视图描述副本。
    ///
    /// - Parameters:
    ///   - trigger: 应用列表更新时的刷新触发条件。
    ///   - action: 刷新动作；默认可见重配不会再次调用提供者，可用 `reloadSection` 更新内容。
    /// - Returns: 应用刷新规则后的描述副本。
    public func refresh(
        when trigger: ListRefreshTrigger,
        action: ListSupplementaryRefreshAction = .reconfigureVisible(layout: .none)
    ) -> Self {
        refresh(ListSupplementaryRefreshRule(trigger: trigger, action: action))
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
    where SectionID: Hashable & Sendable {
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
            refreshRule: supplementaryRefreshRule,
            register: registerProvider,
            viewProvider: { collectionView, elementKind, indexPath, context in
                let view = viewProvider(collectionView, elementKind, indexPath, context)
                ListTapHandlerInstaller.install(
                    on: view,
                    context: context,
                    handler: supplementaryTapHandler
                )
                return view
            },
            supportsElementKindMapping: supportsElementKindMapping,
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
/// 每次安装时移除 ListKit 自有的旧点击手势与代理；处理器非空时再安装新的手势。
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
        view.addGestureRecognizer(
            ListTapGestureRecognizer(target: proxy, action: #selector(TapProxy.invoke)))
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
