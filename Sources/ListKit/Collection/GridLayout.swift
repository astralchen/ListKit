// Adapted from UIKitGridLayouts 89aa339cc5651147c3c6265c0c931dd701bb45a7.
// Copyright (c) 2026 Sondra. MIT license: ThirdPartyNotices/UIKitGridLayouts-LICENSE.txt.
import UIKit

/// 根据内容方向排列轨道的分区网格布局。
///
/// 单轨道可用于普通列表。轨道在纵向内容中表示列，在横向内容中表示行；
/// 内容方向由外层滚动方向和正交滚动配置共同决定。
/// 默认不启用正交滚动，条目主轴使用 44 点估算尺寸，各类间距为零。
public struct ListSectionGridLayout: Hashable, Sendable {
    /// 交叉轴轨道的声明方式；自适应轨道展开后的实际数量可能多于定义数量。
    public enum Tracks: Hashable, Sendable {
        /// 指定等分的弹性轨道数量，有效范围为 1...10000。
        case count(Int)
        /// 按顺序组合固定、弹性或自适应轨道。
        case definitions([ListGridTrack])
    }
    /// 交叉轴轨道配置；纵向内容对应列，横向内容对应行。
    public var tracks: Tracks
    /// 每个条目沿内容延伸方向的尺寸策略，默认使用 44 点估算值并由内容自适应。
    public var itemMainAxisSize: ListGridItemMainAxisSize = .estimated(44)
    /// 相邻轨道的默认间距，可由单条轨道的 spacingAfter 覆盖。
    public var trackSpacing: CGFloat = 0
    /// 内容方向上相邻行／列的间距；未覆盖 groupSpacing 时也用于组间，默认 0。
    public var lineSpacing: CGFloat = 0
    /// 顶层 group 之间的可选间距覆盖；nil 使用当前 lineSpacing，0 表示明确无组间距。
    public var groupSpacing: CGFloat? = nil
    /// 分区通用布局选项，包含分区内边距等配置。
    var options = ListSectionLayoutOptions()
    /// 网格交叉轴尺寸的显式配置；未设置时使用容器扣除分区内边距后的可用尺寸。
    var crossAxisSizing: ListGridCrossAxisSize?
    /// 正交滚动行为；设置后，内容沿外层滚动方向的垂直方向延伸。
    var scrollingBehavior: ListOrthogonalScrollingBehavior?
    /// 顶层组的行数与主轴尺寸策略，默认每组包含一行。
    var grouping: ListGridLineGrouping = .count(lines: 1)
    /// 轨道整体在交叉轴剩余空间中的对齐方式，默认靠起始侧。
    var crossAlignment: ListGridTrackGroupAlignment = .start
    /// 通过通用选项读写分区内边距，未指定时按零处理。
    var sectionInsets: ListLayoutInsets {
        get { options.sectionInsets ?? .zero }
        set { options.sectionInsets = newValue }
    }
    /// 保存轨道声明，其余布局配置使用默认值。
    init(tracks: Tracks) { self.tracks = tracks }
    /// 根据外层滚动方向与正交滚动配置，确定网格内容的主轴方向。
    func contentAxis(for outer: ListLayoutScrollDirection) -> ListLayoutScrollDirection {
        scrollingBehavior == nil ? outer : (outer == .vertical ? .horizontal : .vertical)
    }
    /// 将数量声明转为弹性轨道定义；数量在展开时限制范围，原始非法值仍由验证报告。
    var definitions: [ListGridTrack] {
        switch tracks {
        case .count(let count):
            Array(repeating: ListGridTrack(.flexible(minimum: 1)), count: max(1, min(10000, count)))
        case .definitions(let values): values
        }
    }
    /// 检查不依赖容器的配置约束，包括数量、尺寸、间距和内边距。
    var validationErrors: [String] {
        var errors: [String] = []
        if case .count(let count) = tracks, !(1...10000).contains(count) {
            errors.append("grid count must be 1...10000")
        }
        if definitions.isEmpty || definitions.count > 10000 {
            errors.append("grid requires 1...10000 tracks")
        }
        for value in [
            trackSpacing, lineSpacing, groupSpacing ?? lineSpacing, sectionInsets.top, sectionInsets.leading,
            sectionInsets.bottom, sectionInsets.trailing,
        ] where !value.isFinite || value < 0 {
            errors.append("grid spacing/insets must be finite and nonnegative")
        }
        if !itemMainAxisSize.isValid { errors.append("grid item size/ratio must be finite and positive") }
        if let dimension = crossAxisSizing {
            switch dimension {
            case .fixed(let value), .estimated(let value):
                if !value.isFinite || value <= 0 { errors.append("gridCrossAxisSize must be finite and positive") }
            }
        }
        switch grouping {
        case .count(let count, let size):
            if !(1...10000).contains(count) { errors.append("group count must be 1...10000") }
            if let size, !size.isValid { errors.append("invalid group size") }
        case .fitting(let size): if !size.isValid { errors.append("invalid group size") }
        }
        for (index, track) in definitions.enumerated() {
            let gap = track.spacingAfter ?? trackSpacing
            if !gap.isFinite || gap < 0 {
                errors.append("grid track \(index) spacing must be finite and nonnegative")
            }
            switch track.size {
            case .fixed(let value):
                if !value.isFinite || value <= 0 {
                    errors.append("grid track \(index) fixed size must be finite and positive")
                }
            case .flexible(let minimum, let maximum), .adaptive(let minimum, let maximum):
                if !minimum.isFinite || minimum <= 0 || maximum.isNaN || maximum < minimum {
                    errors.append("grid track \(index) requires finite positive minimum <= maximum")
                }
            }
        }
        return errors
    }
    /// 在实际容器环境中尝试解析几何信息，将尺寸溢出或不兼容的配置转换为错误描述。
    @MainActor func environmentValidationErrors(
        in environment: any NSCollectionLayoutEnvironment,
        scrollDirection: ListLayoutScrollDirection = .vertical
    ) -> [String] {
        do { _ = try geometry(in: environment, scrollDirection: scrollDirection); return [] } catch {
            return [String(describing: error)]
        }
    }
    /// 检查实际轨道是否等宽／等高且间距一致，以满足重复条目组挂载附属视图的条件。
    /// 几何解析失败时返回 false；比较尺寸和间距时允许小于 0.001 点的误差。
    @MainActor func supportsItemSupplementaries(
        in environment: any NSCollectionLayoutEnvironment,
        scrollDirection: ListLayoutScrollDirection = .vertical
    ) -> Bool {
        guard let geometry = try? geometry(in: environment, scrollDirection: scrollDirection),
            let first = geometry.tracks.first
        else { return false }
        return geometry.tracks.allSatisfy { abs($0.extent - first.extent) < 0.001 }
            && geometry.tracks.dropLast().allSatisfy { abs($0.spacing - first.spacing) < 0.001 }
    }
    /// 解析当前环境并构建 UIKit 分区；配置无法解析时触发前置条件失败。
    /// lineSupplementaries 按组内行序提供附属视图，传入时应覆盖解析后的全部行。
    @MainActor func makeSection(
        environment: any NSCollectionLayoutEnvironment,
        itemSupplementaries: [NSCollectionLayoutSupplementaryItem],
        scrollDirection: ListLayoutScrollDirection = .vertical,
        lineSupplementaries: [[NSCollectionLayoutSupplementaryItem]]? = nil
    ) -> NSCollectionLayoutSection {
        do {
            let geometry = try geometry(in: environment, scrollDirection: scrollDirection)
            return ListGridLayoutBuilder.makeSection(
                configuration: self, geometry: geometry,
                itemSupplementaries: itemSupplementaries, lineSupplementaries: lineSupplementaries)
        } catch { preconditionFailure("ListKit: \(error)") }
    }
}

