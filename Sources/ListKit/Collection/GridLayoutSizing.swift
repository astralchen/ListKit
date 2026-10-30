import UIKit

/// 网格条目沿内容方向的尺寸策略。
///
/// 纵向内容控制高度，横向内容控制宽度；交叉轴尺寸由 `ListGridTrack` 决定。
public struct ListGridItemMainAxisSize: Hashable, Sendable {
    enum Storage: Hashable, Sendable {
        case measured(ListGridMeasurement)
        case fractionalViewport(CGFloat)
        case fractionalGroup(CGFloat)
        case fillGroup
    }
    let storage: Storage
    private init(_ storage: Storage) { self.storage = storage }
    init(_ size: ListGridMeasurement) { storage = .measured(size) }
    /// 返回使用固定主轴尺寸的策略。
    ///
    /// - Parameter value: 尺寸，单位为点，必须为有限正数。
    /// - Returns: 不随内容测量变化的主轴尺寸策略。
    public static func fixed(_ value: CGFloat) -> Self { .init(ListGridMeasurement.fixed(value)) }
    /// 返回根据条目内容测量主轴尺寸的策略。
    ///
    /// 单元格与所属组均使用估算尺寸，单元格须提供自适应尺寸；同一行的条目不强制等高或等宽。
    ///
    /// - Parameter value: 初始估算尺寸，单位为点，必须为有限正数。
    /// - Returns: 随内容测量更新的主轴尺寸策略。
    public static func estimated(_ value: CGFloat) -> Self { .init(ListGridMeasurement.estimated(value)) }
    /// 返回根据轨道尺寸和宽高比计算主轴尺寸的策略。
    ///
    /// - Parameter value: 宽度除以高度的比例，必须为有限正数；横向与纵向内容使用相同定义。
    /// - Returns: 根据已解析的交叉轴尺寸计算主轴尺寸的策略。
    public static func aspectRatio(_ value: CGFloat) -> Self { .init(ListGridMeasurement.aspectRatio(value)) }
    /// 返回统一同一基本行或列中条目主轴尺寸的测量策略。
    ///
    /// 统一范围不跨基本行、列或顶层组，组本身仍使用估算尺寸。
    ///
    /// - Parameter value: 初始估算尺寸，单位为点，必须为有限正数。
    /// - Returns: 根据同级条目测量结果统一主轴尺寸的策略。
    @available(iOS 17.0, *)
    public static func uniform(estimated value: CGFloat) -> Self {
        .init(ListGridMeasurement.uniform(estimated: value))
    }
    /// 返回相对于局部内容视口主轴长度的尺寸策略。
    ///
    /// - Parameter value: 相对于容器扣除分区内边距后的主轴长度的比例，须为有限正数。
    /// - Returns: 根据当前布局环境计算条目主轴尺寸的策略。
    public static func fractionalViewport(_ value: CGFloat) -> Self { .init(.fractionalViewport(value)) }
    /// 返回相对于显式组主轴长度的尺寸策略。
    ///
    /// - Parameter value: 相对于组主轴长度的比例，须为有限正数，不预先扣除组内间距。
    /// - Returns: 根据显式组尺寸计算条目主轴尺寸的策略；未提供组尺寸或内容溢出时诊断失败。
    public static func fractionalGroup(_ value: CGFloat) -> Self { .init(.fractionalGroup(value)) }
    /// 必须同时指定 group 的 lines 与 mainAxisSize；扣除 lineSpacing 后等分。
    public static var fillGroup: Self { .init(.fillGroup) }
    var isValid: Bool {
        switch storage {
        case .measured(let size): size.isValid
        case .fractionalViewport(let value), .fractionalGroup(let value): value.isFinite && value > 0
        case .fillGroup: true
        }
    }
    var isSelfSizing: Bool {
        if case .measured(let size) = storage { return size.isSelfSizing }
        return false
    }
}

/// 顶层组沿内容方向的尺寸规则。
///
/// 分组时省略 `mainAxisSize`，组尺寸由内容推导。
public enum ListGridGroupMainAxisSize: Hashable, Sendable {
    /// 组的固定主轴尺寸，单位为点，必须为有限正数。
    case fixed(CGFloat)
    /// 组的主轴尺寸相对于局部视口的比例，必须为有限正数。
    ///
    /// 局部视口使用容器沿内容方向扣除分区内边距后的尺寸。
    case fractionalViewport(CGFloat)
    var isValid: Bool {
        switch self {
        case .fixed(let value), .fractionalViewport(let value): value.isFinite && value > 0
        }
    }
    func extent(viewport: CGFloat) -> CGFloat {
        switch self {
        case .fixed(let value): value
        case .fractionalViewport(let value): viewport * value
        }
    }
}

/// 网格基本行或列组成顶层组的策略。
///
/// 行数统计基本行或列的数量；自动容纳策略根据指定主轴尺寸计算容量，并保留尾部空白。
/// 估算或统一测量的多行附属视图要求轨道同构；类型化内容自动映射地址，
/// 自定义附属视图提供者须使用接收实际元素种类和索引路径的初始化方法。
public enum ListGridLineGrouping: Hashable, Sendable {
    /// 使用指定行数组成一个顶层组。
    ///
    /// `lines` 的有效范围为 1...10000；`mainAxisSize` 为 `nil` 时，组尺寸由行尺寸与行间距决定。
    /// 使用估算或同级统一尺寸的条目时，必须省略显式组尺寸。
    case count(lines: Int, mainAxisSize: ListGridGroupMainAxisSize? = nil)
    /// 在指定组尺寸内放入尽可能多的完整行，并保留尾部剩余空间。
    ///
    /// 要求条目尺寸可确定，不能使用估算或同级统一尺寸；组必须至少容纳一行。
    case fitting(mainAxisSize: ListGridGroupMainAxisSize)
}

