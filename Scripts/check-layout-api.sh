#!/bin/bash
# iOS 15 compile contract, including intentional compile failures.
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/listkit-api.XXXXXX)
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(rg --files Sources/ListKit -g '*.swift')
xcrun swiftc -emit-module -enable-testing -swift-version 6 -module-name ListKit \
    -sdk "$sdk_path" -target arm64-apple-ios15.0-simulator \
    -module-cache-path "$check_dir/cache" -emit-module-path "$check_dir/ListKit.swiftmodule" "${sources[@]}"
check() {
    local name="$1" expected="$2" snippet="$3"
    printf 'import UIKit\nimport ListKit\n@MainActor func example() {\n%s\n}\n' "$snippet" > "$check_dir/$name.swift"
    if xcrun swiftc -typecheck -swift-version 6 -sdk "$sdk_path" -target arm64-apple-ios15.0-simulator \
        -module-cache-path "$check_dir/cache" -I "$check_dir" "$check_dir/$name.swift" > "$check_dir/$name.log" 2>&1; then
        [ "$expected" = pass ] || { echo "UNEXPECTED SUCCESS: $name"; exit 1; }
    else
        [ "$expected" = fail ] || { cat "$check_dir/$name.log"; exit 1; }
    fi
    echo "$expected: $name"
}
check empty-section-builders pass 'let _ = ListSection(0) {} layout: {} supplementaries: {} decorations: {}
let _ = ListSection(0, rows: {}, layout: {}, supplementaries: {}, decorations: {})
let _ = ListSection(0) {}
    .layout {}
    .supplementaries {}
    .decorations {}
    .addingSupplementaries {}
    .addingDecorations {}'
check grid-naming pass 'let columns: [ListGridTrack] = [.init(.fixed(80)), .init(.flexible()), .init(.adaptive(minimumForCount: 60))]
let size: ListBoundaryMainAxisSize = .fixed(44)
let _ = GridLayout(tracks: columns).itemMainAxisSize(.fixed(44))
let _ = GridLayout(tracks: columns).itemMainAxisSize(.estimated(44))
let _ = BoundarySupplementaryLayout(kind: "title", mainAxisSize: size, sizingAxis: .vertical, alignment: .top)'
check grid-legacy-track fail 'let _ = GridTrack(.flexible())'
check grid-item-size pass 'let _: ListGridItemMainAxisSize = .estimated(44)'
check grid-legacy-absolute fail 'let _ = ListGridSize.absolute(44)'
check typed-layouts pass 'let _ = ListSection(0) {} layout: {
    EnvironmentLayout(layoutKey: 1) { env in
        if env.container.effectiveContentSize.width > 400 {
            GridLayout(tracks: [ListGridTrack(.adaptive(minimumForCount: 80))]).trackSpacing(8).lineSpacing(8)
        } else { UIKitListLayout() }
    }
}
let _ = ListSection(1) {} layout: {
    if #available(iOS 17.0, *) { GridLayout(tracks: 2).itemMainAxisSize(.uniform(estimated: 60)) }
    else { GridLayout(tracks: 2).itemMainAxisSize(.estimated(60)) }
}'
check optional-layouts pass 'let grid: ListSectionGridLayout? = GridLayout(tracks: 1)
let native: ListUIKitListLayout? = UIKitListLayout()
let value: ListSectionLayout? = nil
let _ = ListSection(0) {} layout: { grid }
let _ = ListSection(0) {} layout: { native }
let _ = ListSection(0) {} layout: { value }'
check complete-layout pass 'let title = "title"
let card = "card"
let _ = ListSection(0) {} layout: {
    GridLayout(tracks: 3)
        .boundarySupplementaries {
            BoundarySupplementaryLayout(kind: title, size: .init(width: .fractionalWidth(1), height: .estimated(44)), alignment: .top).pinToVisibleBounds()
        }
        .decorationItems {
            DecorationItemLayout(kind: card)
            DecorationItemLayout(kind: "overlay").whenContentExists()
        }
        .sectionInsets(.init(12)).itemMainAxisSize(.aspectRatio(1)).trackSpacing(8).lineSpacing(8)
} supplementaries: {
    SectionSupplementary(UICollectionReusableView.self, kind: title, id: 1) { _, _ in }
} decorations: {
    SectionDecoration(UICollectionReusableView.self, kind: card)
}'
check custom-layout pass 'let _ = ListSection(0) {} layout: {
    CustomLayout(layoutKey: 1, sectionInsets: .init(12)) { context in
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44))
        let item = NSCollectionLayoutItem(layoutSize: size, supplementaryItems: context.itemSupplementaries)
        let result = NSCollectionLayoutSection(group: .horizontal(layoutSize: size, subitem: item, count: 1))
        result.contentInsets = context.sectionInsets?.directionalEdgeInsets ?? .zero
        return result
    }.decorationItems(.none)
}'
check array-builders pass 'let kinds = ["a", "b"]
let _ = GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)).boundarySupplementaries {
    for kind in kinds {
        BoundarySupplementaryLayout(kind: kind, mainAxisSize: .aspectRatio(4), sizingAxis: .vertical, alignment: .top).whenContentExists()
    }
}.trackSpacing(8).lineSpacing(8)'
check optional-supplementary-content pass 'let present: ListSectionSupplementary<Int>? = SectionSupplementary(UICollectionReusableView.self, kind: "title", id: 0) { _, _ in }
let absent: ListSectionSupplementary<Int>? = nil
let _ = ListSection(0) {} supplementaries: {
    present
    absent
    SectionSupplementary(UICollectionReusableView.self, kind: "other", id: 1) { _, _ in }
}'
check decoration-kinds pass 'let logical = "card"
let typed = SectionDecoration(UICollectionReusableView.self, kind: logical)
let actual: String = typed.elementKind
let _ = SectionDecoration(kind: "manual", elementKind: actual)'
check removed-decoration-slot fail 'let _ = DecorationSlot("card")'
check removed-supplementary-slot fail 'let _ = SupplementarySlot("title")'
check manual-decoration-requires-element-kind fail 'let _ = SectionDecoration( kind: "manual")'
check multiple-layouts fail 'let _ = ListSection(0) {} layout: { GridLayout(tracks: 1).itemMainAxisSize(.estimated(44)); GridLayout(tracks: 2) }'
check legacy-background fail 'let _ = ListSection(0) {} background: { BackgroundDecoration(kind: "a"); BackgroundDecoration(kind: "b") }'
check legacy-id fail 'let _ = ListSection(0) {}.layout("grid")'
check direct-config fail 'let _ = ListSection(0) {}.layout(GridLayout(tracks: 2))'
check native-grid-size fail 'let _ = UIKitListLayout().itemMainAxisSize(.aspectRatio(1))'
check uniform-availability fail 'let _ = GridLayout(tracks: 2).itemMainAxisSize(.uniform(estimated: 60))'
check legacy-header fail 'let _ = ListSection(0) {} header: { Header(UICollectionReusableView.self, id: 0) { _, _ in } }'
check item-pinning fail 'let _ = ItemSupplementaryLayout(kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)), itemAnchor: .top).pinToVisibleBounds()'
check content-geometry fail 'let value: ListSectionSupplementary<Int> = SectionSupplementary(UICollectionReusableView.self, kind: "title", id: 0) { _, _ in }; let _ = value.layout(height: .absolute(44))'
echo "Logs: $check_dir"

