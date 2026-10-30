import ListKit
import UIKit

/// 布局、内容注册和代码展示共用的关联标识。
enum LayoutLabElementKind {
    static let title = "lab.title"
    static let summary = "lab.summary"
    static let badge = "lab.badge"
    static let card = "section-decoration"
}

/// 预览和代码展示共享的输入；不持有 UIKit 视图或可变 layout 对象。
struct LayoutLabConfiguration: Hashable {
    enum Scene: String, CaseIterable {
        case normal = "Normal", cards = "Cards", tags = "Tags", banner = "Banner", badges = "Measured badges"
        case centered = "Centered", page = "2×3", mixedSections = "Mixed sections", nativeList = "Native list"
        var title: String {
            switch self {
            case .normal: "轨道与主轴尺寸"
            case .cards: "逐组停靠卡片"
            case .tags: "内容自适应标签"
            case .badges: "自适应多行／列徽标"
            case .banner: "整页 Banner"
            case .centered: "居中分页"
            case .page: "两轨道 × 三行／列"
            case .mixedSections: "不同方向的多 Section"
            case .nativeList: "UIKit 原生列表"
            }
        }
    }
    enum TrackMode: String, CaseIterable {
        case list = "List", equal = "3 columns", fixed = "Fixed", adaptive = "Adaptive", mixed = "Mixed"
    }
    enum Sizing: String, CaseIterable {
        case estimated = "自适应", fixed = "固定 56", ratio = "宽高比 1", uniform = "同组统一"
        static var available: [Self] {
            if #available(iOS 17.0, *) { return allCases }
            return allCases.filter { $0 != .uniform }
        }
    }
    var scene = Scene.normal
    var trackMode = TrackMode.adaptive
    var sizing = Sizing.fixed
    var horizontal = false
    var narrow = false
    var count = 17
    var alignment = ListGridTrackGroupAlignment.start
    var trackSpacing: CGFloat = 10
    var lineSpacing: CGFloat = 10
    var groupSpacing: CGFloat? = nil
    var lines = 1
    var pinHeaders = true
    var limitMaximum = false
    var expanded = false

    var outerAxis: ListLayoutScrollDirection { horizontal ? .horizontal : .vertical }
    var titleExtent: Int { horizontal ? 100 : 44 }
    var summaryExtent: Int { horizontal ? 100 : 36 }
    var sectionCount: Int { scene == .mixedSections ? 3 : 1 }
    var editsGrid: Bool { scene == .normal || scene == .mixedSections }
    var axisDescription: String {
        "外层\(horizontal ? "横向" : "纵向") · 主 Section 内容\(recipe(section: 0).orthogonal == nil ? (horizontal ? "横向" : "纵向") : (horizontal ? "纵向" : "横向"))"
    }
    mutating func cycleCount() { count = count == 17 ? 1 : count == 1 ? 0 : 17 }

    var explanation: String {
        switch scene {
        case .normal, .mixedSections:
            let unit = horizontal ? "行高" : "列宽"
            let track: String
            switch trackMode {
            case .list: track = "单轨道占满可用\(unit)"
            case .equal: track = "3 条弹性轨道平分可用空间"
            case .fixed: track = "3 条固定轨道，每条 60 pt"
            case .adaptive: track = "以 90 pt 计算自适应轨道数量"
            case .mixed: track = "固定 60 + 弹性 50…100 + 自适应 50"
            }
            return "\(track)。\(sizing == .estimated ? "默认 estimated(44)，最终尺寸由文字测量。" : sizing.rawValue + " 主轴尺寸。")"
        case .cards: return "固定 92 pt，按 viewport 计算每组容量；停靠在 group 起始边缘。"
        case .tags: return "默认 estimated(44)，根据文字测量内容主轴；增加内容可观察尺寸变化。"
        case .badges: return "每组 3 行／列，内容自适应并带独立徽标；点击徽标可核对所属 item。"
        case .banner: return "单 item 填满一个 viewport group，按整页滚动。"
        case .centered: return "group 占 viewport 的 84%，滚动后居中停靠。"
        case .page: return "每组最多 6 项，fillGroup 扣除组内间距后等分；尾组保留空位。"
        case .nativeList: return "由 UIKit List 生成布局。支持默认 cell 自适应；此场景不添加网格边界或背景。"
        }
    }