/// 创建具有指定数量等分轨道的网格布局。
///
/// 单轨道可用于普通列表。条目主轴默认使用 44 点估算尺寸，单元格须提供自适应尺寸。
///
/// - Parameter tracks: 交叉轴轨道数量，有效范围为 1...10000。
/// - Returns: 使用默认尺寸、间距和对齐配置的网格布局。
public func GridLayout(tracks: Int) -> ListSectionGridLayout { .init(tracks: .count(tracks)) }
/// 创建使用指定轨道定义的网格布局。
///
/// 固定、弹性和自适应轨道可混合使用；一个自适应定义可以展开为多条实际轨道。
///
/// - Parameter tracks: 按交叉轴顺序排列的轨道定义，数量须为 1...10000。
/// - Returns: 纵向内容按列宽、横向内容按行高解析轨道的网格布局。
public func GridLayout(tracks: [ListGridTrack]) -> ListSectionGridLayout {
    .init(tracks: .definitions(tracks))
}

extension ListSectionGridLayout {
    /// 当前容器环境下解析出的几何快照，供 UIKit 布局构建阶段直接使用。
    struct Geometry {
        /// 网格内容实际延伸的主轴方向。
        let axis: ListLayoutScrollDirection
        /// 已展开自适应定义的实际轨道，包含交叉轴尺寸与尾部间距。
        let tracks: [ListGridLayoutBuilder.Track]
        /// 与实际轨道逐一对应的条目主轴尺寸；自适应内容在此保存估算值。
        let mainExtents: [CGFloat]
        /// 所有实际轨道及其间距占用的交叉轴总尺寸。
        let crossExtent: CGFloat
        /// 显式配置的交叉轴估算值；存在时构建估算尺寸而非绝对尺寸。
        let crossEstimate: CGFloat?
        /// 显式固定的交叉轴外框尺寸，可能大于轨道实际占用的尺寸。
        let fixedCrossExtent: CGFloat?
        /// 为实现交叉轴对齐而在起始侧预留的偏移量。
        let alignmentOffset: CGFloat
        /// 单行的主轴尺寸，取该行各轨道条目尺寸的最大值。
        let unitExtent: CGFloat
        /// 一个顶层组沿主轴包含的行数。
        let count: Int
        /// 顶层组的主轴尺寸，包含行间距及显式组尺寸留下的空白。
        let groupExtent: CGFloat
        /// 条目需要内容自适应时，行与顶层组也使用估算主轴尺寸。
        let estimatedGroup: Bool
    }
    /// 将声明式配置解析为具体几何信息，并验证尺寸依赖、组容量及溢出约束。
    /// 主轴沿内容方向延伸，交叉轴用于排列轨道；容器尺寸取自当前布局环境。
    @MainActor func geometry(
        in environment: any NSCollectionLayoutEnvironment,
        scrollDirection: ListLayoutScrollDirection
    ) throws -> Geometry {
        func fail(_ message: String) -> ListGridLayoutBuilder.ResolutionError { .init(description: message) }
        guard validationErrors.isEmpty else { throw fail(validationErrors.joined(separator: "; ")) }
        let axis = contentAxis(for: scrollDirection)
        let vertical = axis == .vertical
        let container = environment.container.effectiveContentSize
        guard container.width.isFinite, container.height.isFinite else { throw fail("nonfinite container") }
        let insets = sectionInsets
        let crossInsets = vertical ? insets.leading + insets.trailing : insets.top + insets.bottom
        let mainInsets = vertical ? insets.top + insets.bottom : insets.leading + insets.trailing
        guard crossInsets.isFinite, mainInsets.isFinite else { throw fail("grid insets overflow") }
        // 先扣除分区内边距；显式交叉轴尺寸会覆盖计算出的可用尺寸。
        let crossSize = crossAxisSizing
        var available = max(1, (vertical ? container.width : container.height) - crossInsets)
        var crossEstimate: CGFloat?
        switch crossSize {
        case .fixed(let value): available = value
        case .estimated(let value): available = value; crossEstimate = value
        case nil: break
        }
        let viewport = max(1, (vertical ? container.height : container.width) - mainInsets)
        let resolved = try ListGridLayoutBuilder.checkedResolve(
            definitions,
            availableExtent: available, defaultSpacing: trackSpacing)
        // 估算交叉轴仅支持单轨道，且不能作为宽高比计算所需的最终尺寸。
        if crossEstimate != nil {
            guard case .count(1) = tracks else { throw fail("estimated gridCrossAxisSize requires tracks: 1") }
            if case .measured(let measured) = itemMainAxisSize.storage, measured.requiresResolvedCrossExtent {
                throw fail("aspectRatio requires a resolved cross size; estimated gridCrossAxisSize is not a final size")
            }
        }
        let totalCross = resolved.reduce(0) { $0 + $1.extent + $1.spacing }
        guard totalCross.isFinite, totalCross > 0 else { throw fail("grid cross extent overflow") }
        if case .fixed = crossSize, totalCross > available + 0.001 {
            throw fail("tracks and spacing overflow fixed gridCrossAxisSize")
        }
        let requestedCount: Int?
        let explicitSize: ListGridGroupMainAxisSize?
        switch grouping {
        case .count(let count, let size): requestedCount = count; explicitSize = size
        case .fitting(let size): requestedCount = nil; explicitSize = size
        }
        let explicitExtent = explicitSize?.extent(viewport: viewport)
        if let explicitExtent, !explicitExtent.isFinite || explicitExtent <= 0 {
            throw fail("group size overflow")
        }
        // 按轨道尺寸、视口或显式组尺寸解析条目主轴尺寸，拒绝缺少依赖的尺寸策略。
        let mainExtents: [CGFloat] = try resolved.map { track in
            let value: CGFloat
            switch itemMainAxisSize.storage {
            case .measured(let measured):
                guard let extent = measured.checkedExtent(crossExtent: track.extent, isVertical: vertical)
                else {
                    throw fail("grid resolved main-axis size must be finite and positive")
                }
                value = extent
            case .fractionalViewport(let fraction): value = viewport * fraction
            case .fractionalGroup(let fraction):
                guard let explicitExtent else {
                    throw fail("fractionalGroup requires explicit group size (size cycle)")
                }
                value = explicitExtent * fraction
            case .fillGroup:
                guard let explicitExtent, let requestedCount else {
                    throw fail("fillGroup requires explicit group lines and mainAxisSize")
                }
                value = (explicitExtent - CGFloat(requestedCount - 1) * lineSpacing) / CGFloat(requestedCount)
            }
            guard value.isFinite, value > 0 else {
                throw fail("grid resolved main-axis size must be finite and positive")
            }
            return value
        }
        let unit = mainExtents.max()!
        let count: Int
        if let requestedCount {
            count = requestedCount
        } else {
            guard !itemMainAxisSize.isSelfSizing else {
                throw fail(
                    "fitting requires resolved item sizes; estimated content must use natural/count groups or CustomLayout"
                )
            }
            // 最后一行不需要尾部行间距，因此在容量公式的分子中补回一次间距。
            let capacity = floor((explicitExtent! + lineSpacing) / (unit + lineSpacing))
            guard capacity.isFinite, capacity >= 1, capacity <= 10000 else {
                throw fail("fitting capacity must be 1...10000")
            }
            count = Int(capacity)
        }
        guard count * resolved.count <= 10000 else { throw fail("group capacity exceeds 10000 items") }
        if itemMainAxisSize.isSelfSizing && explicitExtent != nil {
            throw fail(
                "self-sizing items require content-sized groups; fixed group cannot guarantee measured capacity"
            )
        }
        // 显式组尺寸可以保留空白，但不能小于所有行及其间距占用的尺寸。
        let contentExtent = unit * CGFloat(count) + lineSpacing * CGFloat(count - 1)
        let groupExtent = explicitExtent ?? contentExtent
        guard contentExtent.isFinite, groupExtent.isFinite, groupExtent > 0 else {
            throw fail("group extent overflow")
        }
        guard contentExtent <= groupExtent + 0.001 else {
            throw fail("items and spacing overflow explicit group size")
        }
        return Geometry(
            axis: axis, tracks: resolved, mainExtents: mainExtents, crossExtent: totalCross,
            crossEstimate: crossEstimate,
            fixedCrossExtent: crossEstimate == nil && crossSize != nil ? available : nil,
            alignmentOffset: max(0, available - totalCross) * crossAlignment.fraction,
            unitExtent: unit, count: count, groupExtent: groupExtent, estimatedGroup: itemMainAxisSize.isSelfSizing)
    }
}

