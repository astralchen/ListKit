import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import ListKit

@MainActor
final class CollectionRowDragDropTests: XCTestCase {
    func testNativeOverrideReleaseRestoresVisibleRowWithoutApply() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let list = fixture.list
        let adapter = fixture.adapter
        let row = Row(1, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
        var drags = 0
        await adapter.apply(transaction: .disabled) {
            ListSection(0) {
                row.onDrag {
                    drags += 1
                    return NSItemProvider(object: "text" as NSString)
                }.onDrop(of: [.plainText]) { _ in }.onMove { _, _ in }
            }
        }
        list.layoutIfNeeded()
        let cell = try XCTUnwrap(list.cellForItem(at: IndexPath(item: 0, section: 0)))
        func drag() -> UIDragInteraction? {
            cell.interactions.compactMap { $0 as? UIDragInteraction }.first { $0.delegate is CollectionRowDragDrop }
        }
        func drop() -> UIDropInteraction? {
            cell.interactions.compactMap { $0 as? UIDropInteraction }.first { $0.delegate is CollectionRowDragDrop }
        }
        XCTAssertNotNil(drag())
        XCTAssertNotNil(drop())
        var native: NativeDragDelegate? = NativeDragDelegate()
        adapter.dragDelegate = native
        XCTAssertTrue(list.dragDelegate === native)
        XCTAssertNil(drag())
        XCTAssertNotNil(drop())
        adapter.dropDelegate = native
        XCTAssertNil(drop())
        native = nil
        XCTAssertNil(list.dragDelegate)
        XCTAssertNil(list.dropDelegate)
        let restored = try XCTUnwrap(drag())
        XCTAssertTrue(restored.allowsSimultaneousRecognitionDuringLift)
        XCTAssertNotNil(drop())
        let originalContent = cell.contentView
        cell.contentConfiguration = UIListContentConfiguration.cell()
        cell.layoutIfNeeded()
        XCTAssertFalse(originalContent === cell.contentView)
        XCTAssertTrue(drag() === restored)
        XCTAssertNotNil(drop())
        let session = TestDragSession()
        session.point = CGPoint(x: cell.bounds.midX, y: cell.bounds.midY)
        let outside = CGPoint(x: cell.bounds.maxX + 1, y: cell.bounds.midY)
        XCTAssertTrue(restored.delegate?.dragInteraction?(restored, itemsForAddingTo: session, withTouchAt: outside).isEmpty == true)
        XCTAssertEqual(drags, 0)
        XCTAssertEqual(restored.delegate?.dragInteraction(restored, itemsForBeginning: session).count, 1)
        XCTAssertEqual(drags, 1)
        await adapter.apply(transaction: .disabled) { ListSection(0) { row } }
        XCTAssertNil(drag())
        XCTAssertNil(drop())
    }

    func testDropChecksTypeAndBusinessConditionAtEntryHoverAndCommit() async throws {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let row = Row(1, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
        var hover: [Bool] = []
        var enabled = true
        var delivered: [NSItemProvider] = []
        await fixture.adapter.apply(transaction: .disabled) {
            ListSection(0) {
                row.onDrop(of: [.plainText], isTargeted: { hover.append($0) }, canDrop: { _ in enabled }) {
                    delivered += $0
                }
            }
        }
        fixture.list.layoutIfNeeded()
        let cell = try XCTUnwrap(fixture.list.cellForItem(at: IndexPath(item: 0, section: 0)))
        let drop = try XCTUnwrap(cell.interactions.compactMap { $0 as? UIDropInteraction }.first { $0.delegate is CollectionRowDragDrop })
        let delegate = try XCTUnwrap(drop.delegate as? CollectionRowDragDrop)
        let session = TestDropSession()
        session.items = [UIDragItem(itemProvider: NSItemProvider(object: UIImage()))]
        XCTAssertFalse(delegate.dropInteraction(drop, canHandle: session))
        let text = NSItemProvider(object: "text" as NSString)
        session.items.append(UIDragItem(itemProvider: text))
        enabled = false
        XCTAssertFalse(delegate.dropInteraction(drop, canHandle: session))
        XCTAssertEqual(delegate.dropInteraction(drop, sessionDidUpdate: session).operation, .forbidden)
        XCTAssertTrue(hover.isEmpty)
        enabled = true
        XCTAssertTrue(delegate.dropInteraction(drop, canHandle: session))
        XCTAssertEqual(delegate.dropInteraction(drop, sessionDidUpdate: session).operation, .copy)
        enabled = false
        delegate.dropInteraction(drop, performDrop: session)
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertEqual(hover, [true, false])
        enabled = true
        XCTAssertEqual(delegate.dropInteraction(drop, sessionDidUpdate: session).operation, .copy)
        delegate.dropInteraction(drop, performDrop: session)
        XCTAssertEqual(delivered, [text])
        XCTAssertEqual(delegate.dropInteraction(drop, sessionDidUpdate: session).operation, .copy)
        await fixture.adapter.apply(transaction: .disabled) { ListSection(0) { row } }
        delegate.dropInteraction(drop, sessionDidEnd: session)
        XCTAssertEqual(hover, [true, false, true, false, true, false])
    }

    @MainActor private final class Fixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let list: UICollectionView
        let adapter: CollectionListAdapter<Int>

        init() {
            list = UICollectionView(frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
            adapter = CollectionListAdapter(collectionView: list)
            let controller = UIViewController()
            window.rootViewController = controller
            controller.view.addSubview(list)
            window.makeKeyAndVisible()
        }
    }
}

@MainActor
private class TestSession: NSObject, UIDragDropSession {
    var items: [UIDragItem] = []
    var point = CGPoint.zero
    let allowsMoveOperation = true
    let isRestrictedToDraggingApplication = false
    func location(in view: UIView) -> CGPoint { point }
    func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool { false }
    func canLoadObjects(ofClass aClass: any NSItemProviderReading.Type) -> Bool { false }
}

@MainActor
private final class TestDragSession: TestSession, UIDragSession {
    var localContext: Any?
}

@MainActor
private final class TestDropSession: TestSession, UIDropSession {
    var localDragSession: (any UIDragSession)? { nil }
    var progressIndicatorStyle: UIDropSessionProgressIndicatorStyle = .none
    let progress = Progress(totalUnitCount: 1)
    func loadObjects(
        ofClass aClass: any NSItemProviderReading.Type,
        completion: @escaping ([any NSItemProviderReading]) -> Void
    ) -> Progress { progress }
}

@MainActor
private final class NativeDragDelegate: NSObject, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {}
    func collectionView(
        _ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath
    ) -> [UIDragItem] { [] }
}