/// 轨道组在交叉轴剩余空间中的对齐方式。
public enum ListGridTrackGroupAlignment: Hashable, Sendable {
    /// 起始侧、居中与结束侧；纵向内容使用逻辑起止方向，横向内容使用上下方向。
    case start, center, end
    var fraction: CGFloat { self == .start ? 0 : self == .center ? 0.5 : 1 }
}

/// 网格主体的交叉轴尺寸，不包含 Section inset 或 boundary 占位。
/// 内容纵向时为宽度，横向时为高度；不改变主轴 viewport。
public enum ListGridCrossAxisSize: Hashable, Sendable {
    /// 固定的网格交叉轴占位尺寸，单位为点，必须为有限正数。
    ///
    /// 轨道和间距不得超过该尺寸；剩余空间按轨道组对齐方式分配。
    case fixed(CGFloat)
    /// 仅支持 tracks: 1，且 item 不能使用 aspectRatio；需 cell 实现 self-sizing。
    case estimated(CGFloat)
}

extension ListSectionGridLayout {
    /// 设置整个轨道区域的交叉轴尺寸；nil 恢复环境提供的可用尺寸。
    /// fixed 完整预留区域，剩余空间由 trackGroupAlignment 分配；轨道溢出时诊断。
    /// estimated 同时设置 item/group 的交叉轴估算值，仅支持单轨道与独立主轴尺寸。
    ///
    /// - Parameter value: 网格主体的交叉轴尺寸；`nil` 恢复使用容器可用尺寸。
    /// - Returns: 应用交叉轴尺寸后的布局副本。
    public func gridCrossAxisSize(_ value: ListGridCrossAxisSize?) -> Self {
        var copy = self
        copy.crossAxisSizing = value
        return copy
    }
    /// 设置当前 Section 的正交滚动。非 nil 时内容轴与外层轴垂直，tracks、itemMainAxisSize、gridCrossAxisSize 随之解释。
    /// nil 关闭正交滚动并恢复跟随外层方向；不主动改写尺寸策略或分组配置。
    /// 估算主轴 group 的原生吸附可能仍按初始估算长度定位；动态内容建议 continuous，精确分页使用确定尺寸。
    ///
    /// - Parameter behavior: 分区的独立滚动行为；`nil` 关闭正交滚动。
    /// - Returns: 应用滚动行为后的布局副本。
    public func orthogonalScrolling(_ behavior: ListOrthogonalScrollingBehavior?) -> Self {
        var copy = self
        copy.scrollingBehavior = behavior
        return copy
    }
    /// 按基本行／列组合顶层 group；默认 count(lines: 1)。纵向内容的一行、横向内容的一列为一个 line。
    /// 分组不自动开启分页；分页行为由 orthogonalScrolling 决定。
    ///
    /// - Parameter grouping: 顶层组的行数及主轴尺寸策略。
    /// - Returns: 应用分组策略后的布局副本。
    public func lineGrouping(_ grouping: ListGridLineGrouping) -> Self {
        var copy = self
        copy.grouping = grouping
        return copy
    }
    /// 轨道之间的默认交叉轴间距，默认 0；单条 ListGridTrack.spacingAfter 可覆盖它。
    ///
    /// - Parameter value: 间距，单位为点，必须为有限非负数。
    /// - Returns: 应用轨道间距后的布局副本。
    public func trackSpacing(_ value: CGFloat) -> Self {
        var copy = self
        copy.trackSpacing = value
        return copy
    }
    /// 内容方向上相邻行／列的统一间距，默认 0；未设置 groupSpacing 时也用于组间。
    /// 不修改显式的 groupSpacing 覆盖，与它的调用顺序无关。
    ///
    /// - Parameter value: 相邻基本行或列之间的间距，单位为点，必须为有限非负数。
    /// - Returns: 应用行间距后的布局副本。
    public func lineSpacing(_ value: CGFloat) -> Self {
        var copy = self
        copy.lineSpacing = value
        return copy
    }
    /// 覆盖顶层 group 之间的间距；默认 nil，使用当前 lineSpacing。
    /// nil 清除覆盖并恢复跟随 lineSpacing；0 表示明确无组间距。
    ///
    /// - Parameter value: 顶层组间距，单位为点；非空时必须为有限非负数。
    /// - Returns: 应用组间距覆盖后的布局副本。
    public func groupSpacing(_ value: CGFloat?) -> Self {
        var copy = self
        copy.groupSpacing = value
        return copy
    }
    /// 整组轨道在剩余交叉轴空间中的对齐，默认 start；不控制 cell 内容或分页停靠。
    ///
    /// - Parameter value: 轨道整体的交叉轴对齐方式。
    /// - Returns: 应用对齐方式后的布局副本。
    public func trackGroupAlignment(_ value: ListGridTrackGroupAlignment) -> Self {
        var copy = self
        copy.crossAlignment = value
        return copy
    }
}