check removed-list fail 'let _ = ListLayout()'
check removed-horizontal fail 'let _ = HorizontalLayout()'
check removed-columns fail 'let _ = GridLayout(columns: 2)'
check removed-rows fail 'let _ = GridLayout(rows: 2)'
check orthogonal-grid pass 'let _ = GridLayout(tracks: 2).itemMainAxisSize(.fillGroup)
    .gridCrossAxisSize(.fixed(220)).orthogonalScrolling(.groupPaging)
    .lineGrouping(.count(lines: 3, mainAxisSize: .fractionalViewport(1))).groupSpacing(16).trackGroupAlignment(.center)'
check boundary-no-fill fail 'let _ = BoundarySupplementaryLayout(kind: "header", mainAxisSize: .fillGroup, sizingAxis: .vertical, alignment: .top)'

check removed-frame fail 'let _ = GridLayout(tracks: 2).frame(height: 200)'
check removed-estimated-frame fail 'let _ = GridLayout(tracks: 1).estimatedFrame(height: 80)'
check removed-track-type fail 'let _ = ListGridItem(.fixed(80))'
check removed-item-size fail 'let _ = GridLayout(tracks: 1).itemSize(.fixed(44))'
check group-count-requires-unit fail 'let _ = GridLayout(tracks: 2).lineGrouping(.count(3))'
check boundary-no-uniform fail 'if #available(iOS 17.0, *) { let _ = BoundarySupplementaryLayout(kind: "header", mainAxisSize: .uniform(estimated: 44), sizingAxis: .vertical, alignment: .top) }'
check native-no-item-supplementaries fail 'let _ = UIKitListLayout().itemSupplementaries {}'
check provider-boundary-no-pinning fail 'let _ = CustomLayoutBoundary(kind: "header").pinToVisibleBounds()'
check provider-boundary-no-offset fail 'let _ = CustomLayoutBoundary(kind: "header").absoluteOffset(.zero)'
check boundary-no-center fail 'let _ = BoundarySupplementaryLayout(kind: "header", mainAxisSize: .fixed(44), sizingAxis: .vertical, alignment: .center)'
check layout-key-required fail 'let _ = ListSection(0) {} layout: { EnvironmentLayout(id: 0) { _ in GridLayout(tracks: 1) } }'
check independent-spacing pass 'let _ = GridLayout(tracks: 2).trackSpacing(10).lineSpacing(12).groupSpacing(20).gridCrossAxisSize(.fixed(220)).orthogonalScrolling(nil)'
check provider-boundary-reference pass 'let _ = ListSection(0) {} layout: { CustomLayout(layoutKey: 0) { _ in
    let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44))
    return NSCollectionLayoutSection(group: .horizontal(layoutSize: size, subitems: [.init(layoutSize: size)]))
}.boundarySupplementaries { CustomLayoutBoundary(kind: "title").whenContentExists() }.decorationItems(.registeredBackgrounds) }'
check removed-custom-inset-modifier fail 'let _ = ListSection(0) {} layout: { CustomLayout(layoutKey: 0) { _ in
    let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44))
    return NSCollectionLayoutSection(group: .horizontal(layoutSize: size, subitems: [.init(layoutSize: size)]))
}.sectionInsets(.init(12)) }'

