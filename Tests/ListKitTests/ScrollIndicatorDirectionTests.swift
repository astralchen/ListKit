import UIKit
import XCTest
@testable import ListKit

@MainActor
final class ScrollIndicatorDirectionTests: XCTestCase {
    func testCollectionAndTablePreserveIndicatorConfigurationAcrossDirectionChanges() {
        for usesTable in [false, true] {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
            let controller = UIViewController()
            window.rootViewController = controller
            let scroll: UIScrollView
            let setDirection: (UITraitEnvironmentLayoutDirection) -> Void
            if usesTable {
                let table = UITableView(frame: window.bounds)
                let adapter = TableListAdapter<Int>(tableView: table)
                adapter.apply(transaction: .disabled) {
                    TableSection(0) {
                        for index in 0..<60 {
                            TableRow(index, model: (), cell: UITableViewCell.self) { _, _, _ in }
                        }
                    }.layout { TableLayout().rowHeight(.fixed(50)) }
                }
                scroll = table
                setDirection = { adapter.layoutDirection = $0 }
            } else {
                let collection = UICollectionView(frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
                let adapter = CollectionListAdapter<Int>(collectionView: collection)
                collection.collectionViewLayout = adapter.makeCompositionalLayout()
                adapter.apply(transaction: .disabled) {
                    ListSection(0) {
                        for index in 0..<60 {
                            Row(index, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
                        }
                    } layout: {
                        GridLayout(tracks: 2).itemMainAxisSize(.fixed(80))
                    }
                }
                scroll = collection
                setDirection = { adapter.layoutDirection = $0 }
            }
            scroll.semanticContentAttribute = .forceLeftToRight
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.automaticallyAdjustsScrollIndicatorInsets = false
            let vertical = UIEdgeInsets(top: 7, left: 11, bottom: 9, right: 13)
            let horizontal = UIEdgeInsets(top: 3, left: 5, bottom: 17, right: 19)
            scroll.verticalScrollIndicatorInsets = vertical
            scroll.horizontalScrollIndicatorInsets = horizontal
            controller.view.addSubview(scroll)
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            render(scroll, in: window)
            scroll.contentOffset = CGPoint(x: 0, y: 100)
            render(scroll, in: window)
            let offset = scroll.contentOffset

            for direction in [UITraitEnvironmentLayoutDirection.rightToLeft, .leftToRight, .rightToLeft, .unspecified] {
                setDirection(direction)
                render(scroll, in: window)
                XCTAssertEqual(scroll.verticalScrollIndicatorInsets, vertical)
                XCTAssertEqual(scroll.horizontalScrollIndicatorInsets, horizontal)
                XCTAssertFalse(scroll.automaticallyAdjustsScrollIndicatorInsets)
                XCTAssertEqual(scroll.contentOffset, offset)
                XCTAssertTrue(scroll.showsVerticalScrollIndicator)
            }
            setDirection(.rightToLeft)
            scroll.frame.size.width = 280
            render(scroll, in: window)
            XCTAssertEqual(scroll.verticalScrollIndicatorInsets, vertical)
        }
    }

    func testHiddenIndicatorsAndInsetsRemainUnchanged() {
        for scroll in [UIScrollView(), UITableView()] {
            scroll.showsVerticalScrollIndicator = false
            scroll.showsHorizontalScrollIndicator = false
            let insets = UIEdgeInsets(top: 5, left: 7, bottom: 11, right: 13)
            scroll.verticalScrollIndicatorInsets = insets
            let direction = ListLayoutDirectionOverride()
            for value in [UITraitEnvironmentLayoutDirection.rightToLeft, .leftToRight, .unspecified] {
                direction.apply(value, to: scroll)
                direction.refreshScrollIndicators(in: scroll)
                XCTAssertFalse(scroll.showsVerticalScrollIndicator)
                XCTAssertFalse(scroll.showsHorizontalScrollIndicator)
                XCTAssertEqual(scroll.verticalScrollIndicatorInsets, insets)
                XCTAssertEqual(scroll.horizontalScrollIndicatorInsets, .zero)
                XCTAssertTrue(scroll.automaticallyAdjustsScrollIndicatorInsets)
            }
        }
    }

    func testCollectionIndicatorsBeforeFirstLayoutPreserveBusinessConfiguration() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collection.semanticContentAttribute = .forceLeftToRight
        collection.contentInsetAdjustmentBehavior = .never
        let contentInsets = UIEdgeInsets(top: 17, left: 7, bottom: 19, right: 9)
        let vertical = UIEdgeInsets(top: 5, left: 11, bottom: 7, right: 13)
        let horizontal = UIEdgeInsets(top: 3, left: 5, bottom: 17, right: 19)
        collection.contentInset = contentInsets
        collection.verticalScrollIndicatorInsets = vertical
        collection.horizontalScrollIndicatorInsets = horizontal
        collection.automaticallyAdjustsScrollIndicatorInsets = false
        collection.showsVerticalScrollIndicator = false
        collection.showsHorizontalScrollIndicator = false
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        // 方向可以先于布局对象、内容和 window 设置。
        adapter.layoutDirection = .rightToLeft
        collection.collectionViewLayout = adapter.makeCompositionalLayout()
        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                for index in 0..<60 {
                    Row(index, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
                }
            } layout: { GridLayout(tracks: 2).itemMainAxisSize(.fixed(80)) }
        }
        controller.view.addSubview(collection)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        render(collection, in: window)
        XCTAssertFalse(collection.showsVerticalScrollIndicator)
        XCTAssertFalse(collection.showsHorizontalScrollIndicator)
        XCTAssertEqual(collection.contentInset, contentInsets)
        XCTAssertEqual(collection.horizontalScrollIndicatorInsets, horizontal)
        XCTAssertEqual(collection.verticalScrollIndicatorInsets, vertical)
        XCTAssertFalse(collection.automaticallyAdjustsScrollIndicatorInsets)
        collection.showsVerticalScrollIndicator = true
        collection.contentOffset.y = 300
        render(collection, in: window)

        adapter.layoutDirection = .leftToRight
        render(collection, in: window)
        XCTAssertEqual(collection.verticalScrollIndicatorInsets, vertical)
        XCTAssertFalse(collection.automaticallyAdjustsScrollIndicatorInsets)

        let updatedVertical = UIEdgeInsets(top: 2, left: 3, bottom: 4, right: 5)
        collection.verticalScrollIndicatorInsets = updatedVertical
        collection.automaticallyAdjustsScrollIndicatorInsets = true
        adapter.layoutDirection = .rightToLeft
        render(collection, in: window)
        adapter.layoutDirection = .unspecified
        render(collection, in: window)
        XCTAssertEqual(collection.verticalScrollIndicatorInsets, updatedVertical)
        XCTAssertTrue(collection.automaticallyAdjustsScrollIndicatorInsets)
        XCTAssertTrue(collection.showsVerticalScrollIndicator)
        XCTAssertFalse(collection.showsHorizontalScrollIndicator)
        XCTAssertEqual(collection.contentInset, contentInsets)
        XCTAssertEqual(collection.horizontalScrollIndicatorInsets, horizontal)
    }

