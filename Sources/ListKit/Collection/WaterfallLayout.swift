import UIKit

/// 自动测量标准 Row 的瀑布流。纵向固定轨道宽度、测量高度；横向固定轨道高度、测量宽度。
/// 内容方向与 GridLayout 一致，由外层滚动方向和 orthogonalScrolling 共同决定。
/// 首次解析预先测量全部条目；后续由 adapter 按内容版本和环境缓存尺寸。
public struct ListSectionWaterfallLayout: Hashable, Sendable {
    // 复用 Grid 的轨道解析、校验与方向语义，不复用其按行分组的排布。
    var grid: ListSectionGridLayout
    var options: ListSectionLayoutOptions { grid.options }
    var validationErrors: [String] { grid.validationErrors }

    init(tracks: ListSectionGridLayout.Tracks) {
        grid = ListSectionGridLayout(tracks: tracks).itemMainAxisSize(.fixed(1))
    }

    /// 相邻轨道的默认间距，默认 0，可被轨道的 spacing 覆盖。
    public func trackSpacing(_ value: CGFloat) -> Self {
        var copy = self; copy.grid = grid.trackSpacing(value); return copy
    }
    /// 同一轨道内相邻条目的主轴间距，默认 0；末尾不添加间距。
    public func lineSpacing(_ value: CGFloat) -> Self {
        var copy = self; copy.grid = grid.lineSpacing(value); return copy
    }
    /// 固定整个轨道区域的交叉轴尺寸；nil 恢复环境提供的尺寸。正交滚动时可用于限定行高区域。
    public func crossAxisSize(_ value: CGFloat?) -> Self {
        var copy = self; copy.grid = grid.crossAxisSize(value.map { .fixed($0) }); return copy
    }
    /// 轨道区域在交叉轴上的对齐，默认 start。
    public func alignment(_ value: ListGridAlignment) -> Self {
        var copy = self; copy.grid = grid.alignment(value); return copy
    }
    /// 非 nil 时内容方向与外层方向垂直。整个瀑布流为一个 group，分页行为以整个 group 为单位。
    public func orthogonalScrolling(_ value: ListOrthogonalScrollingBehavior?) -> Self {
        var copy = self; copy.grid = grid.orthogonalScrolling(value); return copy
    }
    /// 设置 Section 内边距，不改变 Cell padding 或 CollectionView contentInset。
    public func sectionInsets(_ value: ListLayoutInsets) -> Self {
        var copy = self; copy.grid = grid.sectionInsets(value); return copy
    }
    /// 完整替换 header/footer 等边界布局声明。
    public func boundarySupplementaries(
        @ListLayoutArrayBuilder<BoundarySupplementaryLayout> _ content: () -> [BoundarySupplementaryLayout]
    ) -> Self {
        var copy = self; copy.grid = grid.boundarySupplementaries(content); return copy
    }
    /// 设置已注册背景的默认生成策略。
    public func decorationItems(_ policy: ListDecorationLayoutPolicy) -> Self {
        var copy = self; copy.grid = grid.decorationItems(policy); return copy
    }
    /// 完整替换背景装饰几何声明。
    public func decorationItems(
        @ListLayoutArrayBuilder<DecorationItemLayout> _ content: () -> [DecorationItemLayout]
    ) -> Self {
        var copy = self; copy.grid = grid.decorationItems(content); return copy
    }

    @MainActor func makeSection(
        environment: any NSCollectionLayoutEnvironment,
        scrollDirection: ListAxis,
        itemCount: Int,
        measure: (Int, CGFloat, ListAxis) throws -> CGFloat
    ) throws -> NSCollectionLayoutSection {
        let geometry = try grid.geometry(in: environment, scrollDirection: scrollDirection)
        let vertical = geometry.axis == .vertical
        var ends = Array(repeating: CGFloat.zero, count: geometry.tracks.count)
        var occupied = Array(repeating: false, count: ends.count)
        var offsets: [CGFloat] = []
        var crossOffset = geometry.alignmentOffset
        for track in geometry.tracks {
            offsets.append(crossOffset)
            crossOffset += track.extent + track.spacing
        }
        var items: [NSCollectionLayoutGroupCustomItem] = []
        for item in 0..<itemCount {
            // 相同高度时稳定选择逻辑起始侧轨道。UIKit 负责 RTL 镜像。
            let track = ends.indices.min { lhs, rhs in
                let a = ends[lhs] + (occupied[lhs] ? grid.lineSpacing : 0)
                let b = ends[rhs] + (occupied[rhs] ? grid.lineSpacing : 0)
                return a == b ? lhs < rhs : a < b
            }!
            let cross = geometry.tracks[track].extent
            let main = try measure(item, cross, geometry.axis)
            let origin = ends[track] + (occupied[track] ? grid.lineSpacing : 0)
            guard main.isFinite, main > 0, (origin + main).isFinite else {
                throw ListWaterfallError("item \(item) returned a nonpositive/nonfinite measured size")
            }
            let frame = vertical
                ? CGRect(x: offsets[track], y: origin, width: cross, height: main)
                : CGRect(x: origin, y: offsets[track], width: main, height: cross)
            items.append(NSCollectionLayoutGroupCustomItem(frame: frame))
            ends[track] = origin + main
            occupied[track] = true
        }
        // UIKit 要求 group 尺寸为正；空 section 无 item，只保留边界与最小占位。
        let main = max(1 / max(1, environment.traitCollection.displayScale), ends.max() ?? 0)
        let container = environment.container.effectiveContentSize
        let insets = grid.sectionInsets
        let available = vertical ? container.width - insets.leading - insets.trailing
            : container.height - insets.top - insets.bottom
        let cross = geometry.fixedCrossExtent ?? max(geometry.crossExtent, max(1, available))
        let size = NSCollectionLayoutSize(
            widthDimension: .absolute(vertical ? cross : main),
            heightDimension: .absolute(vertical ? main : cross))
        let resolvedItems = items
        let group = NSCollectionLayoutGroup.custom(layoutSize: size) { _ in resolvedItems }
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = grid.sectionInsets.directionalEdgeInsets
        section.orthogonalScrollingBehavior = grid.scrollingBehavior?.uiKitValue ?? .none
        return section
    }
}

/// 创建等分轨道的自动测量瀑布流。标准 Row 无需额外测量闭包。
public func WaterfallLayout(tracks: Int) -> ListSectionWaterfallLayout { .init(tracks: .count(tracks)) }

/// 创建固定、弹性或自适应轨道的自动测量瀑布流。条目放入最短轨道，再按该轨道尺寸测量。
public func WaterfallLayout(tracks: [ListGridTrack]) -> ListSectionWaterfallLayout {
    .init(tracks: .definitions(tracks))
}

struct ListWaterfallError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = "WaterfallLayout: " + description }
}