/// 将已解析的网格几何信息转换为 UIKit 布局对象，并提供轨道分配算法。
@MainActor enum ListGridLayoutBuilder {
    /// 先构建单行轨道组，再沿主轴组合多行，最后应用对齐、内边距与滚动行为。
    static func makeSection(
        configuration: ListSectionGridLayout, geometry g: ListSectionGridLayout.Geometry,
        itemSupplementaries: [NSCollectionLayoutSupplementaryItem],
        lineSupplementaries: [[NSCollectionLayoutSupplementaryItem]]? = nil
    ) -> NSCollectionLayoutSection {
        let vertical = g.axis == .vertical
        /// 根据内容方向，将主轴与交叉轴尺寸映射为 UIKit 的宽度和高度。
        func layoutSize(main: NSCollectionLayoutDimension, cross: NSCollectionLayoutDimension)
            -> NSCollectionLayoutSize
        {
            .init(widthDimension: vertical ? cross : main, heightDimension: vertical ? main : cross)
        }
        let equalSpacing = g.tracks.dropLast().allSatisfy { abs($0.spacing - g.tracks[0].spacing) < 0.001 }
        /// 显式交叉轴估算值优先，否则使用已解析的绝对尺寸。
        func crossDimension(_ value: CGFloat) -> NSCollectionLayoutDimension {
            g.crossEstimate.map { .estimated($0) } ?? .absolute(value)
        }
        /// 构建包含全部交叉轴轨道的一行，并为条目复制附属视图布局声明。
        func makeUnit(_ supplementaries: [NSCollectionLayoutSupplementaryItem]) -> NSCollectionLayoutGroup {
            let items = g.tracks.enumerated().map { index, track in
                let main: NSCollectionLayoutDimension
                if case .measured(let measured) = configuration.itemMainAxisSize.storage {
                    main = measured.dimension(crossExtent: track.extent, isVertical: vertical)
                } else {
                    main = .absolute(g.mainExtents[index])
                }
                let item = NSCollectionLayoutItem(
                    layoutSize: layoutSize(main: main, cross: crossDimension(track.extent)),
                    supplementaryItems: supplementaries.map {
                        $0.copy() as! NSCollectionLayoutSupplementaryItem
                    })
                // 间距不统一时逐条设置尾部间距；统一间距在行组上集中设置。
                if !equalSpacing && index < g.tracks.count - 1 {
                    item.edgeSpacing = .init(
                        leading: nil, top: nil,
                        trailing: vertical ? .fixed(track.spacing) : nil,
                        bottom: vertical ? nil : .fixed(track.spacing))
                }
                return item
            }
            let unitSize = layoutSize(
                main: g.estimatedGroup ? .estimated(g.unitExtent) : .absolute(g.unitExtent),
                cross: crossDimension(g.crossExtent))
            let unit: NSCollectionLayoutGroup
            if !supplementaries.isEmpty {
                unit =
                    vertical
                    ? .horizontal(layoutSize: unitSize, subitem: items[0], count: items.count)
                    : .vertical(layoutSize: unitSize, subitem: items[0], count: items.count)
            } else {
                unit =
                    vertical
                    ? .horizontal(layoutSize: unitSize, subitems: items)
                    : .vertical(layoutSize: unitSize, subitems: items)
            }
            if equalSpacing { unit.interItemSpacing = .fixed(g.tracks.count > 1 ? g.tracks[0].spacing : 0) }
            return unit
        }
        let unit = makeUnit(lineSupplementaries?.first ?? itemSupplementaries)
        let top: NSCollectionLayoutGroup
        if g.count == 1 && abs(g.groupExtent - g.unitExtent) < 0.001 {
            top = unit
        } else {
            let pageSize = layoutSize(
                main: g.estimatedGroup ? .estimated(g.groupExtent) : .absolute(g.groupExtent),
                cross: crossDimension(g.crossExtent))
            let contentExtent =
                g.unitExtent * CGFloat(g.count)
                + configuration.lineSpacing * CGFloat(g.count - 1)
            let remainder = g.groupExtent - contentExtent
            if !itemSupplementaries.isEmpty && lineSupplementaries == nil {
                // 每层中每种附属视图只声明一次，通过重复行组保留所属条目的索引路径。
                let contentSize = layoutSize(
                    main: g.estimatedGroup ? .estimated(contentExtent) : .absolute(contentExtent),
                    cross: crossDimension(g.crossExtent))
                let repeated: NSCollectionLayoutGroup =
                    vertical
                    ? .vertical(layoutSize: contentSize, subitem: unit, count: g.count)
                    : .horizontal(layoutSize: contentSize, subitem: unit, count: g.count)
                repeated.interItemSpacing = .fixed(configuration.lineSpacing)
                if remainder > 0.001 {
                    repeated.edgeSpacing = .init(
                        leading: nil, top: nil,
                        trailing: vertical ? nil : .fixed(remainder),
                        bottom: vertical ? .fixed(remainder) : nil)
                    top =
                        vertical
                        ? .vertical(layoutSize: pageSize, subitems: [repeated])
                        : .horizontal(layoutSize: pageSize, subitems: [repeated])
                } else {
                    top = repeated
                }
            } else {
                // 显式列出各行以保留行尺寸，并预留剩余空白，避免产生额外重复。
                let units = (0..<g.count).map { line in
                    lineSupplementaries.map { makeUnit($0[line]) }
                        ?? (unit.copy() as! NSCollectionLayoutGroup)
                }
                if remainder > 0.001 {
                    units.last?.edgeSpacing = .init(
                        leading: nil, top: nil,
                        trailing: vertical ? nil : .fixed(remainder),
                        bottom: vertical ? .fixed(remainder) : nil)
                }
                top =
                    vertical
                    ? .vertical(layoutSize: pageSize, subitems: units)
                    : .horizontal(layoutSize: pageSize, subitems: units)
                top.interItemSpacing = .fixed(configuration.lineSpacing)
            }
        }
        top.edgeSpacing = .init(
            leading: vertical ? .fixed(g.alignmentOffset) : nil,
            top: vertical ? nil : .fixed(g.alignmentOffset), trailing: nil, bottom: nil)
        let sectionGroup: NSCollectionLayoutGroup
        if let extent = g.fixedCrossExtent, extent > g.crossExtent + 0.001 {
            // 完整预留固定交叉轴外框，在内部保持轨道尺寸和逻辑对齐。
            top.edgeSpacing = .init(
                leading: vertical ? .fixed(g.alignmentOffset) : nil,
                top: vertical ? nil : .fixed(g.alignmentOffset),
                trailing: vertical ? .fixed(extent - g.crossExtent - g.alignmentOffset) : nil,
                bottom: vertical ? nil : .fixed(extent - g.crossExtent - g.alignmentOffset))
            let frameSize = layoutSize(
                main: g.estimatedGroup ? .estimated(g.groupExtent) : .absolute(g.groupExtent),
                cross: .absolute(extent))
            sectionGroup = vertical
                ? .vertical(layoutSize: frameSize, subitems: [top])
                : .horizontal(layoutSize: frameSize, subitems: [top])
        } else {
            sectionGroup = top
        }
        let section = NSCollectionLayoutSection(group: sectionGroup)
        section.interGroupSpacing = configuration.groupSpacing ?? configuration.lineSpacing
        section.contentInsets = configuration.sectionInsets.directionalEdgeInsets
        section.orthogonalScrollingBehavior = configuration.scrollingBehavior?.uiKitValue ?? .none
        return section
    }
    /// 自适应定义展开后的一条实际轨道。
    struct Track {
        /// 交叉轴尺寸，单位为点。
        let extent: CGFloat
        /// 与下一条实际轨道的间距；最后一条轨道为 0。
        var spacing: CGFloat
    }

