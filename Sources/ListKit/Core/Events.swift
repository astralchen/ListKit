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
public struct ListContext: @unchecked Sendable {
    public let sectionID: AnyListID
    public let indexPath: IndexPath
    public unowned let collectionView: UICollectionView

    private let eventDispatcher: @MainActor (any ListEvent, ListContext) -> Void

    /// 创建事件上下文。
    ///
    /// - Parameters:
    ///   - sectionID: 当前 section 的类型擦除 id。
    ///   - indexPath: 当前 cell 或 supplementary 的 index path。
    ///   - collectionView: 当前 collection view。
    ///   - eventDispatcher: adapter 持有的事件分发闭包。
    /// - Note: 这个初始化器仅供 ListKit 内部构造 context；页面通过 row/supplementary 的
    /// configure 或事件闭包接收 `ListContext`。
    init(
        sectionID: AnyListID,
        indexPath: IndexPath,
        collectionView: UICollectionView,
        eventDispatcher: @escaping @MainActor (any ListEvent, ListContext) -> Void
    ) {
        self.sectionID = sectionID
        self.indexPath = indexPath
        self.collectionView = collectionView
        self.eventDispatcher = eventDispatcher
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
}
