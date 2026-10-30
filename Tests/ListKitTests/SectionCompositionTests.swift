import ListKit
import UIKit
import XCTest

/// Compile composition through the public API, then resolve it through the adapter.
@MainActor
final class SectionCompositionTests: XCTestCase {
    func testEmptyInitializerBuildersMatchOmittedDefaults() {
        let explicit = ListSection(7) {} layout: {} supplementaries: {} decorations: {}
        let labeled = ListSection(7, rows: {}, layout: {}, supplementaries: {}, decorations: {})
        let defaults = ListSection(7) {}
        for section in [explicit, labeled] {
            XCTAssertTrue(section.rows.isEmpty)
            XCTAssertTrue(section.outlineRoots.isEmpty)
            XCTAssertTrue(section.supplementaries.isEmpty)
            XCTAssertTrue(section.decorations.isEmpty)
            XCTAssertEqual(section.layoutSource, defaults.layoutSource)
            XCTAssertTrue(ListDiagnostics.validate([section]).isEmpty)
        }
    }

    func testEmptyLayoutResetsGeometryAndPreservesContent() {
        let original = ListSection(7) { rows() } layout: { grid }
            supplementaries: { header() } decorations: { card }
        let reset = original.layout {}
        XCTAssertEqual(reset.layoutSource, ListSection(7) {}.layoutSource)
        XCTAssertEqual(reset.rows.map(\.identity), original.rows.map(\.identity))
        XCTAssertEqual(reset.supplementaries.map(\.identity), original.supplementaries.map(\.identity))
        XCTAssertEqual(reset.decorations, original.decorations)
        XCTAssertTrue(ListDiagnostics.validate([reset]).isEmpty)
        let layout = reset.resolvedForTesting()
        XCTAssertTrue(layout.boundarySupplementaryItems.isEmpty)
        XCTAssertEqual(layout.decorationItems.map(\.elementKind), [card.elementKind])
        XCTAssertEqual(layout.decorationItems.first?.contentInsets, .zero)
    }

    private func header(_ kind: String = "title", version: Int = 1) -> ListSectionSupplementary<Int> {
        SectionSupplementary(UICollectionReusableView.self, kind: kind, id: kind) { view, _ in
            view.accessibilityLabel = "version \(version)"
        }
        .refreshID(version)
    }

    private var grid: ListSectionGridLayout {
        GridLayout(tracks: 1)
            .itemMainAxisSize(.fixed(44))
            .sectionInsets(.init(8))
            .boundarySupplementaries {
                BoundarySupplementaryLayout(
                    kind: "title",
                    size: .init(width: .fractionalWidth(1), height: .absolute(36)),
                    alignment: .top
                )
            }
            .decorationItems {
                DecorationItemLayout(kind: "card", backgroundInsets: .init(4))
            }
    }

    private var card: SectionDecoration {
        SectionDecoration(UICollectionReusableView.self, kind: "card")
    }

    private func rows() -> RowGroup {
        ForEach([1, 2], id: \.self) { value in
            Row(model: value, cell: UICollectionViewCell.self) { _, _, _ in }
                .refreshID(value)
        }
    }

