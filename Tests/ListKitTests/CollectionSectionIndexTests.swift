import XCTest
import UIKit
@testable import ListKit

@MainActor
final class CollectionSectionIndexTests: XCTestCase {
    func testGeometryClampsDraggingAndAccessibilitySelectsInOrder() {
        let index = CollectionSectionIndexView(frame: CGRect(x: 0, y: 0, width: 44, height: 200))
        var selections: [Int] = []
        index.update(titles: ["A", "B", "#"]) { selections.append($0) }
        XCTAssertEqual(index.titleIndex(at: CGPoint(x: 22, y: -50)), 0)
        XCTAssertEqual(index.titleIndex(at: CGPoint(x: 22, y: 500)), 2)
        for item in 0..<3 {
            XCTAssertEqual(index.titleIndex(at: CGPoint(x: 22, y: index.rectForTitle(at: item).midY)), item)
        }
        index.accessibilityIncrement()
        index.accessibilityIncrement()
        index.accessibilityDecrement()
        XCTAssertEqual(selections, [0, 1, 0])
        XCTAssertEqual(index.accessibilityValue, "A")
        index.update(titles: [], selection: nil)
        index.accessibilityIncrement()
        XCTAssertTrue(index.isHidden)
        XCTAssertNil(index.selectedTitle)
        XCTAssertNil(index.titleIndex(at: .zero))
        XCTAssertEqual(selections, [0, 1, 0])
    }

    func testBindingUpdatesTitlesAndResolvesReorderedSections() async {
        let view = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<String>(collectionView: view)
        view.collectionViewLayout = adapter.makeCompositionalLayout()
        let index = CollectionSectionIndexView()
        adapter.sectionIndexView = index
        func section(_ id: String, title: String?) -> ListSection<String> {
            ListSection(id) {
                ForEach(0..<12, id: \.self) { row in
                    Row(row, model: "\(id)-\(row)", cell: UICollectionViewListCell.self) { cell, name, _ in
                        var content = UIListContentConfiguration.cell()
                        content.text = name
                        cell.contentConfiguration = content
                    }
                }
            }.indexTitle(title)
        }
        _ = await adapter.apply(transaction: .disabled) {
            section("entry", title: nil)
            ListSection("empty") {}.indexTitle("Empty")
            section("a", title: "A")
            section("b", title: "B")
        }
        view.layoutIfNeeded()
        XCTAssertEqual(index.titles, ["A", "B"])
        XCTAssertNil(adapter.indexTitles(for: view))
        index.accessibilityIncrement()
        index.accessibilityIncrement()
        let offset = view.contentOffset.y
        XCTAssertGreaterThan(offset, 0)
        _ = await adapter.apply(transaction: .disabled) {
            section("b", title: "B")
            section("a", title: "A")
        }
        view.layoutIfNeeded()
        index.accessibilityIncrement()
        XCTAssertEqual(index.selectedTitle, "B")
        XCTAssertEqual(view.contentOffset.y, -view.adjustedContentInset.top, accuracy: 1)
        _ = await adapter.apply(transaction: .disabled) {
            section("b", title: "A")
            section("a", title: "A")
        }
        index.accessibilityIncrement()
        index.accessibilityIncrement()
        XCTAssertGreaterThan(view.contentOffset.y, 0, "相同标题仍按独立分组 identity 定位")
        _ = await adapter.apply(transaction: .disabled) {
            section("b", title: nil)
            section("a", title: nil)
        }
        XCTAssertTrue(index.isHidden)
        _ = await adapter.apply(transaction: .disabled) { section("a", title: "A") }
        adapter.sectionIndexView = nil
        XCTAssertTrue(index.isHidden)
        XCTAssertEqual(adapter.indexTitles(for: view), ["A"])
    }

    func testCompactHeightKeepsAllTouchTargetsWithoutOverlappingGlyphs() {
        let index = CollectionSectionIndexView(frame: CGRect(x: 0, y: 0, width: 44, height: 120))
        index.update(titles: Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), selection: nil)
        XCTAssertEqual(index.displayedTitleIndices.first, 0)
        XCTAssertEqual(index.displayedTitleIndices.last, 25)
        for (first, second) in zip(index.displayedTitleIndices, index.displayedTitleIndices.dropFirst()) {
            XCTAssertGreaterThanOrEqual(index.rectForTitle(at: second).midY - index.rectForTitle(at: first).midY, 14)
        }
        for item in 0..<26 {
            XCTAssertEqual(index.titleIndex(at: CGPoint(x: 22, y: index.rectForTitle(at: item).midY)), item)
        }
    }

    func testViewportInsetsKeepIndexBelowNavigationAndAboveToolbar() {
        let index = CollectionSectionIndexView(frame: CGRect(x: 0, y: 0, width: 44, height: 800))
        index.contentInsets = UIEdgeInsets(top: 200, left: 0, bottom: 100, right: 0)
        index.update(titles: Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), selection: nil)
        XCTAssertGreaterThanOrEqual(index.rectForTitle(at: 0).minY, 200)
        XCTAssertLessThanOrEqual(index.rectForTitle(at: 25).maxY, 700)
        XCTAssertFalse(index.point(inside: CGPoint(x: 22, y: 100), with: nil))
        XCTAssertFalse(index.point(inside: CGPoint(x: 22, y: 750), with: nil))
    }

    func testAdapterDoesNotRetainIndexOrCollectionView() {
        var view: UICollectionView? = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<String>(collectionView: view!)
        var index: CollectionSectionIndexView? = CollectionSectionIndexView()
        weak var releasedIndex = index
        weak var releasedView = view
        adapter.sectionIndexView = index
        index = nil
        view = nil
        XCTAssertNil(releasedIndex)
        XCTAssertNil(releasedView)
    }
}