    /// 将轨道定义解析为具有具体尺寸和间距的实际轨道。
    ///
    /// 先扣除定义间距和固定尺寸，再按顺序分配非固定定义，最后展开 adaptive。
    /// flexible 应用上下限后继续分配剩余空间，不回头重新均分已处理的定义。
    /// adaptive 在其分配区域内确定数量；达到 maximum 后不将空白重新分配给其他定义。
    ///
    /// - Parameters:
    ///   - definitions: 已验证的轨道定义数组。
    ///   - availableExtent: 已扣除 Section 交叉轴 inset 的容器有效尺寸，不应再次扣除安全区域。
    ///   - defaultSpacing: 轨道未显式指定间距时使用的值。
    /// - Returns: 按原顺序排列的实际轨道，最后一条轨道的尾部间距为 0。
    /// - Note: 这是本包确定的一轮分配规则，不是 SwiftUI 多轮测量算法的完整复刻。
    static func resolve(
        _ definitions: [ListGridTrack], availableExtent: CGFloat, defaultSpacing: CGFloat = 0
    ) -> [Track] {
        do { return try checkedResolve(definitions, availableExtent: availableExtent, defaultSpacing: defaultSpacing) }
        catch { preconditionFailure("ListKit: \(error)") }
    }

    /// 轨道或网格几何解析失败的错误，描述可直接用于验证结果与失败提示。
    struct ResolutionError: Error, CustomStringConvertible {
        /// 具体的配置约束或尺寸计算失败原因。
        let description: String
    }

