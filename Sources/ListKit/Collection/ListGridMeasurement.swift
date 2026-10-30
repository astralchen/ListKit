// Adapted from UIKitGridLayouts 89aa339cc5651147c3c6265c0c931dd701bb45a7.
// Copyright (c) 2026 Sondra. MIT license: ThirdPartyNotices/UIKitGridLayouts-LICENSE.txt.
import UIKit

/// 内部共享的主轴测量实现；公开 item 与 boundary 类型分别限制可用策略。
struct ListGridMeasurement: Hashable, Sendable {
    private enum Storage: Hashable, Sendable {
        case fixed(CGFloat)
        case estimated(CGFloat)
        case uniform(CGFloat)
        case aspectRatio(CGFloat)
    }

    private let storage: Storage
    private init(_ storage: Storage) { self.storage = storage }

    /// 固定的主轴尺寸，单位为点。
    static func fixed(_ size: CGFloat) -> Self { Self(.fixed(size)) }

    /// 主轴的初始估计尺寸，实际尺寸由视图的 Auto Layout 或 preferred fitting attributes 决定。
    /// 用于网格 item 时，cell 与 group 同时启用 estimated；同组 cell 不强制拉伸为相同尺寸。
    /// 用于边界补充视图时，只设置该视图的主轴估算尺寸。
    static func estimated(_ size: CGFloat) -> Self { Self(.estimated(size)) }

    /// 先测量内容，再让纵向网格同一行等高，或横向网格同一列等宽。
    /// 只统一同一基本行／列的 cell，不跨 line 统一；group 自身仍使用 estimated。
    /// 此策略需要测量同组所有 cell，适合每组项目数量较少的网格。
    @available(iOS 17.0, *)
    static func uniform(estimated size: CGFloat) -> Self { Self(.uniform(size)) }

    /// 宽 ÷ 高。例如 1 为正方形，16.0 / 9 为宽屏比例，两个滚动方向含义相同。
    /// 网格按每条轨道分别计算 item 尺寸，group 取其中最大的主轴尺寸，较小 item 不会被强制拉伸。
    static func aspectRatio(_ ratio: CGFloat) -> Self { Self(.aspectRatio(ratio)) }

    /// 尺寸参数是否为有限正数，不包含依赖环境的计算结果验证。
    var isValid: Bool {
        switch storage {
        case .fixed(let value), .estimated(let value), .uniform(let value), .aspectRatio(let value):
            value.isFinite && value > 0
        }
    }

    /// 返回主轴长度或初始估算值；计算结果无效时触发前置条件失败。
    func resolvedExtent(crossExtent: CGFloat, isVertical: Bool) -> CGFloat {
        let extent = checkedExtent(crossExtent: crossExtent, isVertical: isVertical)
        precondition(extent != nil, "ListKit: resolved grid size must be finite and positive")
        return extent!
    }

    /// 在创建 UIKit dimension 前检查实际计算结果，包括比例运算的溢出与下溢。
    func checkedExtent(crossExtent: CGFloat, isVertical: Bool) -> CGFloat? {
        let extent: CGFloat
        switch storage {
        case .fixed(let size), .estimated(let size), .uniform(let size): extent = size
        case .aspectRatio(let ratio): extent = isVertical ? crossExtent / ratio : crossExtent * ratio
        }
        return extent.isFinite && extent > 0 ? extent : nil
    }

    /// 当前策略是否需要已确定的交叉轴长度来计算宽高比。
    var requiresResolvedCrossExtent: Bool {
        if case .aspectRatio = storage { return true }
        return false
    }

    /// 当前策略是否依赖视图测量来确定最终尺寸。
    var isSelfSizing: Bool {
        switch storage {
        case .estimated, .uniform: true
        case .fixed, .aspectRatio: false
        }
    }

    /// 创建与测量策略对应的 UIKit 尺寸。
    ///
    /// 禁用同级统一尺寸时，统一测量策略退回普通估算尺寸。
    @MainActor
    func dimension(crossExtent: CGFloat, isVertical: Bool, uniformSiblings: Bool = true)
    -> NSCollectionLayoutDimension
    {
        let extent = resolvedExtent(crossExtent: crossExtent, isVertical: isVertical)
        if #available(iOS 17.0, *), case .uniform = storage, uniformSiblings {
            return .uniformAcrossSiblings(estimate: extent)
        }
        if isSelfSizing { return .estimated(extent) }
        return .absolute(extent)
    }
}