    func recipe(section: Int) -> LayoutLabGridRecipe {
        if section == 1 {
            return .init(trackCount: 2, size: .fixed(72), trackSpacing: 10, lineSpacing: 10)
        }
        if section == 2 || scene == .page {
            return .init(trackCount: 2, size: .fillGroup, crossExtent: 220,
                         trackSpacing: 10, lineSpacing: 10, groupSpacing: 16,
                         grouping: .count(lines: 3, mainAxisSize: .fractionalViewport(1)), orthogonal: .groupPaging)
        }
        if scene == .normal || scene == .mixedSections || scene == .nativeList {
            let maximum: CGFloat = limitMaximum ? 112 : .infinity
            let tracks: [ListGridTrack]
            switch trackMode {
            case .list: tracks = [.init(.flexible(minimum: 1))]
            case .equal: tracks = Array(repeating: .init(.flexible(minimum: 1, maximum: maximum)), count: 3)
            case .fixed: tracks = Array(repeating: .init(.fixed(60)), count: 3)
            case .adaptive: tracks = [.init(.adaptive(minimumForCount: 90, maximum: maximum))]
            case .mixed: tracks = [.init(.fixed(60), spacingAfter: 6), .init(.flexible(minimum: 50, maximum: 100)),
                                  .init(.adaptive(minimumForCount: 50, maximum: maximum))]
            }
            let size: LayoutLabGridRecipe.Size
            switch sizing {
            case .estimated: size = .estimated
            case .fixed: size = .fixed(56)
            case .ratio: size = .ratio(1)
            case .uniform: size = .uniform
            }
            return .init(tracks: tracks, size: size, trackSpacing: trackSpacing,
                         lineSpacing: lineSpacing, groupSpacing: groupSpacing,
                         grouping: .count(lines: lines), alignment: alignment)
        }
        switch scene {
        case .badges: return .init(trackCount: 2, size: .estimated, crossExtent: 210,
                                  trackSpacing: 10, lineSpacing: 12, groupSpacing: 20,
                                  grouping: .count(lines: 3), orthogonal: .continuous)
        case .tags: return .init(size: .estimated, crossExtent: 112, orthogonal: .continuous)
        case .banner: return .init(size: .fillGroup, crossExtent: 112,
                                  grouping: .count(lines: 1, mainAxisSize: .fractionalViewport(1)), orthogonal: .paging)
        case .centered: return .init(size: .viewport(0.84), crossExtent: 112, groupSpacing: 12, orthogonal: .groupPagingCentered)
        default: return .init(size: .fixed(92), crossExtent: 112,
                              grouping: .fitting(mainAxisSize: .fractionalViewport(1)), orthogonal: .continuousGroupLeadingBoundary)
        }
    }

    func item(index: Int, section: Int) -> LayoutLabItem {
        let recipe = recipe(section: section)
        let axis = recipe.orthogonal == nil ? outerAxis : (horizontal ? .vertical : .horizontal)
        let measured = recipe.size.measuresContent || scene == .nativeList
        let samples = ["短文本", "按内容测量尺寸", "文字更长时，纵向换行增加高度，横向增加宽度。", "同一行／列之后继续排列内容。"]
        let text = scene == .badges ? ["短", "标签", "较长内容", "徽标", "宽度变化", "项目"][index % 6] : scene == .tags ? String(repeating: "Tag ", count: index % 4 + 1)
            : measured ? samples[index % samples.count] : "\(index + 1)"
        return .init(index: index, text: (section > 0 ? "S\(section) · " : "") + text
                     + (expanded ? " 增加内容后会重新测量单元格。较长的文字在纵向布局中换行，在横向布局中扩展宽度。" : ""), sizingAxis: measured ? axis : nil)
    }

