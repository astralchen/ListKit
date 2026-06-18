# ListKit DSL Requirements

## Requirement 1: 新本地包与迁移边界

**User Story:** 作为 Rebirth iOS 开发者，我希望用新的 `ListKit` 替代 `CellKit`，以获得更 Swift、更声明式、更并发安全的列表开发方式。

### Acceptance Criteria

1. WHEN 工程引入新列表框架 THE SYSTEM SHALL 创建本地 SPM `SharePackage/ListKit`，模块名和产品名均为 `ListKit`。
2. WHEN 旧页面尚未迁移 THE SYSTEM SHALL 允许 `CellKit` 与 `ListKit` 并行存在。
3. WHEN 新页面使用 ListKit THE SYSTEM SHALL 不要求业务 model conform 框架协议。
4. WHEN 包级构建运行 THE SYSTEM SHALL 支持 iOS 14+ 和 Swift 6。

## Requirement 2: SwiftUI-like DSL

**User Story:** 作为页面开发者，我希望用接近 SwiftUI 的 DSL 声明 Row、Header、Footer 和事件。

### Acceptance Criteria

1. WHEN 开发者构建列表 THE SYSTEM SHALL 支持 `ListSection { Row(...) }`、`ForEach`、`if/else`、`switch`。
2. WHEN 开发者声明 Header/Footer THE SYSTEM SHALL 支持 `.header(...)`、`.footer(...)` modifier。
3. WHEN 开发者配置 cell 或 supplementary view THE SYSTEM SHALL 提供强类型 `cell/view + model + context` 闭包。
4. WHEN Row 位于 `ForEach(data, id:)` 内 THE SYSTEM SHALL 允许 `Row(model:cell:)` 自动继承外层 item id。
5. WHEN 单个 model conform `Identifiable` THE SYSTEM SHALL 支持 `Row(model:cell:)` 自动使用 `model.id`。
6. WHEN 单个 model 不 conform `Identifiable` THE SYSTEM SHALL 支持 `Row(model:id:cell:)` 的 keyPath 和 closure 两种身份声明方式。

## Requirement 3: Row 身份、重建与刷新

**User Story:** 作为开发者，我希望每次数据变化后重建列表描述树，由框架判断是换 Cell、刷新 Cell，还是保持不动。

### Acceptance Criteria

1. WHEN `rowID` 相同但 `Cell.self` 变化 THE SYSTEM SHALL 将其视为不同展示节点并执行 delete + insert。
2. WHEN `rowID` 和 `Cell.self` 相同且 `refreshID` 变化 THE SYSTEM SHALL reconfigure 或 reload 对应 item。
3. WHEN 没有提供 `refreshID` THE SYSTEM SHALL 默认只刷新可见同 identity cell，避免不可见项无意义重配。
4. WHEN 页面性能敏感 THE SYSTEM SHALL 支持 `.refreshPolicy(.whenRefreshIDChanges)`、`.refreshID(...)`、`.refreshPolicy(.never)`。
5. WHEN 同一个 `Cell.self` 需要表达不同展示节点 THE SYSTEM SHALL 支持 `.variant(...)`。

## Requirement 4: 事件系统

**User Story:** 作为开发者，我希望 Row/Header/Footer 都能处理标准事件，也能抛出业务自定义事件。

### Acceptance Criteria

1. WHEN Row 被选中、展示、结束展示、预取或取消预取 THE SYSTEM SHALL 提供对应 modifier。
2. WHEN Header/Footer 需要点击事件 THE SYSTEM SHALL 通过 `.onTap` 或 section 级 `.onHeaderTap` / `.onFooterTap` 处理。
3. WHEN cell 内部按钮触发业务动作 THE SYSTEM SHALL 允许通过 `context.send(Event)` 发送类型安全自定义事件。
4. WHEN 页面监听自定义事件 THE SYSTEM SHALL 支持 `.onEvent(Event.self) { event, context in ... }`。
5. WHEN 页面需要 UIKit 高级交互 THE SYSTEM SHALL 支持 context menu 和 swipe actions。

## Requirement 5: Swift 6 并发安全

### Acceptance Criteria

1. WHEN API 触碰 UIKit THE SYSTEM SHALL 标记为 `@MainActor`。
2. WHEN 闭包被保存或跨异步边界使用 THE SYSTEM SHALL 使用 `@MainActor`，必要时使用 `@Sendable`。
3. WHEN identity 参与 diff THE SYSTEM SHALL 要求 `Hashable & Sendable`。
4. WHEN UIKit 或类型擦除无法静态证明 Sendable THE SYSTEM SHALL 用局部、可解释的 `@unchecked Sendable` 封装。
