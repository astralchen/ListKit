import UIKit
import XCTest

@testable import ListKit

@MainActor final class LayoutBoundaryTests: XCTestCase {
    func testOptionalLayoutsRestoreDefaultAndKeepPresentValues() {
        let grid: ListSectionGridLayout? = GridLayout(tracks: 3)
        let empty: ListSectionGridLayout? = nil
        let original = ListSection(0) {
        } layout: {
            grid
        }
        XCTAssertEqual(original.layoutSource, .builtIn(.gridConfiguration(grid!)))
        XCTAssertEqual(original.layout { empty }.layoutSource, .builtIn(.defaultLayout))
    }

    func testCustomKindsKeepRolesAfterModifiersAndTapBinding() throws {
        let section = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                .boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: "title", mainAxisSize: .fixed(30), sizingAxis: .vertical,
                        alignment: .top
                    ).pinToVisibleBounds(true).whenContentExists()
                    BoundarySupplementaryLayout(
                        kind: "summary", mainAxisSize: .fixed(20), sizingAxis: .vertical,
                        alignment: .bottom
                    ).whenContentExists()
                }

        } supplementaries: {
            SectionSupplementary(
                UICollectionReusableView.self, kind: "title", id: 1
            ) { _, _ in }.onTap { _ in }
                .refreshID(1)

            SectionSupplementary(
                UICollectionReusableView.self, kind: "summary", id: 2
            ) { _, _ in }.onTap { _ in }
                .onDisplay { _, _ in }
        }
        XCTAssertEqual(
            section.supplementaries.map(\.kind),
            ["title", "summary"])
        XCTAssertTrue(section.supplementaries.allSatisfy { $0.tapHandler != nil })
        for horizontal in [false, true] {
            let f = BoundaryFixture(horizontal: horizontal)
            defer { f.close() }
            f.apply(section)
            let resolved = try XCTUnwrap(
                f.adapter.makeCompositionalSection(
                    for: 0,
                    environment: TestLayoutEnvironment(),
                    scrollDirection: horizontal ? .horizontal : .vertical))
            XCTAssertEqual(resolved.boundarySupplementaryItems.map(\.elementKind), ["title", "summary"])
            XCTAssertEqual(
                resolved.boundarySupplementaryItems.map(\.alignment),
                [.top, .bottom])
            XCTAssertEqual(resolved.boundarySupplementaryItems.map(\.pinToVisibleBounds), [true, false])
        }
        // Even a standard kind with the opposite role must not override the declaration's role.
        let opposite = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                .boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: UICollectionView.elementKindSectionFooter,
                        size: .init(width: .fractionalWidth(1), height: .estimated(44)), alignment: .top
                    ).whenContentExists()
                }

        } supplementaries: {
            SectionSupplementary(
                UICollectionReusableView.self,
                kind: UICollectionView.elementKindSectionFooter, id: 0
            ) { _, _ in }
        }
        XCTAssertEqual(opposite.resolvedForTesting().boundarySupplementaryItems.first?.alignment, .top)
    }

    func testCustomKindsReachViewsAndSelfSizeInBothAxes() throws {
        for horizontal in [false, true] {
            let f = BoundaryFixture(horizontal: horizontal)
            defer { f.close() }
            var received = Set<String>()
            f.apply(
                ListSection(0) {
                    for i in 0..<3 { Row(i, model: i, cell: UICollectionViewCell.self) { _, _, _ in } }
                } layout: {
                    GridLayout(tracks: 2)
                        .itemMainAxisSize(.fixed(48)).sectionInsets(.init(20))
                        .boundarySupplementaries {
                            BoundarySupplementaryLayout(
                                kind: "custom.title", mainAxisSize: .estimated(20),
                                sizingAxis: horizontal ? .horizontal : .vertical, alignment: horizontal ? .leading : .top
                            ).whenContentExists()
                            BoundarySupplementaryLayout(
                                kind: "custom.summary", mainAxisSize: .estimated(20),
                                sizingAxis: horizontal ? .horizontal : .vertical,
                                alignment: horizontal ? .trailing : .bottom
                            ).whenContentExists()
                        }

                } supplementaries: {
                    SectionSupplementary(
                        ReviewSizingBoundary.self,
                        kind: "custom.title", id: 0
                    ) { view, _ in
                        received.insert("custom.title")
                        view.horizontal = horizontal
                        view.extent = 75
                    }

                    SectionSupplementary(
                        ReviewSizingBoundary.self,
                        kind: "custom.summary", id: 1
                    ) { view, _ in
                        received.insert("custom.summary")
                        view.horizontal = horizontal
                        view.extent = 65
                    }
                })
            XCTAssertEqual(received, ["custom.title", "custom.summary"])
            let header = try f.boundary("custom.title")
            let footer = try f.boundary("custom.summary")
            XCTAssertEqual(horizontal ? header.width : header.height, 75, accuracy: 1)
            XCTAssertEqual(horizontal ? footer.width : footer.height, 65, accuracy: 1)
            XCTAssertLessThanOrEqual(
                horizontal ? header.maxX : header.maxY, horizontal ? footer.minX : footer.minY)
        }
    }

    func testBoundaryRatioUsesEffectiveCrossAxisAndInsets() throws {
        for horizontal in [false, true] {
            let f = BoundaryFixture(horizontal: horizontal)
            defer { f.close() }
            f.apply(
                ListSection(0) {
                    Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
                } layout: {
                    GridLayout(tracks: 2).sectionInsets(.init(20))
                        .boundarySupplementaries {
                            BoundarySupplementaryLayout(
                                kind: "ratio", mainAxisSize: .aspectRatio(2),
                                sizingAxis: horizontal ? .horizontal : .vertical, alignment: horizontal ? .leading : .top
                            ).whenContentExists()
                        }

                } supplementaries: {
                    SectionSupplementary(
                        UICollectionReusableView.self, kind: "ratio", id: 0
                    ) { _, _ in }
                })
            let frame = try f.boundary("ratio")
            XCTAssertEqual(horizontal ? frame.height : frame.width, 320, accuracy: 1)
            XCTAssertEqual(horizontal ? frame.width : frame.height, horizontal ? 640 : 160, accuracy: 1)
        }
    }

    func testBoundaryEstimatedSizesMeasureIndependently() throws {
        let f = BoundaryFixture(horizontal: false)
        defer { f.close() }
        f.apply(
            ListSection(0) {
                Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(48))
                    .boundarySupplementaries {
                        BoundarySupplementaryLayout(
                            kind: "title", mainAxisSize: .estimated(20),
                            sizingAxis: .vertical, alignment: .top
                        ).whenContentExists()
                        BoundarySupplementaryLayout(
                            kind: "summary", mainAxisSize: .estimated(20),
                            sizingAxis: .vertical, alignment: .bottom
                        ).whenContentExists()
                    }

            } supplementaries: {
                SectionSupplementary(
                    ReviewSizingBoundary.self, kind: "title", id: 0
                ) { view, _ in view.extent = 75 }

                SectionSupplementary(
                    ReviewSizingBoundary.self, kind: "summary", id: 1
                ) { view, _ in view.extent = 65 }
            })
        XCTAssertEqual(try f.boundary("title").height, 75, accuracy: 1)
        XCTAssertEqual(try f.boundary("summary").height, 65, accuracy: 1)
    }

    func testInvalidBoundaryContractsDiagnoseWithoutDuplicateGeometry() {
        let invalid = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                .boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: "",
                        size: .init(width: .fractionalWidth(1), height: .estimated(44)), alignment: .top
                    ).whenContentExists()
                }

        } supplementaries: {
            SectionSupplementary(
                UICollectionReusableView.self, kind: "", id: 0
            ) { _, _ in }
        }
        XCTAssertTrue(ListDiagnostics.validate([invalid]).contains { $0.message.contains("kind") })
        let invalidSize = ListSection(0) {
        } layout: {
            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                .boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: UICollectionView.elementKindSectionHeader,
                        mainAxisSize: .aspectRatio(0), sizingAxis: .vertical, alignment: .top
                    ).whenContentExists()
                }

        } supplementaries: {
            SectionSupplementary(
                UICollectionReusableView.self,
                kind: UICollectionView.elementKindSectionHeader, id: 0
            ) { _, _ in }
        }
        XCTAssertTrue(ListDiagnostics.validate([invalidSize]).contains { $0.message.contains("size") })
        for isCustom in [false, true] {
            // The public builder rejects this ownership combination; retain defensive validation coverage.
            var invalid = GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
            invalid.options.boundaries = [.provided(CustomLayoutBoundary(kind: "missing").whenContentExists())]
            let f = BoundaryFixture(horizontal: false)
            defer { f.close() }
            let section = ListSection(0) {
            } layout: {
                if isCustom {
                    CustomLayout(layoutKey: 0) { context in
                        ListSectionLayout.gridConfiguration(
                            GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                        ).makeCompositionalSection(
                            environment: context.environment, itemSupplementaries: [])
                    }
                    .boundarySupplementaries {
                        CustomLayoutBoundary(kind: "missing")
                            .whenContentExists()
                    }

                } else {
                    EnvironmentLayout(layoutKey: 0) { _ in
                        invalid
                    }
                }
            } supplementaries: {
                SectionSupplementary(
                    UICollectionReusableView.self, kind: "missing", id: 0
                ) { _, _ in }
            }
            f.apply(section)
            XCTAssertNil(f.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
            XCTAssertFalse(f.adapter.lastLayoutDiagnostics.isEmpty)
        }
    }

    func testCustomBoundaryCanUseSectionViewProvider() throws {
        let f = BoundaryFixture(horizontal: false)
        defer { f.close() }
        var configured = false
        f.apply(
            ListSection(0) {
                Row(0, model: 0, cell: UICollectionViewCell.self) { _, _, _ in }
            } layout: {
                CustomLayout(layoutKey: 0) { context in
                    let section = ListSectionLayout.gridConfiguration(
                        GridLayout(tracks: 1).itemMainAxisSize(.fixed(48)).trackSpacing(0).lineSpacing(0)
                    ).makeCompositionalSection(
                        environment: context.environment, itemSupplementaries: [])
                    let header = NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: .init(
                            widthDimension: .fractionalWidth(1), heightDimension: .absolute(30)),
                        elementKind: "custom-header", alignment: .top)
                    header.contentInsets.leading = 12
                    section.boundarySupplementaryItems = [header]
                    return section
                }
                .boundarySupplementaries {
                    CustomLayoutBoundary(
                        kind: "custom-header").whenContentExists()
                }

            } supplementaries: {
                SectionSupplementary(
                    UICollectionReusableView.self,
                    kind: "custom-header", id: 0
                ) { _, _ in
                    configured = true
                }.refreshID(1)
            })
        let resolved = try XCTUnwrap(
            f.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(configured)
        XCTAssertEqual(resolved.boundarySupplementaryItems.count, 1)
        XCTAssertEqual(resolved.boundarySupplementaryItems[0].contentInsets.leading, 12)
        XCTAssertEqual(try f.boundary("custom-header").height, 30, accuracy: 1)
    }

    func testExplicitDuplicateBoundaryStillReportsConflict() {
        let f = BoundaryFixture(horizontal: false)
        defer { f.close() }
        f.apply(
            ListSection(0) {
            } layout: {
                CustomLayout(layoutKey: 0) { context in
                    let section = ListSectionLayout.gridConfiguration(
                        GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).trackSpacing(0).lineSpacing(0)
                    ).makeCompositionalSection(
                        environment: context.environment, itemSupplementaries: [])
                    section.boundarySupplementaryItems = [
                        NSCollectionLayoutBoundarySupplementaryItem(
                            layoutSize: .init(
                                widthDimension: .fractionalWidth(1), heightDimension: .absolute(30)),
                            elementKind: "title", alignment: .top)
                    ]
                    return section
                }
                .boundarySupplementaries {
                    BoundarySupplementaryLayout(
                        kind: "title", mainAxisSize: .fixed(40), sizingAxis: .vertical,
                        alignment: .top
                    ).whenContentExists()
                }

            } supplementaries: {
                SectionSupplementary(
                    UICollectionReusableView.self, kind: "title", id: 0
                ) { _, _ in }
            })
        XCTAssertNil(f.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertEqual(f.adapter.lastLayoutDiagnostics.map(\.kind), [.conflictingSupplementaryLayout])
        _ = f.adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment())
        XCTAssertEqual(f.adapter.lastLayoutDiagnostics.count, 1)
        _ = f.adapter.makeCompositionalSection(for: 100, environment: TestLayoutEnvironment())
        XCTAssertTrue(f.adapter.lastLayoutDiagnostics.isEmpty)
    }

    func testSuccessfulResolutionClearsPreviousDiagnostic() {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: cv)
        adapter.apply(
            [
                ListSection(0) {
                } layout: {
                    // Positive size passes static validation; tracks overflow during environment resolution.
                    GridLayout(tracks: 2).gridCrossAxisSize(.fixed(1))
                }
            ], transaction: .disabled)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertFalse(adapter.lastLayoutDiagnostics.isEmpty)
        adapter.apply(
            [
                ListSection(0) {
                } layout: {
                    GridLayout(tracks: 2)
                }
            ], transaction: .disabled)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNotNil(adapter.makeCompositionalSection(for: 0, environment: TestLayoutEnvironment()))
        XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
    }

    func testRepeatedGridWithSupplementaryKeepsTrackGeometry() throws {
        let cv = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 800),
            collectionViewLayout: UICollectionViewFlowLayout())
        cv.contentInsetAdjustmentBehavior = .never
        let adapter = CollectionListAdapter<Int>(collectionView: cv)
        cv.collectionViewLayout = adapter.makeCompositionalLayout(
            configuration: .init(contentInsetsReference: .none))
        let window = UIWindow(frame: cv.frame)
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.rootViewController!.view.addSubview(cv)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        adapter.apply(
            [
                ListSection(0) {
                    for i in 0..<7 { Row(i, model: i, cell: UICollectionViewCell.self) { _, _, _ in } }
                } layout: {
                    GridLayout(tracks: 3).itemMainAxisSize(.aspectRatio(1)).trackSpacing(10).lineSpacing(10).sectionInsets(
                        .init(top: 0, leading: 17, bottom: 0, trailing: 23)
                    )
                    .itemSupplementaries {
                        ItemSupplementaryLayout(
                            kind: "badge",
                            size: .init(width: .absolute(10), height: .absolute(10)), itemAnchor: .topTrailing
                        ).whenContentExists()
                    }

                } supplementaries: {
                    SectionSupplementary(
                        UICollectionReusableView.self, kind: "badge", id: 0
                    ) { _, _ in }
                }
            ], transaction: .disabled)
        for _ in 0..<3 {
            window.layoutIfNeeded()
            cv.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        for i in 0..<7 {
            let frame = try XCTUnwrap(cv.layoutAttributesForItem(at: IndexPath(item: i, section: 0)))
                .frame
            XCTAssertEqual(frame.width, 260.0 / 3, accuracy: 0.6)
            XCTAssertEqual(frame.height, frame.width, accuracy: 0.6)
            XCTAssertEqual(frame.minX, 17 + CGFloat(i % 3) * (260.0 / 3 + 10), accuracy: 0.6)
            XCTAssertNotNil(
                cv.layoutAttributesForSupplementaryElement(
                    ofKind: "badge", at: IndexPath(item: i, section: 0)))
        }
    }
}