    var code: String {
        let axis = horizontal ? ".horizontal" : ".vertical"
        var text = """
        let layout = adapter.makeCompositionalLayout(
            configuration: .init(scrollDirection: \(axis))
        )
        collectionView.collectionViewLayout = layout

        // 预览容器：\(narrow ? (horizontal ? "高度 240 pt" : "宽度 240 pt") : "填充可用安全区域")，由宿主 Auto Layout 约束。
        // item 默认 estimated(44)，trackSpacing / lineSpacing 默认 0，groupSpacing 默认 nil 跟随 lineSpacing。
        // cell 需实现 self-sizing；预览中的数字是实际 bounds 尺寸。
        // Row 内容变化使用 refreshID，并声明 .reconfigure(layout: .invalidate)。
        adapter.apply(transaction: .disabled) {
        """
        for section in 0..<sectionCount {
            let layoutCode = scene == .nativeList ? "UIKitListLayout(appearance: .insetGrouped)" : recipe(section: section).code
            text += "\n    ListSection(\(section)) {\n        // \(count) 个 Row，内容\(expanded ? "已增加" : "未增加")。\n    }\n    .layout {\n"
            text += layoutCode.split(separator: "\n", omittingEmptySubsequences: false).map { "        " + $0 }.joined(separator: "\n")
            if scene == .badges {
                text += """

                        .itemSupplementaries {
                            ItemSupplementaryLayout(kind: "lab.badge",
                                size: .init(width: .absolute(24), height: .absolute(24)), itemAnchor: .topTrailing)
                                .zIndex(2)
                        }
                """
            }
            if scene != .nativeList {
                if section == 0 {
                    text += """

                            .boundarySupplementaries {
                                BoundarySupplementaryLayout(kind: "\(LayoutLabElementKind.title)",
                                    mainAxisSize: .fixed(\(titleExtent)), sizingAxis: \(axis),
                                    alignment: \(horizontal ? ".leading" : ".top"))
                                    .pinToVisibleBounds(\(pinHeaders))
                                BoundarySupplementaryLayout(kind: "\(LayoutLabElementKind.summary)",
                                    mainAxisSize: .fixed(\(summaryExtent)), sizingAxis: \(axis),
                                    alignment: \(horizontal ? ".trailing" : ".bottom"))
                            }
                    """
                }
                text += "\n            .decorationItems { DecorationItemLayout(kind: \"\(LayoutLabElementKind.card)\") }"
            }
            text += "\n    }"
            if section == 0 && scene != .nativeList {
                let badgeContent = scene == .badges ? """

                        SectionSupplementary(LayoutLabBadge.self, kind: "lab.badge", id: "badge") { view, context in
                            view.configure(item: context.indexPath.item)
                        }
                """ : ""
                text += """

                    .supplementaries {
                        SectionSupplementary(LayoutLabHeader.self, kind: "\(LayoutLabElementKind.title)", id: "title") { view, _ in
                            view.configure(text: "lab.title · \(count)", identifier: "lab-title")
                        }
                        .refreshID(\(count))
                        SectionSupplementary(LayoutLabHeader.self, kind: "\(LayoutLabElementKind.summary)", id: "footer") { view, _ in
                            view.configure(text: "lab.summary", identifier: "lab-summary")
                        }\(badgeContent)
                    }
                """
            }
            if scene != .nativeList {
                text += "\n    .decorations {\n        SectionDecoration(LayoutLabBackground.self, kind: \"\(LayoutLabElementKind.card)\")\n    }"
            }
            text += "\n"
        }
        return text + "}"
    }
}

struct LayoutLabItem: Hashable, Sendable {
    let index: Int
    let text: String
    let sizingAxis: ListLayoutScrollDirection?
}