    /// 按固定轨道优先、非固定定义顺序分配、自适应定义展开的步骤解析实际轨道。
    /// 调用方负责验证定义参数；此处继续检查分配过程中的溢出、数量与最终几何结果。
    static func checkedResolve(
        _ definitions: [ListGridTrack], availableExtent: CGFloat, defaultSpacing: CGFloat = 0
    ) throws -> [Track] {
        guard availableExtent.isFinite, !definitions.isEmpty, definitions.count <= 10000 else {
            throw ResolutionError(description: "grid requires finite extent and 1...10000 track definitions")
        }
        // 定义之间的间距先行扣除；最后一个定义无需尾部间距。
        let gaps = definitions.map { $0.spacingAfter ?? defaultSpacing }
        var remaining = availableExtent - gaps.dropLast().reduce(0, +)
        guard remaining.isFinite else {
            throw ResolutionError(description: "grid track spacing sum overflow")
        }
        var allocated = Array(repeating: CGFloat.zero, count: definitions.count)
        var flexibleCount = 0

        // 固定轨道先占用空间，其余定义共享待分配的剩余尺寸。
        for (index, definition) in definitions.enumerated() {
            if case .fixed(let extent) = definition.size {
                allocated[index] = extent
                remaining -= extent
            } else {
                flexibleCount += 1
            }
        }
        guard remaining.isFinite else {
            throw ResolutionError(description: "grid fixed track extent sum overflow")
        }
        for (index, definition) in definitions.enumerated() {
            switch definition.size {
            case .fixed: continue
            case .flexible(let minimum, let maximum):
                allocated[index] = min(maximum, max(minimum, remaining / CGFloat(flexibleCount)))
            case .adaptive:
                allocated[index] = max(1, remaining / CGFloat(flexibleCount))
            }
            remaining -= allocated[index]
            flexibleCount -= 1
        }

        // 自适应定义在自己的分配区域内展开为多条实际轨道，并计入内部间距。
        var tracks: [Track] = []
        for (index, definition) in definitions.enumerated() {
            let gap = gaps[index]
            if case .adaptive(let minimum, let maximum) = definition.size {
                let proposedCount = floor((allocated[index] + gap) / (minimum + gap))
                guard proposedCount.isFinite, proposedCount <= CGFloat(10000 - tracks.count) else {
                    throw ResolutionError(description: "grid track \(index) adaptive expansion exceeds 10000 total tracks or is nonfinite")
                }
                let count = max(1, Int(proposedCount))
                let extent = min(
                    maximum, max(1, (allocated[index] - CGFloat(count - 1) * gap) / CGFloat(count)))
                for _ in 0..<count {
                    tracks.append(Track(extent: extent, spacing: gap))
                }
            } else {
                tracks.append(Track(extent: allocated[index], spacing: gap))
            }
        }
        if !tracks.isEmpty { tracks[tracks.count - 1].spacing = 0 }
        guard tracks.count <= 10000,
            tracks.allSatisfy({ $0.extent.isFinite && $0.extent > 0 }),
            tracks.reduce(CGFloat.zero, { $0 + $1.extent + $1.spacing }).isFinite
        else { throw ResolutionError(description: "grid resolved track count or geometry is invalid") }
        return tracks
    }
}
