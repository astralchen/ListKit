// Adapted from UIKitGridLayouts 89aa339cc5651147c3c6265c0c931dd701bb45a7.
// Copyright (c) 2026 Sondra. MIT license: ThirdPartyNotices/UIKitGridLayouts-LICENSE.txt.
import UIKit

/// 描述网格在交叉轴上的尺寸规则及相邻轨道间距。
///
/// 将此类型用于 GridLayout(tracks:) 的轨道定义。交叉轴是与内容方向垂直的轴：
/// 纵向网格使用列宽，横向网格使用行高。
///
/// 一个自适应定义可以展开为多列或多行，因此定义数量不一定等于实际轨道数量。
public struct ListGridTrack: Hashable, Sendable {
    /// 指定一个或多个行、列在交叉轴上的尺寸分配方式。
    ///
    /// 布局优先预留固定尺寸和间距，再按定义顺序分配剩余空间，最后展开自适应轨道。
    /// 此规则借鉴 SwiftUI 的 GridItem，但不复刻其提议尺寸与多轮测量行为。
    public enum Size: Hashable, Sendable {
        /// 创建一条具有指定尺寸的轨道。
        ///
        /// 即使容器空间不足，轨道仍保持指定尺寸，因此可能超出容器边界。
        /// 关联值的单位为点，且必须是有限正数。
        case fixed(CGFloat)

        /// 创建一条在指定上下限之间分配尺寸的弹性轨道。
        ///
        /// 提议尺寸为当前剩余空间除以尚未分配的非固定定义数量，然后限制到指定范围。
        /// 空间不足时仍保留最小尺寸；达到最大尺寸后，剩余空间继续分配给后续定义。
        /// 已处理的轨道不会再次分配，因此混合定义的顺序会影响最终尺寸。
        ///
        /// - Parameters:
        ///   - minimum: 最小尺寸，单位为点。必须是有限正数，默认值为 10。
        ///   - maximum: 最大尺寸，单位为点。不得小于 minimum，默认值为正无穷大。
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)

        /// 在分得的区域内创建一条或多条自适应轨道。
        ///
        /// 布局根据 minimumForCount 和轨道间距计算能容纳的数量，再均分该区域并对每条轨道
        /// 应用 maximum。达到最大尺寸后可能留下未使用空间，不会将该余量重新分配给其他定义。
        ///
        /// minimumForCount 用于决定展开数量，不是空间不足时的硬性下限。
        /// 此时单条轨道可以小于 minimumForCount。分配区域与应用 maximum 前的轨道尺寸均至少取 1 点；
        /// 若 maximum 本身小于 1 点，最终轨道仍按 maximum 限制。
        ///
        /// - Parameters:
        ///   - minimumForCount: 计算展开数量时使用的最小尺寸，单位为点。必须是有限正数。
        ///   - maximum: 每条展开轨道的最大尺寸，单位为点。不得小于 minimumForCount，
        ///     默认值为正无穷大。
        case adaptive(minimumForCount: CGFloat, maximum: CGFloat = .infinity)
    }

    /// 此行或列使用的尺寸分配规则。
    public var size: Size
    /// 此轨道与下一条轨道之间的交叉轴间距，单位为点。
    ///
    /// nil 继承 GridLayout.trackSpacing，默认 0。自适应定义展开出的轨道之间也使用此间距，
    /// 最后一条实际轨道之后不添加间距。此属性不控制滚动方向上的行间距或列间距。
    public var spacingAfter: CGFloat?

    /// 使用指定的尺寸规则和间距创建网格轨道定义。
    ///
    /// - Parameters:
    ///   - size: 行或列的尺寸规则，默认值为 flexible(minimum: 10, maximum: .infinity)。
    ///   - spacingAfter: 与下一条轨道的间距，单位为点。必须是有限非负数；nil 继承 GridLayout.trackSpacing。
    /// - Important: adapter 在 apply/环境解析时诊断参数；内部几何生成器同时保留前置条件。
    public init(_ size: Size = .flexible(), spacingAfter: CGFloat? = nil) {
        self.size = size
        self.spacingAfter = spacingAfter
    }
}
