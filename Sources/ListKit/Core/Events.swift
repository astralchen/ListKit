import UIKit

// MARK: - Events

/// 自定义列表事件标记协议。
public protocol ListEvent: Sendable {}

/// 集合视图条目与附属视图的配置和事件上下文。
///
/// - Usage:
/// ```swift
/// Row(model: user, id: \.userID, cell: UserCell.self) { cell, user, context in
///     cell.onAvatarTap = {
///         context.send(UserListEvent.avatarTap(userID: user.userID))
///     }
/// }
/// ```
@MainActor
public struct ListContext {
    /// 当前 row 或 supplementary 的稳定展示身份。
    public let identity: AnyListIdentity
    /// 当前 section 的稳定身份。
    public var sectionID: AnyListID { identity.sectionID }
    /// 当前 row 或 supplementary 的数据 ID。附属视图省略 elementID 时得到 DefaultSupplementaryID。
    public var itemID: AnyListID { identity.rowID }
    /// 创建上下文时保存的业务位置，不会随后续列表更新自动改变。
    /// 条目附属视图使用所属条目的位置；查询实际 UIKit 附属视图地址时使用适配器的地址转换接口。
    /// 若徽章事件需要在重排后找到所属条目，在回调中用 itemIdentity(at:) 保存该条目的身份，之后用 indexPath(for:) 重新定位。
    public let indexPath: IndexPath
    /// 离屏尺寸测量时为 true。配置闭包可能重复执行，可据此跳过图片请求等非布局副作用。
    /// 测量期间 send 不派发事件，框架也不执行展示、预取及交互事件绑定。
    public let isMeasuring: Bool
    private let collectionViewReference: ListCollectionViewReference

    /// 当前 collection view。
    ///
    /// - Important: context 被异步保存且列表已经释放时访问会触发前置条件失败；
    ///   需要容忍释放的代码请使用 `collectionViewIfAvailable`。
    public var collectionView: UICollectionView {
        guard let collectionView = collectionViewReference.collectionView else {
            preconditionFailure("ListKit: ListContext collectionView was released")
        }
        return collectionView
    }

    /// 列表仍存活时返回 collection view。
    public var collectionViewIfAvailable: UICollectionView? {
        collectionViewReference.collectionView
    }

    private let eventDispatcher: @MainActor (any ListEvent, ListContext) -> Void

    /// 创建事件上下文。
    ///
    /// - Parameters:
    ///   - identity: 当前 row 或 supplementary 的稳定展示身份。
    ///   - indexPath: 条目的业务位置；条目附属视图使用所属条目位置，边界视图使用其分区内位置。
    ///   - collectionView: 当前 collection view。
    ///   - eventDispatcher: adapter 持有的事件分发闭包。
    /// - Note: 这个初始化器仅供 ListKit 内部构造 context；调用方通过 row/supplementary 的
    /// configure 或事件闭包接收 `ListContext`。
    init(
        identity: AnyListIdentity,
        indexPath: IndexPath,
        collectionView: UICollectionView,
        isMeasuring: Bool = false,
        eventDispatcher: @escaping @MainActor (any ListEvent, ListContext) -> Void
    ) {
        self.isMeasuring = isMeasuring
        self.identity = identity
        self.indexPath = indexPath
        self.collectionViewReference = ListCollectionViewReference(collectionView)
        self.eventDispatcher = eventDispatcher
    }

    /// 向 adapter 发送列表事件。
    ///
    /// - Parameter event: 遵守 `ListEvent` 的事件值。
    @MainActor public func send<Event>(_ event: Event) where Event: ListEvent {
        guard !isMeasuring else { return }
        eventDispatcher(event, self)
    }

    /// 取回强类型 sectionID，避免调用方在事件处理期间维护重复状态。
    ///
    /// - Parameter type: 要恢复的 section id 类型。
    /// - Returns: 类型匹配时返回原始 section id，否则返回 `nil`。
    public func section<ID>(as type: ID.Type = ID.self) -> ID? where ID: Hashable & Sendable {
        sectionID.typed(type)
    }

    /// 取回强类型 item/row id。
    public func item<ID>(as type: ID.Type = ID.self) -> ID? where ID: Hashable & Sendable {
        itemID.typed(type)
    }

    /// `item(as:)` 的 row 语义别名。
    public func row<ID>(as type: ID.Type = ID.self) -> ID? where ID: Hashable & Sendable {
        item(as: type)
    }
}

@MainActor
private final class ListCollectionViewReference {
    weak var collectionView: UICollectionView?

    init(_ collectionView: UICollectionView) {
        self.collectionView = collectionView
    }
}
