import UIKit
import XCTest

@testable import ListKit

@MainActor
final class MeasuredBadgeLayoutTests: XCTestCase {
    func testMeasuredBadgesKeepGeometryAndBusinessIndexPaths() throws {
        for horizontal in [false, true] {
            for orthogonal in [false, true] {
                for uniform in [false, true] {
                    if uniform { guard #available(iOS 17.0, *) else { continue } }
                    let f = LayoutFixture(width: 360, count: 8, horizontal: horizontal)
                    defer { f.close() }
                    let vertical = horizontal == orthogonal
                    let extents: [CGFloat] = [40, 100, 60, 70, 110, 90, 50, 80]
                    var size = ListGridItemMainAxisSize.estimated(44)
                    if #available(iOS 17.0, *), uniform { size = .uniform(estimated: 44) }
                    var grid = GridLayout(tracks: 2).itemMainAxisSize(size)
                        .gridCrossAxisSize(.fixed(210)).lineGrouping(.count(lines: 3))
                        .trackSpacing(10).lineSpacing(10).groupSpacing(20)
                        .itemSupplementaries {
                            ItemSupplementaryLayout(
                                kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)),
                                itemAnchor: .topTrailing)
                        }
                    if orthogonal { grid = grid.orthogonalScrolling(.groupPaging) }
                    f.adapter.apply(transaction: .disabled) {
                        ListSection(0) {
                            for i in extents.indices {
                                Row(i, model: extents[i], cell: MeasuredBadgeCell.self) { cell, extent, _ in
                                    cell.vertical = vertical
                                    cell.extent = extent
                                }
                            }
                        } layout: {
                            grid
                        } supplementaries: {
                            SectionSupplementary(MeasuredBadgeView.self, kind: "badge", id: 0) {
                                view, context in
                                view.item = context.indexPath.item
                            }
                        }
                    }
                    f.render()
                    XCTAssertTrue(f.adapter.lastLayoutDiagnostics.isEmpty)
                    let expected: [CGFloat] = uniform ? [100, 100, 70, 70, 110, 110, 80, 80] : extents
                    var actualKinds = Set<String>()
                    var visibleCount = 0
                    for i in extents.indices {
                        let path = IndexPath(item: i, section: 0)
                        let cell = try f.frame(i)
                        XCTAssertEqual(vertical ? cell.height : cell.width, expected[i], accuracy: 1)
                        let address = try XCTUnwrap(f.adapter.supplementaryElement(ofKind: "badge", at: path))
                        actualKinds.insert(address.elementKind)
                        let badge = try XCTUnwrap(
                            f.collection.layoutAttributesForSupplementaryElement(
                                ofKind: address.elementKind, at: address.indexPath))
                        XCTAssertEqual(badge.frame.maxX, cell.maxX, accuracy: 1)
                        XCTAssertEqual(badge.frame.minY, cell.minY, accuracy: 1)
                        if let view = f.collection.supplementaryView(
                            forElementKind: address.elementKind, at: address.indexPath) as? MeasuredBadgeView
                        {
                            visibleCount += 1
                            XCTAssertEqual(view.item, i)
                        }
                    }
                    XCTAssertGreaterThan(visibleCount, 0)
                    XCTAssertEqual(f.adapter.reconfigureVisibleSupplementaries(ofKind: "badge"), visibleCount)
                    XCTAssertEqual(actualKinds.count, 3)
                    for (item, start) in [(2, CGFloat(110)), (4, 190), (6, 320)] {
                        let frame = try f.frame(item)
                        XCTAssertEqual(vertical ? frame.minY : frame.minX, start, accuracy: 1)
                    }
                }
            }
        }
    }
    func testRefreshReorderMeasurementAndIdentityReplacement() async throws {
        let f = LayoutFixture(width: 360, count: 8)
        defer { f.close() }
        var configurations: [Int: Int] = [:]
        var displayed: [Int] = []
        var ended: [Int] = []
        func section(_ version: Int, order: [Int], lines: Int = 3, replacement: Bool = false) -> ListSection<
            Int
        > {
            ListSection(0) {
                for id in order {
                    Row(id, model: CGFloat(version == 0 ? 40 : 80), cell: MeasuredBadgeCell.self) {
                        cell, extent, _ in
                        cell.vertical = true
                        cell.extent = extent
                    }.refreshID(version).refresh(
                        when: .refreshIDChanges, action: .reconfigure(layout: .invalidate))
                }
            } layout: {
                GridLayout(tracks: 2).itemMainAxisSize(.estimated(44))
                    .lineGrouping(.count(lines: lines)).trackSpacing(10).lineSpacing(12).groupSpacing(20)
                    .itemSupplementaries {
                        ItemSupplementaryLayout(
                            kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)),
                            itemAnchor: .topTrailing)
                    }
            } supplementaries: {
                if replacement {
                    SectionSupplementary(OtherMeasuredBadgeView.self, kind: "badge", id: 1) { view, context in
                        view.item = context.indexPath.item
                        view.version = version
                    }
                } else {
                    SectionSupplementary(MeasuredBadgeView.self, kind: "badge", id: 0) { view, context in
                        view.item = context.indexPath.item
                        view.version = version
                        configurations[context.indexPath.item, default: 0] += 1
                    }.refreshID(version)
                        .onDisplay { _, context in displayed.append(context.indexPath.item) }
                        .onEndDisplay { _, context in ended.append(context.indexPath.item) }
                }
            }
        }
        func view(_ item: Int) throws -> MeasuredBadgeView {
            let address = try XCTUnwrap(
                f.adapter.supplementaryElement(ofKind: "badge", at: IndexPath(item: item, section: 0)))
            return try XCTUnwrap(
                f.collection.supplementaryView(forElementKind: address.elementKind, at: address.indexPath)
                    as? MeasuredBadgeView)
        }
        await f.adapter.apply(options: .init(transaction: .disabled)) { section(0, order: Array(0..<8)) }
        f.render()
        XCTAssertEqual(Set(displayed), Set(0..<8))
        let initial = try XCTUnwrap(
            f.adapter.supplementaryElement(ofKind: "badge", at: IndexPath(item: 6, section: 0)))
        configurations = [:]
        XCTAssertEqual(f.adapter.reconfigureVisibleSupplementaries(ofKind: "badge", forRowID: 6), 1)
        XCTAssertEqual(configurations, [6: 1])
        configurations = [:]
        XCTAssertEqual(f.adapter.reconfigureVisibleSupplementaries(ofKind: "badge"), 8)
        XCTAssertEqual(configurations, Dictionary(uniqueKeysWithValues: (0..<8).map { ($0, 1) }))
        await f.adapter.apply(options: .init(transaction: .disabled)) {
            section(1, order: Array((0..<8).reversed()))
        }
        f.render()
        for i in 0..<8 {
            XCTAssertEqual(try view(i).item, i)
            XCTAssertEqual(try view(i).version, 1)
        }
        XCTAssertEqual(try f.frame(2).minY, 92, accuracy: 1)
        XCTAssertEqual(
            f.adapter.supplementaryElement(ofKind: "badge", at: IndexPath(item: 6, section: 0)), initial)
        configurations = [:]
        XCTAssertEqual(f.adapter.reconfigureVisibleSupplementaries(ofKind: "badge", forRowID: 6), 1)
        XCTAssertEqual(configurations, [1: 1], "row identity follows its new item position")
        // 改变模板数量后 UIKit 的局部编号也改变；不得沿用旧模板的地址计算。
        await f.adapter.apply(options: .init(transaction: .disabled)) {
            section(1, order: Array(0..<7), lines: 2)
        }
        f.render()
        for i in 0..<7 { XCTAssertEqual(try view(i).item, i) }
        await f.adapter.apply(options: .init(transaction: .disabled)) {
            section(2, order: Array(0..<7), lines: 2, replacement: true)
        }
        f.render()
        for i in 0..<7 {
            XCTAssertTrue(try view(i) is OtherMeasuredBadgeView)
            XCTAssertEqual(try view(i).version, 2)
        }
        XCTAssertFalse(ended.isEmpty)
        XCTAssertTrue(ended.allSatisfy { (0..<8).contains($0) })
        await f.adapter.apply(options: .init(transaction: .disabled)) {}
        f.render()
        XCTAssertNil(f.adapter.supplementaryElement(ofKind: "badge", at: IndexPath(item: 0, section: 0)))
    }

    func testProviderReceivesPhysicalAddressAndLogicalContext() throws {
        let f = LayoutFixture(width: 360, count: 8)
        defer { f.close() }
        var requests: [(Int, Int)] = []
        let provider = ProviderSupplementary("badge", id: 0, view: MeasuredBadgeView.self) {
            collection, kind, path, context in
            requests.append((path.item, context.indexPath.item))
            let view = collection.lk.dequeue(MeasuredBadgeView.self, ofKind: kind, for: path)
            view.item = context.indexPath.item
            return view
        }
        f.adapter.apply(transaction: .disabled) {
            ListSection(0) {
                for i in 0..<8 {
                    Row(i, model: CGFloat(40), cell: MeasuredBadgeCell.self) { cell, extent, _ in
                        cell.extent = extent
                    }
                }
            } layout: {
                GridLayout(tracks: 2).lineGrouping(.count(lines: 3)).itemSupplementaries {
                    ItemSupplementaryLayout(
                        kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)),
                        itemAnchor: .topTrailing)
                }
            } supplementaries: {
                SectionSupplementary(provider)
            }
        }
        f.render()
        XCTAssertEqual(Set(requests.map { $0.1 }), Set(0..<8))
        for (physical, logical) in requests { XCTAssertEqual(physical, (logical / 6) * 2 + logical % 2) }
    }

    func testSectionIsolationRTLAndChangingTrackCount() async throws {
        let f = LayoutFixture(width: 360, count: 8, rtl: true)
        defer { f.close() }
        for tracks in [2, 3, 2] {
            await f.adapter.apply(options: .init(transaction: .disabled)) {
                for sectionID in 0..<2 {
                    ListSection(sectionID) {
                        for i in 0..<8 {
                            Row(i, model: CGFloat(40), cell: MeasuredBadgeCell.self) { cell, extent, _ in
                                cell.extent = extent
                            }
                        }
                    } layout: {
                        GridLayout(tracks: tracks).lineGrouping(.count(lines: 3)).lineSpacing(10)
                            .itemSupplementaries {
                                ItemSupplementaryLayout(
                                    kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)),
                                    itemAnchor: .topTrailing)
                            }
                    } supplementaries: {
                        SectionSupplementary(MeasuredBadgeView.self, kind: "badge", id: 0) { view, context in
                            view.item = context.indexPath.item
                            view.version = sectionID
                        }
                    }
                }
            }
            f.render()
            var sectionKinds: [Set<String>] = []
            for sectionID in 0..<2 {
                var kinds = Set<String>()
                for i in 0..<8 {
                    let path = IndexPath(item: i, section: sectionID)
                    let address = try XCTUnwrap(f.adapter.supplementaryElement(ofKind: "badge", at: path))
                    kinds.insert(address.elementKind)
                    let view = try XCTUnwrap(
                        f.collection.supplementaryView(
                            forElementKind: address.elementKind, at: address.indexPath) as? MeasuredBadgeView)
                    let cell = try XCTUnwrap(f.collection.cellForItem(at: path))
                    XCTAssertEqual(view.item, i)
                    XCTAssertEqual(view.version, sectionID)
                    let badgeRect = view.convert(view.bounds, to: f.window)
                    let cellRect = cell.convert(cell.bounds, to: f.window)
                    XCTAssertEqual(badgeRect.minX, cellRect.minX, accuracy: 1)
                    XCTAssertEqual(badgeRect.minY, cellRect.minY, accuracy: 1)
                }
                sectionKinds.append(kinds)
            }
            XCTAssertTrue(sectionKinds[0].isDisjoint(with: sectionKinds[1]))
        }
        // 切换为无 badge 布局时，查询不得返回保留给旧视图结束展示用的地址。
        await f.adapter.apply(options: .init(transaction: .disabled)) {
            ListSection(0) {
                Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(44))
            } supplementaries: {
                SectionSupplementary(MeasuredBadgeView.self, kind: "badge", id: 0) { _, _ in }
            }
        }
        f.render()
        XCTAssertNil(f.adapter.supplementaryElement(ofKind: "badge", at: IndexPath(item: 0, section: 0)))
    }

    func testAdaptiveTrackResizeRemapsBadgeAddresses() throws {
        let f = LayoutFixture(width: 340, count: 8)
        defer { f.close() }
        f.adapter.apply(transaction: .disabled) {
            ListSection(0) {
                for i in 0..<8 {
                    Row(i, model: CGFloat(40), cell: MeasuredBadgeCell.self) { cell, extent, _ in
                        cell.extent = extent
                    }
                }
            } layout: {
                GridLayout(tracks: [.init(.adaptive(minimumForCount: 100))])
                    .trackSpacing(10).lineSpacing(10).lineGrouping(.count(lines: 3))
                    .itemSupplementaries {
                        ItemSupplementaryLayout(
                            kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)),
                            itemAnchor: .topTrailing)
                    }
            } supplementaries: {
                SectionSupplementary(MeasuredBadgeView.self, kind: "badge", id: 0) { view, context in
                    view.item = context.indexPath.item
                }
            }
        }
        for (width, tracks) in [(CGFloat(340), 3), (220, 2), (340, 3)] {
            f.collection.frame.size.width = width
            f.render()
            XCTAssertEqual(try f.frame(tracks).minY, 50, accuracy: 1)
            for i in 0..<8 {
                let address = try XCTUnwrap(
                    f.adapter.supplementaryElement(ofKind: "badge", at: IndexPath(item: i, section: 0)))
                let view = try XCTUnwrap(
                    f.collection.supplementaryView(forElementKind: address.elementKind, at: address.indexPath)
                        as? MeasuredBadgeView)
                XCTAssertEqual(view.item, i)
                let badge = try XCTUnwrap(
                    f.collection.layoutAttributesForSupplementaryElement(
                        ofKind: address.elementKind, at: address.indexPath))
                XCTAssertEqual(badge.frame.maxX, try f.frame(i).maxX, accuracy: 1)
                XCTAssertEqual(badge.frame.minY, try f.frame(i).minY, accuracy: 1)
            }
        }
    }

    func testLegacyProviderIsDiagnosedOnlyWhenMappingIsRequired() {
        for lines in [1, 3] {
            let f = LayoutFixture(width: 360, count: 8)
            defer { f.close() }
            f.adapter.apply(transaction: .disabled) {
                ListSection(0) {
                    Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
                } layout: {
                    GridLayout(tracks: 2).lineGrouping(.count(lines: lines)).itemSupplementaries {
                        ItemSupplementaryLayout(
                            kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)),
                            itemAnchor: .topTrailing)
                    }
                } supplementaries: {
                    SectionSupplementary(
                        ProviderSupplementary("badge", id: 0, view: MeasuredBadgeView.self) {
                            collection, path, _ in
                            collection.lk.dequeue(MeasuredBadgeView.self, ofKind: "badge", for: path)
                        })
                }
            }
            let section = f.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment())
            if lines == 1 {
                XCTAssertNotNil(section)
            } else {
                XCTAssertNil(section)
                XCTAssertTrue(
                    f.adapter.lastLayoutDiagnostics.contains {
                        $0.message.contains("must accept elementKind")
                    })
            }
        }
    }

}

@MainActor
class MeasuredBadgeView: UICollectionReusableView {
    var item: Int = -1
    var version: Int = -1
}

@MainActor
final class OtherMeasuredBadgeView: MeasuredBadgeView {}
