import UIKit
import XCTest
@testable import ListKit

@MainActor
final class WaterfallLayoutTests: XCTestCase {
    private let lengths: [CGFloat] = [90, 40, 30, 70, 50]

    func testDirectionMatrixUsesShortestTrackAndNoTrailingSpacing() throws {
        for horizontal in [false, true] {
            for orthogonal in [false, true] {
                let f = LayoutFixture(width: 360, count: lengths.count, horizontal: horizontal)
                defer { f.close() }
                var layout = WaterfallLayout(tracks: 2).crossAxisSize(210).trackSpacing(10).lineSpacing(8)
                if orthogonal { layout = layout.orthogonalScrolling(.continuous) }
                let vertical = horizontal == orthogonal
                f.adapter.apply([section(lengths, layout: layout)], transaction: .disabled)
                f.render()
                XCTAssertTrue(f.adapter.lastLayoutDiagnostics.isEmpty)
                let a = try f.frame(0), b = try f.frame(1), c = try f.frame(2)
                XCTAssertEqual(vertical ? a.width : a.height, 100, accuracy: 0.5)
                XCTAssertEqual(vertical ? a.height : a.width, 90, accuracy: 0.5)
                XCTAssertEqual(vertical ? b.minX - a.minX : b.minY - a.minY, 110, accuracy: 0.5)
                XCTAssertEqual(vertical ? c.minX : c.minY, vertical ? b.minX : b.minY, accuracy: 0.5)
                XCTAssertEqual(vertical ? c.minY - b.minY : c.minX - b.minX, 48, accuracy: 0.5)
                if !orthogonal {
                    let maxEnd = try (0..<lengths.count).map { try f.frame($0) }
                        .map { vertical ? $0.maxY : $0.maxX }.max()!
                    let size = f.collection.collectionViewLayout.collectionViewContentSize
                    XCTAssertEqual(vertical ? size.height : size.width, maxEnd, accuracy: 0.5)
                }
            }
        }
    }