check adaptive-requires-count-label fail 'let _ = ListGridTrack(.adaptive(minimum: 80))'
check removed-alignment fail 'let _ = GridLayout(tracks: 2).alignment(.center)'
check removed-fill fail 'let _ = GridLayout(tracks: 2).itemMainAxisSize(.fill)'
check removed-fit fail 'let _ = GridLayout(tracks: 2).lineGrouping(.fit(size: .fixed(300)))'
check removed-append-name fail 'let _ = ListSection(0) {}.sectionSupplementaries {}'

check removed-grid-content-insets fail 'let _ = GridLayout(tracks: 1).contentInsets(.init(12))'
check removed-native-content-insets fail 'let _ = UIKitListLayout().contentInsets(.init(12))'
check section-insets pass 'let _ = GridLayout(tracks: 2).sectionInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12)); let _ = UIKitListLayout().sectionInsets(.zero)'
check grid-no-provider-boundary fail 'let _ = GridLayout(tracks: 1).boundarySupplementaries { CustomLayoutBoundary(kind: "header") }'
check native-no-provider-boundary fail 'let _ = UIKitListLayout().boundarySupplementaries { CustomLayoutBoundary(kind: "header") }'
check no-provider-boundary-erasure fail 'let erased = ListLayoutArrayBuilder<BoundarySupplementaryLayout>.buildExpression(CustomLayoutBoundary(kind: "header")); let _ = erased[0].pinToVisibleBounds()'
check wrapped-boundary-no-pinning fail 'let values = ListLayoutArrayBuilder<ListBoundaryLayout>.buildExpression(CustomLayoutBoundary(kind: "header")); let _ = values[0].pinToVisibleBounds()'
check mixed-custom-boundaries pass 'let _ = ListSection(0) {} layout: {
    CustomLayout(layoutKey: 0, sectionInsets: .init(12)) { context in
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44))
        let section = NSCollectionLayoutSection(group: .horizontal(layoutSize: size, subitems: [.init(layoutSize: size)]))
        section.contentInsets = context.sectionInsets?.directionalEdgeInsets ?? .zero
        return section
    }.boundarySupplementaries {
        [CustomLayoutBoundary(kind: "provided").whenContentExists()]
        BoundarySupplementaryLayout(kind: "generated", mainAxisSize: .fixed(44), sizingAxis: .vertical, alignment: .top).whenContentExists()
    }
}'