    func testTrailingClosuresAndChainedValuesResolveTheSameSection() {
        let inline = ListSection(7) {
            rows()
        } layout: {
            grid
        } supplementaries: {
            header()
        } decorations: {
            card
        }
        let chained = ListSection(7) { rows() }
            .layout { grid }
            .supplementaries { header() }
            .decorations { card }

        XCTAssertEqual(inline.rows.map(\.identity), chained.rows.map(\.identity))
        XCTAssertEqual(inline.rows.map(\.refreshID), chained.rows.map(\.refreshID))
        XCTAssertEqual(inline.layoutSource, chained.layoutSource)
        XCTAssertEqual(inline.supplementaries.map(\.identity), chained.supplementaries.map(\.identity))
        XCTAssertEqual(inline.supplementaries.map(\.refreshID), chained.supplementaries.map(\.refreshID))
        XCTAssertEqual(inline.decorations, chained.decorations)
        for section in [inline, chained] {
            XCTAssertTrue(ListDiagnostics.validate([section]).isEmpty)
            let layout = section.resolvedForTesting()
            XCTAssertEqual(layout.contentInsets, NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            XCTAssertEqual(layout.boundarySupplementaryItems.map(\.elementKind), ["title"])
            XCTAssertEqual(layout.decorationItems.map(\.elementKind), [card.elementKind])
            XCTAssertEqual(layout.decorationItems.first?.contentInsets, NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }

    func testReplacementKeepsLayoutAndRoutesLatestContent() async throws {
        let original = ListSection(7) { rows() } layout: { grid }
            supplementaries: { header(version: 1) } decorations: { card }
        let replaced = original
            .supplementaries { header(version: 2) }
            .supplementaries { header(version: 3) }
        XCTAssertEqual(original.supplementaries.first?.refreshID, AnyListID(1))
        XCTAssertEqual(replaced.supplementaries.count, 1)
        XCTAssertEqual(replaced.supplementaries.first?.identity, original.supplementaries.first?.identity)
        XCTAssertEqual(replaced.supplementaries.first?.refreshID, AnyListID(3))
        XCTAssertEqual(replaced.layoutSource, original.layoutSource)
        XCTAssertEqual(replaced.decorations, original.decorations)
        XCTAssertEqual(replaced.rows.map(\.identity), original.rows.map(\.identity))

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        controller.view.addSubview(collection)
        let adapter = CollectionListAdapter<Int>(collectionView: collection)
        collection.collectionViewLayout = adapter.makeCompositionalLayout()
        await adapter.apply(options: .init(transaction: .disabled)) { original }
        collection.layoutIfNeeded()
        let indexPath = IndexPath(item: 0, section: 0)
        let originalView = try XCTUnwrap(collection.supplementaryView(forElementKind: "title", at: indexPath))
        XCTAssertEqual(originalView.accessibilityLabel, "version 1")
        await adapter.apply(options: .init(transaction: .disabled)) { replaced }
        collection.layoutIfNeeded()
        let view = try XCTUnwrap(collection.supplementaryView(forElementKind: "title", at: indexPath))
        XCTAssertEqual(view.accessibilityLabel, "version 3")
        XCTAssertTrue(view === originalView)
    }

    func testEmptySettersClearDeclarationsWithoutSilentlyDeletingRequiredGeometry() {
        let original = ListSection(7) {} layout: { grid }
            supplementaries: { header() } decorations: { card }
        let cleared = original.supplementaries {}.decorations {}
        XCTAssertTrue(cleared.supplementaries.isEmpty)
        XCTAssertTrue(cleared.decorations.isEmpty)
        XCTAssertEqual(cleared.layoutSource, original.layoutSource)
        let messages = ListDiagnostics.validate([cleared]).map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("missing content for kind title") })
        XCTAssertTrue(messages.contains { $0.contains("missing decoration content for kind card") })

        let recovered = cleared.supplementaries { header() }.decorations { card }
        XCTAssertTrue(ListDiagnostics.validate([recovered]).isEmpty)
        XCTAssertEqual(recovered.resolvedForTesting().boundarySupplementaryItems.count, 1)
        XCTAssertEqual(recovered.resolvedForTesting().decorationItems.count, 1)
    }

    func testAddingBuildersPreserveOrderAndDoNotOverwriteDuplicates() {
        let absentHeader: ListSectionSupplementary<Int>? = nil
        let absentDecoration: SectionDecoration? = nil
        let base = ListSection(7) {} supplementaries: { header() } decorations: { card }
        let extended = base.addingSupplementaries {
            absentHeader
            [header("subtitle")]
            for kind in ["footnote", "footer"] { header(kind) }
            if true { header("badge") }
        }.addingDecorations {
            absentDecoration
            [SectionDecoration(UICollectionReusableView.self, kind: "overlay")]
            if true { SectionDecoration(UICollectionReusableView.self, kind: "border") }
        }
        XCTAssertEqual(extended.supplementaries.map(\.kind), ["title", "subtitle", "footnote", "footer", "badge"])
        XCTAssertEqual(extended.decorations.map(\.kind), ["card", "overlay", "border"])
        XCTAssertTrue(ListDiagnostics.validate([extended]).isEmpty)
        XCTAssertEqual(extended.resolvedForTesting().decorationItems.count, 3)
        XCTAssertEqual(extended.addingSupplementaries {}.supplementaries.map(\.identity), extended.supplementaries.map(\.identity))
        XCTAssertEqual(extended.addingDecorations {}.decorations, extended.decorations)
        XCTAssertEqual(base.supplementaries.count, 1)
        XCTAssertEqual(base.decorations.count, 1)

        let duplicateHeader = extended.addingSupplementaries { header(version: 2) }
        XCTAssertTrue(ListDiagnostics.validate([duplicateHeader]).contains { $0.kind == .duplicateSupplementaryKind })
        let duplicateCard = extended.addingDecorations { card }
        XCTAssertTrue(ListDiagnostics.validate([duplicateCard]).contains { $0.message.contains("duplicate decoration logical kind") })
    }

    func testDecorationReplacementUpdatesDefaultGeometryAndLayoutReplacementKeepsContent() {
        let base = ListSection(7) {}.supplementaries { header() }.decorations { card }
        let overlay = SectionDecoration(UICollectionReusableView.self, kind: "overlay")
        let replaced = base.addingDecorations { overlay }.decorations { overlay }
        XCTAssertEqual(replaced.resolvedForTesting().decorationItems.map(\.elementKind), [overlay.elementKind])
        XCTAssertTrue(replaced.decorations {}.resolvedForTesting().decorationItems.isEmpty)

        let relaid = base.layout { grid }.layout { GridLayout(tracks: 2) }
        XCTAssertEqual(relaid.supplementaries.map(\.identity), base.supplementaries.map(\.identity))
        XCTAssertEqual(relaid.decorations, base.decorations)
        XCTAssertTrue(relaid.resolvedForTesting().boundarySupplementaryItems.isEmpty)
        XCTAssertEqual(relaid.resolvedForTesting().decorationItems.first?.contentInsets, .zero)
    }
}
