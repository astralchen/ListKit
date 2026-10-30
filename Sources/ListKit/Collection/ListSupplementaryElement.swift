import UIKit

/// 业务 kind/item 位置对应的实际 UIKit supplementary 地址。
/// 将两项一起用于 UIKit 查询；不得把业务 item indexPath 与这里的 elementKind 混用。
public struct ListSupplementaryElement: Hashable, Sendable {
    /// 查询或出队附属视图时使用的实际 UIKit 元素种类。
    ///
    /// 此值可能与业务声明中的 `kind` 不同，应与同一实例的 `indexPath` 配对使用。
    public let elementKind: String
    /// 实际 UIKit 元素种类下的附属视图索引路径。
    ///
    /// 此地址可能不同于所属条目的业务索引路径。
    public let indexPath: IndexPath
}

/// 同构轨道的每条基本 line 使用一个 kind；UIKit 按 kind 独立编号 supplementary。
struct ListSupplementaryAliasKey: Hashable {
    let sectionID: AnyListID
    let kind: String
    let presentationID: ObjectIdentifier
    let line: Int
    let lines: Int
    let tracks: Int

    /// 将某一行别名下独立编号的附属视图位置转换为所属业务条目位置。
    func itemIndexPath(for supplementary: IndexPath) -> IndexPath {
        .init(
            item: (supplementary.item / tracks) * (lines * tracks)
                + line * tracks + supplementary.item % tracks, section: supplementary.section)
    }
    /// 将业务条目位置转换为当前行别名下的 UIKit 地址；条目属于其他行时返回 `nil`。
    func supplementaryIndexPath(for item: IndexPath) -> IndexPath? {
        guard (item.item / tracks) % lines == line else { return nil }
        return .init(
            item: (item.item / (lines * tracks)) * tracks + item.item % tracks,
            section: item.section)
    }
}