check removed-grid-cross-axis-size fail 'let _ = GridLayout(tracks: 1).crossAxisSize(.fixed(100))'
check removed-generic-spacing fail 'let _ = GridLayout(tracks: 1).spacing(8)'
check removed-generic-group fail 'let _ = GridLayout(tracks: 1).group(.count(lines: 2))'
check removed-grouping-type fail 'let _: ListGridGrouping = .count(lines: 2)'
check removed-track-alignment fail 'let _ = GridLayout(tracks: 1).trackAlignment(.center)'
check removed-track-spacing-label fail 'let _ = ListGridTrack(.fixed(40), spacing: 8)'
check removed-track-spacing-property fail 'var value = ListGridTrack(.fixed(40)); value.spacing = 8'
check removed-boundary-axis-label fail 'let _ = BoundarySupplementaryLayout(kind: "h", mainAxisSize: .fixed(44), axis: .vertical, alignment: .top)'
check removed-boundary-pinned fail 'let _ = BoundarySupplementaryLayout(kind: "h", size: .init(width: .absolute(10), height: .absolute(10)), alignment: .top).pinned()'
check removed-boundary-offset fail 'let _ = BoundarySupplementaryLayout(kind: "h", size: .init(width: .absolute(10), height: .absolute(10)), alignment: .top).offset(.zero)'
check removed-item-anchor-label fail 'let _ = ItemSupplementaryLayout(kind: "b", size: .init(width: .absolute(10), height: .absolute(10)), anchor: .top)'
check removed-item-anchor-property fail 'var value = ItemSupplementaryLayout(kind: "b", size: .init(width: .absolute(10), height: .absolute(10)), itemAnchor: .top); value.anchor = .bottom'
check removed-item-fractional-offset fail 'let _ = ItemSupplementaryLayout(kind: "b", size: .init(width: .absolute(10), height: .absolute(10)), itemAnchor: .top).fractionalOffset(.zero)'
check removed-decoration-insets-label fail 'let _ = DecorationItemLayout(kind: "card", insets: .init(8))'
check removed-decoration-insets-property fail 'var value = DecorationItemLayout(kind: "card"); value.insets = .init(8)'
check explicit-layout-objects pass 'var track = ListGridTrack(.fixed(40), spacingAfter: 6); track.spacingAfter = 8
let grouping: ListGridLineGrouping = .count(lines: 2)
let _ = GridLayout(tracks: [track]).gridCrossAxisSize(.fixed(200)).trackSpacing(10).lineSpacing(10).lineGrouping(grouping).trackGroupAlignment(.center)
let _ = BoundarySupplementaryLayout(kind: "header", mainAxisSize: .fixed(44), sizingAxis: .vertical, alignment: .top).pinToVisibleBounds().absoluteOffset(.zero)
var badge = ItemSupplementaryLayout(kind: "badge", size: .init(width: .absolute(10), height: .absolute(10)), itemAnchor: .top).anchorFractionalOffset(.zero); badge.itemAnchor = .bottom
var background = DecorationItemLayout(kind: "card", backgroundInsets: .init(8)); background.backgroundInsets = .zero'
check removed-track-alignment-type fail 'let _: ListGridTrackAlignment = .center'
check track-group-alignment-type pass 'let alignment: ListGridTrackGroupAlignment = .center; let _ = GridLayout(tracks: 2).trackGroupAlignment(alignment)'
check removed-group-line-spacing-method fail 'let _ = GridLayout(tracks: 2).groupLineSpacing(8)'
check removed-group-line-spacing-property fail 'var value = GridLayout(tracks: 2); value.groupLineSpacing = 8'
check unified-line-spacing pass 'var value = GridLayout(tracks: 2).lineGrouping(.count(lines: 3)).lineSpacing(8).groupSpacing(20); value.lineSpacing = 12; let _: CGFloat = value.lineSpacing'

check section-composition pass 'let title: ListSectionSupplementary<Int> = SectionSupplementary(UICollectionReusableView.self, kind: "title", id: 0) { _, _ in }
let card = SectionDecoration(UICollectionReusableView.self, kind: "card")
let _ = ListSection(0) {}
    .layout { GridLayout(tracks: 1) }
    .supplementaries { title }
    .addingSupplementaries { }
    .decorations { card }
    .addingDecorations { }
    .supplementaries { }
    .decorations { }'
check removed-adding-section-supplementaries fail 'let _ = ListSection(0) {}.addingSectionSupplementaries { }'

check removed-grid-spacing fail 'let _ = GridLayout(tracks: 2).gridSpacing(8)'
check optional-group-spacing pass 'var value = GridLayout(tracks: 2).lineSpacing(8).groupSpacing(20).groupSpacing(nil); value.groupSpacing = nil; let _: CGFloat? = value.groupSpacing'
check mapped-supplementary-provider pass 'let _ = ProviderSupplementary("badge", id: 0, view: UICollectionReusableView.self) { collection, kind, path, context in
    let view = collection.lk.dequeue(UICollectionReusableView.self, ofKind: kind, for: path)
    view.tag = context.indexPath.item
    return view
}'
check mapped-supplementary-address pass 'let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
let adapter = CollectionListAdapter<Int>(collectionView: collection)
if let address = adapter.supplementaryElement(ofKind: "badge", at: IndexPath(item: 3, section: 0)) {
    _ = collection.supplementaryView(forElementKind: address.elementKind, at: address.indexPath)
}'
