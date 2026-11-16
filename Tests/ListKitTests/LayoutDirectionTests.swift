import UIKit
import XCTest
@testable import ListKit

@MainActor
final class LayoutDirectionTests: XCTestCase {
    func testDefaultDoesNotChangeExistingEnvironmentAndResetRestoresIt() {
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let table = UITableView()
        for view in [collection, table] as [UIView] {
            view.semanticContentAttribute = .playback
            if #available(iOS 17.0, *) { view.traitOverrides.layoutDirection = .rightToLeft }
        }
        let collectionAdapter = CollectionListAdapter<Int>(collectionView: collection)
        let tableAdapter = TableListAdapter<Int>(tableView: table)
        XCTAssertEqual(collectionAdapter.layoutDirection, .unspecified)
        XCTAssertEqual(tableAdapter.layoutDirection, .unspecified)
        for view in [collection, table] as [UIView] {
            XCTAssertEqual(view.semanticContentAttribute, .playback)
        }
        collectionAdapter.layoutDirection = .leftToRight
        tableAdapter.layoutDirection = .leftToRight
        collectionAdapter.layoutDirection = .rightToLeft
        tableAdapter.layoutDirection = .rightToLeft
        collectionAdapter.layoutDirection = .unspecified
        tableAdapter.layoutDirection = .unspecified
        for view in [collection, table] as [UIView] {
            XCTAssertEqual(view.semanticContentAttribute, .playback)
            if #available(iOS 17.0, *) {
                XCTAssertTrue(view.traitOverrides.contains(UITraitLayoutDirection.self))
                XCTAssertEqual(view.traitOverrides.layoutDirection, .rightToLeft)
            }
        }
    }

    func testResetRemovesOnlyDirectionOverrideAndResumesInheritance() throws {
        guard #available(iOS 17.0, *) else { return }
        let parent = UIView()
        let table = UITableView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(parent)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        parent.addSubview(table)
        parent.traitOverrides.layoutDirection = .rightToLeft
        parent.updateTraitsIfNeeded()
        table.traitOverrides.userInterfaceStyle = .dark
        let adapter = TableListAdapter<Int>(tableView: table)
        adapter.layoutDirection = .leftToRight
        table.updateTraitsIfNeeded()
        XCTAssertEqual(table.traitCollection.layoutDirection, .leftToRight)
        adapter.layoutDirection = .unspecified
        table.updateTraitsIfNeeded()
        XCTAssertFalse(table.traitOverrides.contains(UITraitLayoutDirection.self))
        XCTAssertEqual(table.traitCollection.layoutDirection, .rightToLeft)
        XCTAssertEqual(table.traitOverrides.userInterfaceStyle, .dark)
        parent.traitOverrides.layoutDirection = .leftToRight
        parent.updateTraitsIfNeeded()
        table.updateTraitsIfNeeded()
        XCTAssertEqual(table.traitCollection.layoutDirection, .leftToRight)
    }

    func testGridSwitchMirrorsRenderedFramesExactlyOnceWithoutReapplying() throws {
        let f = LayoutFixture(width: 400, count: 6)
        defer { f.close() }
        f.apply(GridLayout(tracks: [.init(.fixed(70)), .init(.fixed(90))])
            .itemMainAxisSize(.fixed(50)).alignment(.start).trackSpacing(12)
            .sectionInsets(.init(top: 0, leading: 20, bottom: 0, trailing: 40)))
        f.render()
        let layout = f.collection.collectionViewLayout
        func frames() throws -> [CGRect] {
            try (0..<2).map {
                let cell = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: $0, section: 0)))
                return cell.convert(cell.bounds, to: f.window)
            }
        }
        let ltr = try frames()
        XCTAssertEqual(ltr[0].minX, 20, accuracy: 0.5)
        f.adapter.layoutDirection = .rightToLeft
        f.render()
        let rtl = try frames()
        for index in 0..<2 {
            XCTAssertEqual(rtl[index].minX, 400 - ltr[index].maxX, accuracy: 0.5)
            XCTAssertEqual(rtl[index].size, ltr[index].size)
        }
        XCTAssertFalse(f.collection.collectionViewLayout === layout)
        XCTAssertEqual(f.collection.numberOfItems(inSection: 0), 6)
        f.adapter.layoutDirection = .leftToRight
        f.render()
        XCTAssertEqual(try frames(), ltr)
    }

    func testLayoutProviderReceivesExplicitDirectionEvenWithLegacyEnvironment() {
        let f = LayoutFixture(width: 400, count: 1)
        defer { f.close() }
        var observed: UITraitEnvironmentLayoutDirection?
        f.adapter.apply(transaction: .disabled) {
            ListSection(0) {
                Row(0, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
            } layout: {
                EnvironmentLayout(layoutKey: 0) { environment in
                    let _ = observed = environment.traitCollection.layoutDirection
                    GridLayout(tracks: 1).itemMainAxisSize(.fixed(44))
                }
            }
        }
        let environment = TestLayoutEnvironment()
        environment.traitCollection = UITraitCollection(layoutDirection: .leftToRight)
        f.adapter.layoutDirection = .rightToLeft
        XCTAssertNotNil(f.adapter.makeCompositionalSection(for: 0, environment: environment))
        XCTAssertEqual(observed, .rightToLeft)
        f.adapter.layoutDirection = .unspecified
        XCTAssertNotNil(f.adapter.makeCompositionalSection(for: 0, environment: environment))
        XCTAssertEqual(observed, .leftToRight)
    }

    func testHorizontalAndOrthogonalListsCanScrollAfterRoundTrip() throws {
        for orthogonal in [false, true] {
            let f = LayoutFixture(width: 400, count: 40, horizontal: !orthogonal)
            defer { f.close() }
            f.collection.frame = CGRect(x: 0, y: 0, width: 400, height: 160)
            var grid = GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).lineSpacing(10)
            if orthogonal { grid = grid.crossAxisSize(.fixed(120)).orthogonalScrolling(.continuous) }
            f.apply(grid)
            f.render()
            let path = IndexPath(item: 20, section: 0)
            f.collection.scrollToItem(at: path, at: .centeredHorizontally, animated: false)
            f.render()
            for direction in [UITraitEnvironmentLayoutDirection.rightToLeft, .leftToRight, .unspecified] {
                f.adapter.layoutDirection = direction
                f.render()
                XCTAssertTrue(f.collection.indexPathsForVisibleItems.contains(path),
                    "Direction changes must retain the visible item: \(orthogonal), \(direction)")
                f.collection.scrollToItem(at: path, at: .centeredHorizontally, animated: false)
                f.render()
                let cell = try XCTUnwrap(f.collection.cellForItem(at: path))
                let frame = cell.convert(cell.bounds, to: f.window)
                let viewport = f.collection.convert(f.collection.bounds, to: f.window)
                XCTAssertTrue(frame.intersects(viewport), "\(orthogonal), \(direction)")
                XCTAssertEqual(frame.midX, viewport.midX, accuracy: 1)
                let next = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: 21, section: 0)))
                let nextFrame = next.convert(next.bounds, to: f.window)
                if direction == .rightToLeft {
                    XCTAssertLessThan(nextFrame.minX, frame.minX)
                } else {
                    XCTAssertGreaterThan(nextFrame.minX, frame.minX)
                }
            }
        }
    }

    func testMixedVerticalAndOrthogonalSectionsKeepBothScrollPositions() throws {
        let f = LayoutFixture(width: 400, count: 0)
        defer { f.close() }
        f.collection.frame.size.height = 320
        f.adapter.apply(transaction: .disabled) {
            ListSection(0) {
                for index in 0..<3 {
                    Row(index, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
                }
            } layout: {
                GridLayout(tracks: 3).itemMainAxisSize(.fixed(64))
            }
            ListSection(1) {
                for index in 0..<40 {
                    Row(index, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(100)).crossAxisSize(.fixed(100))
                    .lineSpacing(10).orthogonalScrolling(.continuous)
            }
            ListSection(2) {
                for index in 0..<60 {
                    Row(index, model: (), cell: UICollectionViewCell.self) { _, _, _ in }
                }
            } layout: {
                GridLayout(tracks: 3).itemMainAxisSize(.fixed(80))
            }
        }
        f.render()
        let path = IndexPath(item: 20, section: 1)
        f.collection.scrollToItem(at: path, at: .centeredHorizontally, animated: false)
        f.collection.contentOffset.y = 24
        f.render()
        func orthogonalScrollView() throws -> UIScrollView {
            let cell = try XCTUnwrap(f.collection.cellForItem(at: path))
            var ancestor = cell.superview
            while let current = ancestor, current !== f.collection {
                if let scroll = current as? UIScrollView { return scroll }
                ancestor = current.superview
            }
            throw NSError(domain: "Missing orthogonal scroll view", code: 1)
        }
        let verticalOffset = f.collection.contentOffset
        let horizontal = try orthogonalScrollView()
        let horizontalOffset = horizontal.contentOffset
        let showsHorizontalIndicator = horizontal.showsHorizontalScrollIndicator
        let showsVerticalIndicator = horizontal.showsVerticalScrollIndicator
        for direction in [UITraitEnvironmentLayoutDirection.rightToLeft, .leftToRight, .unspecified] {
            f.adapter.layoutDirection = direction
            f.render()
            XCTAssertEqual(f.collection.contentOffset, verticalOffset)
            let scroll = try orthogonalScrollView()
            XCTAssertEqual(scroll.contentOffset.x, horizontalOffset.x, accuracy: 1)
            XCTAssertEqual(scroll.showsHorizontalScrollIndicator, showsHorizontalIndicator)
            XCTAssertEqual(scroll.showsVerticalScrollIndicator, showsVerticalIndicator)
            let cell = try XCTUnwrap(f.collection.cellForItem(at: path))
            let next = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: 21, section: 1)))
            let frame = cell.convert(cell.bounds, to: f.window)
            let nextFrame = next.convert(next.bounds, to: f.window)
            XCTAssertEqual(frame.midX, 200, accuracy: 1)
            if direction == .rightToLeft { XCTAssertLessThan(nextFrame.minX, frame.minX) }
            else { XCTAssertGreaterThan(nextFrame.minX, frame.minX) }
            // 纵向滑出横向区，再返回；横向位置也应保留。
            f.collection.contentOffset.y = 900
            f.render()
            f.collection.contentOffset = verticalOffset
            f.render()
            XCTAssertEqual(try orthogonalScrollView().contentOffset.x, horizontalOffset.x, accuracy: 1)
        }
    }

    func testTableSwitchUpdatesVisibleLeadingConstraintAndKeepsScrollPosition() throws {
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        table.contentInsetAdjustmentBehavior = .never
        let window = UIWindow(frame: table.frame)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(table)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let adapter = TableListAdapter<Int>(tableView: table)
        adapter.layoutDirection = .leftToRight
        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                for index in 0..<40 {
                    TableRow(index, model: (), cell: DirectionTableCell.self) { _, _, _ in }
                }
            }.layout { TableLayout().rowHeight(.fixed(60)) }
        }
        func render() {
            for _ in 0..<3 {
                window.layoutIfNeeded()
                table.layoutIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        }
        render()
        table.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
        render()
        let path = try XCTUnwrap(table.indexPathsForVisibleRows?.first)
        let cell = try XCTUnwrap(table.cellForRow(at: path) as? DirectionTableCell)
        let offset = table.contentOffset
        XCTAssertEqual(cell.marker.frame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(cell.contentView.frame.minX, 0, accuracy: 0.5)
        adapter.layoutDirection = .rightToLeft
        render()
        XCTAssertEqual(cell.marker.frame.maxX, cell.contentView.bounds.width - 20, accuracy: 0.5)
        XCTAssertEqual(table.contentOffset, offset)
        XCTAssertTrue(table.cellForRow(at: path) === cell)
        XCTAssertGreaterThan(cell.contentView.frame.minX, 0)
        adapter.layoutDirection = .leftToRight
        render()
        XCTAssertEqual(cell.marker.frame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(cell.contentView.frame.minX, 0, accuracy: 0.5)
        adapter.layoutDirection = .rightToLeft
        table.setContentOffset(CGPoint(x: 0, y: 900), animated: false)
        render()
        for visibleCell in table.visibleCells {
            XCTAssertGreaterThan(visibleCell.contentView.frame.minX, 0)
        }
        adapter.layoutDirection = .unspecified
        table.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
        render()
        for visibleCell in table.visibleCells {
            XCTAssertEqual(visibleCell.contentView.frame.minX, 0, accuracy: 0.5)
        }
    }

    func testDirectionOverrideDoesNotRetainList() {
        var table: UITableView? = UITableView()
        weak let weakTable = table
        let adapter = TableListAdapter<Int>(tableView: table!)
        adapter.layoutDirection = .rightToLeft
        table = nil
        XCTAssertNil(weakTable)
        adapter.layoutDirection = .leftToRight
    }
}

private final class DirectionTableCell: UITableViewCell {
    let marker = UIView()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        marker.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(marker)
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            marker.topAnchor.constraint(equalTo: contentView.topAnchor),
            marker.widthAnchor.constraint(equalToConstant: 60),
            marker.heightAnchor.constraint(equalToConstant: 30),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
