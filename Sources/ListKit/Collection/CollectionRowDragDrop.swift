import UIKit
import UniformTypeIdentifiers

struct ListRowDropTarget {
    let types: [UTType]
    let isTargeted: (@MainActor (Bool) -> Void)?
    let canDrop: @MainActor ([NSItemProvider]) -> Bool
    let perform: @MainActor ([NSItemProvider]) -> Void

    @MainActor
    func acceptedProviders(in session: any UIDropSession) -> [NSItemProvider] {
        let matching = session.items.map(\.itemProvider).filter { provider in
            types.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
        return !matching.isEmpty && canDrop(matching) ? matching : []
    }
}

/// 交互随 cell 存活。UIKit 可以在更新 contentConfiguration 时替换 contentView。
@MainActor
final class CollectionRowDragDrop: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
    private weak var cell: UICollectionViewCell?
    private var drag: UIDragInteraction?
    private var drop: UIDropInteraction?
    private var provider: (@MainActor () -> NSItemProvider)?
    private var target: ListRowDropTarget?
    private var sessions = Set<ObjectIdentifier>()
    private var notify: (@MainActor (Bool) -> Void)?
    let identity: AnyListIdentity

    init(cell: UICollectionViewCell, identity: AnyListIdentity) {
        self.cell = cell
        self.identity = identity
    }

    func configure(provider: (@MainActor () -> NSItemProvider)?, target: ListRowDropTarget?, reorderable: Bool = false) {
        self.provider = provider
        self.target = target
        if provider != nil, drag == nil {
            let interaction = UIDragInteraction(delegate: self)
            interaction.isEnabled = true
            cell?.addInteraction(interaction)
            drag = interaction
        } else if provider == nil, let drag {
            cell?.removeInteraction(drag)
            self.drag = nil
        }
        drag?.allowsSimultaneousRecognitionDuringLift = reorderable
        if target != nil, drop == nil {
            let interaction = UIDropInteraction(delegate: self)
            cell?.addInteraction(interaction)
            drop = interaction
        } else if target == nil, let drop {
            cell?.removeInteraction(drop)
            self.drop = nil
            sessions.removeAll()
            endTargeting()
        }
    }

    isolated deinit {
        if let drag { cell?.removeInteraction(drag) }
        if let drop { cell?.removeInteraction(drop) }
        notify?(false)
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem] {
        guard let cell else { return [] }
        return dragItems(at: session.location(in: cell), in: cell)
    }

    func dragInteraction(
        _ interaction: UIDragInteraction, itemsForAddingTo session: any UIDragSession, withTouchAt point: CGPoint
    ) -> [UIDragItem] {
        guard let cell else { return [] }
        return dragItems(at: point, in: cell)
    }

    private func dragItems(at point: CGPoint, in cell: UICollectionViewCell) -> [UIDragItem] {
        // accessory 位于 contentView 之外，其拖动继续交由系统排序手柄处理。
        let content = cell.contentView
        guard let provider, content.bounds.contains(content.convert(point, from: cell)) else { return [] }
        return [UIDragItem(itemProvider: provider())]
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        return target?.acceptedProviders(in: session).isEmpty == false
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
        guard let target, !target.acceptedProviders(in: session).isEmpty else {
            leave(session)
            return UIDropProposal(operation: .forbidden)
        }
        let wasEmpty = sessions.isEmpty
        sessions.insert(ObjectIdentifier(session))
        if wasEmpty {
            notify = target.isTargeted
            notify?(true)
        }
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        defer { leave(session) }
        guard sessions.contains(ObjectIdentifier(session)), let target else { return }
        let providers = target.acceptedProviders(in: session)
        if !providers.isEmpty { target.perform(providers) }
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) { leave(session) }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) { leave(session) }

    private func leave(_ session: any UIDropSession) {
        if sessions.remove(ObjectIdentifier(session)) != nil, sessions.isEmpty { endTargeting() }
    }

    private func endTargeting() {
        let callback = notify
        notify = nil
        callback?(false)
    }
}

/// UIKit 直接使用原生代理。weak 自动清零没有 didSet，代理析构时需要恢复可见行的交互。
@MainActor
final class ListDragDropDelegateObservation {
    private let refresh: () -> Void

    init(refresh: @escaping () -> Void) {
        self.refresh = refresh
    }

    func observe(_ delegate: AnyObject?) {
        guard let delegate else { return }
        let lifetime: DelegateLifetime
        if let existing = objc_getAssociatedObject(delegate, &DelegateLifetime.key) as? DelegateLifetime {
            lifetime = existing
        } else {
            lifetime = DelegateLifetime()
            objc_setAssociatedObject(delegate, &DelegateLifetime.key, lifetime, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        lifetime.observers.add(self)
    }

    @MainActor private final class DelegateLifetime {
        static var key: UInt8 = 0
        let observers = NSHashTable<ListDragDropDelegateObservation>.weakObjects()
        isolated deinit {
            for observer in observers.allObjects { observer.refresh() }
        }
    }
}
