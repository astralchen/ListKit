import UIKit

// MARK: - Identity

/// 保留原始值与类型身份的类型擦除标识符。
///
/// - Important: `Int(1)` 和 `String("1")` 不会被误判成同一个 ID。
/// - Note: `Sendable` 不变量由 initializer 保证，只有 `Hashable & Sendable` 的原始 id 能进入。
public struct AnyListID: Hashable, CustomStringConvertible, @unchecked Sendable {
    private let value: AnyHashable
    private let valueType: ObjectIdentifier
    private let valueDescription: String

    /// 类型擦除任意数据 id。
    ///
    /// - Parameter id: 任意遵守 `Hashable & Sendable` 的数据 id。
    public init<ID>(_ id: ID) where ID: Hashable & Sendable {
        self.value = AnyHashable(id)
        self.valueType = ObjectIdentifier(ID.self)
        self.valueDescription = String(describing: id)
    }

    /// 尝试将保存的标识符值转换为指定类型。
    ///
    /// - Parameter type: 要恢复的 id 类型。
    /// - Returns: Swift 条件类型转换成功时返回转换后的值，否则返回 `nil`。
    /// 此转换不使用身份相等性比较所保存的原始类型标识。
    public func typed<ID>(_ type: ID.Type = ID.self) -> ID? where ID: Hashable & Sendable {
        value.base as? ID
    }

    /// 同时包含原始值描述和类型标识的调试字符串。
    public var description: String {
        "\(valueDescription) <\(valueType)>"
    }

    /// 比较原始值和原始类型；不同类型的相同文本值不会相等。
    public static func == (lhs: AnyListID, rhs: AnyListID) -> Bool {
        lhs.valueType == rhs.valueType && lhs.value == rhs.value
    }

    /// 将原始类型和值共同写入哈希器。
    public func hash(into hasher: inout Hasher) {
        hasher.combine(valueType)
        hasher.combine(value)
    }
}

/// `Row(model:cell:)` 在 `ForEach(id:)` 内使用时的占位 ID 类型。
///
/// - Note: 开发者通常不会直接接触这个类型。它的存在是为了让 Swift 能推断出：
/// Row 的稳定身份来自外层 `ForEach`，无需在 Row 中重复传入。
public struct InheritedRowID: Hashable, Sendable {
    private init() {}
}

/// 用于差异更新的列表展示节点身份。
///
/// - Note: `refreshID` 不放进 identity，原因是：数据变了通常只需要刷新同一个展示节点；
/// 分区标识符、条目标识符、视图类型或展示变体变化时，会形成新的展示身份并参与插入与删除。
public struct AnyListIdentity: Hashable, Sendable {
    /// identity 所属的 Section ID。
    public let sectionID: AnyListID
    /// Row 或 supplementary 的稳定数据 ID。
    public let rowID: AnyListID
    /// Cell 或 reusable view 类型形成的展示身份。
    public let presentationID: ObjectIdentifier
    /// 同一数据 ID 的可选展示变体。
    public let variant: AnyListID?

    /// 创建展示节点 identity。
    ///
    /// - Parameters:
    ///   - sectionID: 类型擦除后的 section id。
    ///   - rowID: 类型擦除后的 row id。
    ///   - presentationID: cell 或 supplementary view 类型对应的展示身份。
    ///   - variant: 可选展示变体。
    public init(
        sectionID: AnyListID,
        rowID: AnyListID,
        presentationID: ObjectIdentifier,
        variant: AnyListID? = nil
    ) {
        self.sectionID = sectionID
        self.rowID = rowID
        self.presentationID = presentationID
        self.variant = variant
    }
}
