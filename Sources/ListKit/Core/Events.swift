import UIKit

// MARK: - Events

/// 自定义业务事件标记协议。
public protocol ListEvent: Sendable {}

/// Row/Header/Footer 配置和事件闭包收到的上下文。
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
    /// 当前 row 或 supplementary 的稳定业务 id。
    public var itemID: AnyListID { identity.rowID }
    /// 事件发生时的位置。列表变化后该位置可能失效，跨刷新逻辑应优先使用 `identity`。
    public let indexPath: IndexPath
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
    ///   - indexPath: 当前 cell 或 supplementary 的 index path。
    ///   - collectionView: 当前 collection view。
    ///   - eventDispatcher: adapter 持有的事件分发闭包。
    /// - Note: 这个初始化器仅供 ListKit 内部构造 context；页面通过 row/supplementary 的
    /// configure 或事件闭包接收 `ListContext`。
    init(
        identity: AnyListIdentity,
        indexPath: IndexPath,
        collectionView: UICollectionView,
        eventDispatcher: @escaping @MainActor (any ListEvent, ListContext) -> Void
    ) {
        self.identity = identity
        self.indexPath = indexPath
        self.collectionViewReference = ListCollectionViewReference(collectionView)
        self.eventDispatcher = eventDispatcher
    }

    @available(*, deprecated, message: "Pass a stable AnyListIdentity instead of a positional sectionID.")
    init(
        sectionID: AnyListID,
        indexPath: IndexPath,
        collectionView: UICollectionView,
        eventDispatcher: @escaping @MainActor (any ListEvent, ListContext) -> Void
    ) {
        self.init(
            identity: AnyListIdentity(
                sectionID: sectionID,
                rowID: AnyListID(indexPath.item),
                presentationID: ObjectIdentifier(LegacyListContextPresentation.self)
            ),
            indexPath: indexPath,
            collectionView: collectionView,
            eventDispatcher: eventDispatcher
        )
    }

    /// 向 adapter 发送业务事件。
    ///
    /// - Parameter event: 遵守 `ListEvent` 的业务事件。
    @MainActor public func send<Event>(_ event: Event) where Event: ListEvent {
        eventDispatcher(event, self)
    }

    /// 取回强类型 sectionID，避免页面在事件里手动保存额外状态。
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

private final class LegacyListContextPresentation {}