@MainActor private final class BoundaryFixture {
    let collection: UICollectionView
    let adapter: CollectionListAdapter<Int>
    let window: UIWindow
    init(horizontal: Bool) {
        collection = UICollectionView(
            frame: CGRect(
                x: 0, y: 0, width: horizontal ? 1200 : 360,
                height: horizontal ? 360 : 1200), collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        adapter = CollectionListAdapter(collectionView: collection)
        collection.collectionViewLayout = adapter.makeCompositionalLayout(
            configuration: .init(
                scrollDirection: horizontal ? .horizontal : .vertical, contentInsetsReference: .none))
        window = UIWindow(frame: collection.frame)
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.rootViewController!.view.addSubview(collection)
    }
    func apply(_ section: ListSection<Int>) {
        adapter.apply([section], transaction: .disabled)
        for _ in 0..<8 {
            window.layoutIfNeeded()
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    func boundary(_ kind: String) throws -> CGRect {
        try XCTUnwrap(
            collection.layoutAttributesForSupplementaryElement(
                ofKind: kind, at: IndexPath(item: 0, section: 0))
        ).frame
    }
    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}

private final class ReviewSizingBoundary: UICollectionReusableView {
    var horizontal = false
    var extent: CGFloat = 75
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let result = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        if horizontal { result.size.width = extent } else { result.size.height = extent }
        return result
    }
}