    func testAutoLayoutCellNeedsNoMeasurementClosureAndRespondsToWidthAndTraits() throws {
        let f = LayoutFixture(width: 360, count: 2)
        defer { f.close() }
        let text = String(repeating: "Automatic measurement wraps this text. ", count: 6)
        f.adapter.apply([ListSection(0) {
            Row(0, model: text, cell: WaterfallLabelCell.self) { cell, text, _ in
                cell.label.text = text
                cell.label.font = .preferredFont(forTextStyle: .body, compatibleWith: cell.traitCollection)
            }.refreshID(text)
        } layout: { WaterfallLayout(tracks: 2).trackSpacing(10) }], transaction: .disabled)
        f.render()
        let initial = try f.frame(0)
        XCTAssertGreaterThan(initial.height, 40)
        XCTAssertEqual(initial.width, 175, accuracy: 0.5)
        f.collection.frame.size.width = 260
        f.render()
        let narrower = try f.frame(0)
        XCTAssertGreaterThan(narrower.height, initial.height)
        if #available(iOS 17.0, *) {
            f.collection.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            f.render()
            XCTAssertGreaterThan(try f.frame(0).height, narrower.height)
        }
    }

    func testHorizontalAutoLayoutMeasuresWidthAtFixedHeight() throws {
        let f = LayoutFixture(width: 240, count: 2, horizontal: true)
        defer { f.close() }
        f.adapter.apply([ListSection(0) {
            Row(0, model: "A long horizontal label", cell: WaterfallLabelCell.self) { cell, text, _ in
                cell.label.numberOfLines = 1
                cell.label.text = text
            }
            Row(1, model: "Short", cell: WaterfallLabelCell.self) { cell, text, _ in
                cell.label.numberOfLines = 1
                cell.label.text = text
            }
        } layout: { WaterfallLayout(tracks: 2).trackSpacing(10) }], transaction: .disabled)
        f.render()
        XCTAssertEqual(try f.frame(0).height, 115, accuracy: 0.5)
        XCTAssertGreaterThan(try f.frame(0).width, try f.frame(1).width)
    }

    func testCachingAppendContentChangeAndOffscreenInvalidation() throws {
        let f = LayoutFixture(width: 360, count: 0)
        defer { f.close() }
        var measurements: [Int: Int] = [:]
        func apply(_ values: [CGFloat]) {
            f.adapter.apply([ListSection(0) {
                for (id, length) in values.enumerated() {
                    Row(id, model: length, cell: WaterfallLengthCell.self) { cell, length, context in
                        cell.length = length
                        if context.isMeasuring { measurements[id, default: 0] += 1 }
                    }.refreshID(length).refresh(when: .refreshIDChanges)
                }
            } layout: { WaterfallLayout(tracks: 1).lineSpacing(8) }], transaction: .disabled)
            f.render()
        }
        apply([800, 800, 100, 100])
        let before = measurements
        apply([800, 800, 100, 100, 90])
        for i in 0..<4 { XCTAssertEqual(measurements[i], before[i]) }
        XCTAssertEqual(measurements[4], 1)
        let oldFourth = try f.frame(3)
        XCTAssertNil(f.collection.cellForItem(at: IndexPath(item: 2, section: 0)))
        apply([800, 800, 200, 100, 90])
        XCTAssertEqual(measurements[2], (before[2] ?? 0) + 1)
        XCTAssertEqual(try f.frame(3).minY - oldFourth.minY, 100, accuracy: 0.5)
        let count = measurements[0]!
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        f.collection.collectionViewLayout.invalidateLayout()
        f.render()
        XCTAssertEqual(measurements[0], count + 1)
    }

    func testUnversionedRowsRemeasureOnApplyAndMeasurementsNeverDispatchEvents() throws {
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        var measurements = 0, events = 0, displays = 0
        adapter.onEvent(MeasurementEvent.self) { _, _ in events += 1 }
        func apply(_ value: CGFloat) throws {
            adapter.apply([ListSection(0) {
                Row(0, model: value, cell: WaterfallLengthCell.self) { cell, value, context in
                    cell.length = value
                    if context.isMeasuring { measurements += 1 }
                    context.send(MeasurementEvent.ping)
                }.onAppear { _, _ in displays += 1 }
            } layout: { WaterfallLayout(tracks: 1) }], transaction: .disabled)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            _ = try XCTUnwrap(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        }
        try apply(40)
        try apply(80)
        XCTAssertEqual(measurements, 2)
        XCTAssertEqual(events, 0)
        XCTAssertEqual(displays, 0)
    }

    func testNativeDirectionChangeAndSwitchToGrid() throws {
        let f = LayoutFixture(width: 360, count: lengths.count)
        defer { f.close() }
        f.adapter.apply([section(lengths, layout: WaterfallLayout(tracks: 2).trackSpacing(10))], transaction: .disabled)
        f.render()
        XCTAssertEqual(try f.frame(0).width, 175, accuracy: 0.5)
        let layout = try XCTUnwrap(f.collection.collectionViewLayout as? UICollectionViewCompositionalLayout)
        let config = layout.configuration
        config.scrollDirection = .horizontal
        layout.configuration = config
        f.render()
        XCTAssertEqual(try f.frame(0).height, 695, accuracy: 0.5)
        XCTAssertEqual(try f.frame(0).width, 90, accuracy: 0.5)
        f.apply(GridLayout(tracks: 1).itemMainAxisSize(.fixed(50)))
        f.render()
        XCTAssertEqual(try f.frame(0).width, 50, accuracy: 0.5)
    }

    func testAdaptiveTracksInsetsAndRTL() throws {
        for rtl in [false, true] {
            let f = LayoutFixture(width: 360, count: lengths.count, rtl: rtl)
            defer { f.close() }
            f.adapter.apply([section(lengths, layout: WaterfallLayout(tracks: [.init(.adaptive(minimum: 100))])
                .trackSpacing(10).lineSpacing(8).sectionInsets(.init(leading: 10, trailing: 10)))], transaction: .disabled)
            f.render()
            XCTAssertEqual(try f.frame(0).width, 320.0 / 3, accuracy: 0.5)
            let first = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: 0, section: 0)))
            let second = try XCTUnwrap(f.collection.cellForItem(at: IndexPath(item: 1, section: 0)))
            let a = first.convert(first.bounds, to: f.window), b = second.convert(second.bounds, to: f.window)
            XCTAssertEqual(a.minX < b.minX, !rtl)
        }
    }

    func testAdaptiveTrackCountChangesWithContainerOnBothAxes() throws {
        for horizontal in [false, true] {
            let f = LayoutFixture(width: 360, count: 6, horizontal: horizontal)
            defer { f.close() }
            f.adapter.apply([section(Array(repeating: 40, count: 6), layout:
                WaterfallLayout(tracks: [ListGridTrack(.adaptive(minimum: 100))])
                    .trackSpacing(10).lineSpacing(8))], transaction: .disabled)
            f.render()
            let first = try f.frame(0), third = try f.frame(2)
            // 360 点容器生成三条轨道，前三项沿主轴并排。
            XCTAssertEqual(horizontal ? third.minX : third.minY, horizontal ? first.minX : first.minY, accuracy: 0.5)
            if horizontal { f.collection.frame.size.height = 230 }
            else { f.collection.frame.size.width = 230 }
            f.render()
            // 容器缩小后无需 apply，自动改成两条轨道，第三项进入第二行/列。
            let resized = try f.frame(0), next = try f.frame(2)
            XCTAssertEqual(horizontal ? resized.height : resized.width, 110, accuracy: 0.5)
            XCTAssertEqual(horizontal ? next.minX - resized.minX : next.minY - resized.minY, 48, accuracy: 0.5)
        }
    }

    func testEmptySectionBoundariesAndDecorations() throws {
        let f = LayoutFixture(width: 360, count: 0)
        defer { f.close() }
        let header = UICollectionView.elementKindSectionHeader
        f.adapter.apply([ListSection(0) {} layout: {
            WaterfallLayout(tracks: 2).boundarySupplementaries {
                BoundarySupplementaryLayout(kind: header,
                    size: .init(width: .fractionalWidth(1), height: .absolute(52)), alignment: .top)
            }
        } supplementaries: {
            SectionSupplementary(UICollectionReusableView.self, kind: header) { _, _ in }
        } decorations: {
            SectionDecoration(UICollectionReusableView.self, kind: "background")
        }], transaction: .disabled)
        f.render()
        let resolved = try XCTUnwrap(f.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertEqual(resolved.boundarySupplementaryItems.count, 1)
        XCTAssertEqual(resolved.decorationItems.count, 1)
        XCTAssertNotNil(f.collection.layoutAttributesForSupplementaryElement(ofKind: header, at: IndexPath(item: 0, section: 0)))
    }

    func testInvalidConfigurationAndProviderRowsDiagnose() {
        XCTAssertFalse(ListDiagnostics.validate([section([], layout: WaterfallLayout(tracks: 0))]).isEmpty)
        XCTAssertFalse(ListDiagnostics.validate([section([], layout: WaterfallLayout(tracks: 2).lineSpacing(-1))]).isEmpty)
        let provider = ListSection(0) {
            ProviderRow(0, cell: UICollectionViewCell.self, cellProvider: { _, _, _ in UICollectionViewCell() })
        } layout: { WaterfallLayout(tracks: 2) }
        XCTAssertTrue(ListDiagnostics.validate([provider]).contains { $0.message.contains("ProviderRow") })
    }

    private func section(_ values: [CGFloat], layout: ListSectionWaterfallLayout) -> ListSection<Int> {
        ListSection(0) {
            for (id, value) in values.enumerated() {
                Row(id, model: value, cell: WaterfallLengthCell.self) { cell, value, _ in cell.length = value }
                    .refreshID(value)
            }
        } layout: { layout }
    }
}

private enum MeasurementEvent: ListEvent { case ping }

@MainActor private final class WaterfallLengthCell: UICollectionViewCell {
    var length: CGFloat = 1
    override func systemLayoutSizeFitting(_ targetSize: CGSize,
        withHorizontalFittingPriority horizontal: UILayoutPriority,
        verticalFittingPriority vertical: UILayoutPriority) -> CGSize {
        horizontal == .required ? CGSize(width: targetSize.width, height: length)
            : CGSize(width: length, height: targetSize.height)
    }
}

@MainActor private final class WaterfallLabelCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
