import ListKit
import UIKit
import UniformTypeIdentifiers

@MainActor
final class DragDropDemoViewController: UIViewController {
    private let list = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private lazy var adapter = CollectionListAdapter<Int>(collectionView: list)
    private let sampleImageData: Data = {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).pngData { _ in
            UIImage(systemName: "photo")?.draw(in: CGRect(origin: .zero, size: size))
        }
    }()
    private var receivedText: String?
    private var receivedImage = false
    private var inboxOpen = true
    private var order = ["First", "Second", "Third"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Drag and Drop"
        view.backgroundColor = .systemGroupedBackground
        list.frame = view.bounds
        list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        list.isEditing = true
        list.reorderingCadence = .immediate
        list.dragInteractionEnabled = true
        adapter.collectionDelegate = self
        list.setCollectionViewLayout(adapter.makeCompositionalLayout(), animated: false)
        view.addSubview(list)
        view.addInteraction(UIDropInteraction(delegate: self))
        let toggle = UIBarButtonItem(title: "Close Inbox", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            inboxOpen.toggle()
            navigationItem.rightBarButtonItem?.title = inboxOpen ? "Close Inbox" : "Open Inbox"
        })
        toggle.accessibilityIdentifier = "toggle-inbox"
        navigationItem.rightBarButtonItem = toggle
        render()
    }

    private func render() {
        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                row("image", title: receivedImage ? "Page received image" : "Drag an image")
                    .onDrag { [sampleImageData] in
                        NSItemProvider(item: sampleImageData as NSData, typeIdentifier: UTType.png.identifier)
                    }
                row("source", title: "Drag this text")
                    .onDrag { NSItemProvider(object: "Hello from ListKit" as NSString) }
            } layout: {
                UIKitListLayout(appearance: .insetGrouped)
            }
            ListSection(1) {
                for name in order {
                    row(name, title: name, reorderable: true)
                        .onDrag { NSItemProvider(object: name as NSString) }
                        .onMove { [weak self] source, destination in
                            guard let self else { return }
                            guard source.section == destination.section else {
                                render()
                                return
                            }
                            let moved = order.remove(at: source.item)
                            order.insert(moved, at: destination.item)
                            title = "Moved " + name
                        }
                }
            } layout: {
                UIKitListLayout(appearance: .insetGrouped)
            }
            ListSection(2) {
                row("inbox", title: receivedText ?? "Drop text here")
                    .onDrop(of: [.plainText], isTargeted: { [weak self] inside in
                        self?.title = inside ? "Release to copy text" : "Drag and Drop"
                    }, canDrop: { [weak self] _ in self?.inboxOpen == true }) { [weak self] providers in
                        guard let provider = providers.first else { return }
                        provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                            guard let text = value as? String else { return }
                            Task { @MainActor in
                                self?.receivedText = text
                                self?.render()
                            }
                        }
                    }
            } layout: {
                UIKitListLayout(appearance: .insetGrouped)
            }
        }
    }

    private func row(_ id: String, title: String, reorderable: Bool = false) -> Row<String, String, UICollectionViewListCell> {
        Row(id, model: title, cell: UICollectionViewListCell.self) { cell, title, _ in
            var content = cell.defaultContentConfiguration()
            content.text = title
            cell.contentConfiguration = content
            cell.accessories = reorderable ? [.reorder(displayed: .always)] : []
            cell.accessibilityIdentifier = id
        }
    }
}

extension DragDropDemoViewController: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier])
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        receivedImage = true
        render()
    }
}

extension DragDropDemoViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveOfItemFromOriginalIndexPath originalIndexPath: IndexPath,
        atCurrentIndexPath currentIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        return originalIndexPath.section == proposedIndexPath.section ? proposedIndexPath : currentIndexPath
    }
}