    func testHorizontalCollectionKeepsFirstItemVisibleAndIndicatorSettings() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        let controller = UIViewController()
        window.rootViewController = controller
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collection.semanticContentAttribute = .forceLeftToRight
        collection.contentInsetAdjustmentBehavior = .never
        collection.automaticallyAdjustsScrollIndicatorInsets = false
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        collection.collectionViewLayout = adapter.makeCompositionalLayout(
            configuration: .init(scrollDirection: .horizontal, contentInsetsReference: .none))
        controller.view.addSubview(collection)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                for index in 0..<40 {
                    Row(index, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
                }
            } layout: { GridLayout(tracks: 1).itemMainAxisSize(.fixed(80)).lineSpacing(8) }
        }
        for direction in [UITraitEnvironmentLayoutDirection.leftToRight, .rightToLeft, .unspecified] {
            adapter.layoutDirection = direction
            render(collection, in: window)
            XCTAssertTrue(collection.showsHorizontalScrollIndicator)
            XCTAssertFalse(collection.automaticallyAdjustsScrollIndicatorInsets)
            XCTAssertEqual(collection.horizontalScrollIndicatorInsets, .zero)
            XCTAssertNotNil(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        }
    }

    private func render(_ scroll: UIScrollView, in window: UIWindow) {
        for _ in 0..<3 {
            window.layoutIfNeeded()
            scroll.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

}