/// 一份解析后的配置同时生成真实 Grid 和可读代码，避免另写一套展示用 preset。
struct LayoutLabGridRecipe {
    enum Size {
        case estimated, fixed(CGFloat), ratio(CGFloat), uniform, fillGroup, viewport(CGFloat)
        var measuresContent: Bool { if case .estimated = self { return true }; if case .uniform = self { return true }; return false }
        var value: ListGridItemMainAxisSize {
            switch self {
            case .estimated: .estimated(44)
            case .fixed(let n): .fixed(n)
            case .ratio(let n): .aspectRatio(n)
            case .uniform:
                if #available(iOS 17.0, *) { .uniform(estimated: 44) } else { .estimated(44) }
            case .fillGroup: .fillGroup
            case .viewport(let n): .fractionalViewport(n)
            }
        }
        var code: String {
            switch self {
            case .estimated: ".estimated(44)"
            case .fixed(let n): ".fixed(\(number(n)))"
            case .ratio(let n): ".aspectRatio(\(number(n)))"
            case .uniform:
                if #available(iOS 17.0, *) { ".uniform(estimated: 44)" } else { ".estimated(44)" }
            case .fillGroup: ".fillGroup"
            case .viewport(let n): ".fractionalViewport(\(number(n)))"
            }
        }
    }
    var trackCount = 1
    var tracks: [ListGridTrack]? = nil
    var size: Size = .estimated
    var crossExtent: CGFloat? = nil
    var trackSpacing: CGFloat = 10
    var lineSpacing: CGFloat = 10
    var groupSpacing: CGFloat? = nil
    var grouping = ListGridLineGrouping.count(lines: 1)
    var orthogonal: ListOrthogonalScrollingBehavior? = nil
    var alignment = ListGridTrackGroupAlignment.start

    func makeGrid() -> ListSectionGridLayout {
        let grid = tracks.map { GridLayout(tracks: $0) } ?? GridLayout(tracks: trackCount)
        return grid
            .itemMainAxisSize(size.value)
            .gridCrossAxisSize(crossExtent.map { .fixed($0) })
            .trackSpacing(trackSpacing)
            .lineSpacing(lineSpacing)
            .groupSpacing(groupSpacing)
            .lineGrouping(grouping)
            .trackGroupAlignment(alignment)
            .sectionInsets(.init(12))
            .orthogonalScrolling(orthogonal)
    }
    var code: String {
        let trackCode = tracks.map { "[\n" + $0.map { "    " + Self.trackCode($0) }.joined(separator: ",\n") + "\n]" } ?? "\(trackCount)"
        var result = "GridLayout(tracks: \(trackCode))\n    .itemMainAxisSize(\(size.code))"
        if let crossExtent { result += "\n    .gridCrossAxisSize(.fixed(\(number(crossExtent))))" }
        result += "\n    .trackSpacing(\(number(trackSpacing)))\n    .lineSpacing(\(number(lineSpacing)))"
        if let groupSpacing { result += "\n    .groupSpacing(\(number(groupSpacing)))" }
        let groupingCode: String
        switch grouping {
        case .count(let lines, let size): groupingCode = ".count(lines: \(lines)" + (size.map { ", mainAxisSize: \(Self.groupSizeCode($0))" } ?? "") + ")"
        case .fitting(let size): groupingCode = ".fitting(mainAxisSize: \(Self.groupSizeCode(size)))"
        }
        result += "\n    .lineGrouping(\(groupingCode))\n    .trackGroupAlignment(.\(alignment))\n    .sectionInsets(.init(12))"
        if let orthogonal { result += "\n    .orthogonalScrolling(.\(orthogonal))" }
        return result
    }
    private static func groupSizeCode(_ value: ListGridGroupMainAxisSize) -> String {
        switch value { case .fixed(let n): ".fixed(\(number(n)))"; case .fractionalViewport(let n): ".fractionalViewport(\(number(n)))" }
    }
    private static func trackCode(_ track: ListGridTrack) -> String {
        let size: String
        switch track.size {
        case .fixed(let n): size = ".fixed(\(number(n)))"
        case .flexible(let minimum, let maximum): size = ".flexible(minimum: \(number(minimum)), maximum: \(number(maximum)))"
        case .adaptive(let minimum, let maximum): size = ".adaptive(minimumForCount: \(number(minimum)), maximum: \(number(maximum)))"
        }
        return "ListGridTrack(\(size)" + (track.spacingAfter.map { ", spacingAfter: \(number($0))" } ?? "") + ")"
    }
}

private func number(_ value: CGFloat) -> String {
    value.isInfinite ? ".infinity" : value == value.rounded() ? String(Int(value)) : String(Double(value))
}
