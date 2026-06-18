# ListKit Enhancements Requirements

## Summary

本规格覆盖 ListKit 增强版 1-13 项能力。开发按三期推进：

- P0: diagnostics、apply options、debug summary、带 model 事件与 prefetch。
- P1: 状态 Row、layout metadata、selection state、supplementary 增强、delegate forwarding。
- P2: UITableView adapter 独立规格、宏/代码生成探索、完整文件结构拆分。

## Requirement 1: Identity 诊断

**User Story:** 作为 ListKit 使用者，我希望重复 identity 在 `apply` 前被清晰指出，避免 diffable data source 抛出难定位的崩溃。

### Acceptance Criteria

- WHEN `apply` 产生重复 section identity THE SYSTEM SHALL 生成 `.duplicateSection` 诊断。
- WHEN `apply` 产生重复 row identity THE SYSTEM SHALL 生成 `.duplicateRow` 诊断。
- WHEN `apply` 产生重复 supplementary identity THE SYSTEM SHALL 生成 `.duplicateSupplementary` 诊断。
- WHEN diagnostics mode 为 `.warning` THE SYSTEM SHALL 在 DEBUG 输出 warning 并跳过本次 diffable apply。
- WHEN diagnostics mode 为 `.assertion` THE SYSTEM SHALL 在 DEBUG/assert 环境触发 assertion 并跳过本次 diffable apply。
- WHEN diagnostics mode 为 `.disabled` THE SYSTEM SHALL 保持原始 diffable 行为。

## Requirement 2: 空态/加载态/错误态

**User Story:** 作为页面开发者，我希望用轻量状态 Row 描述 empty/loading/failure，而不是为每个页面重复写状态 section 样板。

### Acceptance Criteria

- WHEN 页面需要空态 THE SYSTEM SHALL 提供 `ListStateRow.empty(...)`。
- WHEN 页面需要加载态 THE SYSTEM SHALL 提供 `ListStateRow.loading(...)`。
- WHEN 页面需要错误态 THE SYSTEM SHALL 提供 `ListStateRow.failure(...)`。
- WHEN 使用状态 Row THE SYSTEM SHALL 只负责 UI 描述，不接管网络请求、重试或页面状态机。

## Requirement 3: Layout 绑定

**User Story:** 作为使用 compositional layout 的开发者，我希望 section DSL 能携带 layout 标识，方便数据描述与布局 provider 对齐。

### Acceptance Criteria

- WHEN 声明 section THE SYSTEM SHALL 支持 `.layout(...)` 绑定 `Hashable & Sendable` 布局标识。
- WHEN 外部构建 layout provider THE SYSTEM SHALL 可通过 section metadata 查找布局配置。
- WHEN 首版实现 THE SYSTEM SHALL 不强制接管 `UICollectionViewCompositionalLayout` 的创建。

## Requirement 4: Cell 事件绑定增强

**User Story:** 作为页面开发者，我希望 cell 内按钮、手势或菜单事件能少写样板，同时保留类型安全事件。

### Acceptance Criteria

- WHEN cell 内部按钮触发业务动作 THE SYSTEM SHALL 支持 `.onCellEvent(...)` 绑定 cell 事件入口。
- WHEN `.onCellEvent(...)` 触发 THE SYSTEM SHALL 使用 `context.send(Event)` 分发强类型 `ListEvent`。
- WHEN 页面已有自定义写法 THE SYSTEM SHALL 继续支持在 configure 闭包里手动调用 `context.send(...)`。

## Requirement 5: Debug 日志

**User Story:** 作为调试刷新问题的开发者，我希望每次 apply 能看到插入、删除、保留和刷新统计。

### Acceptance Criteria

- WHEN DEBUG apply THE SYSTEM SHALL 输出 inserted/deleted/kept。
- WHEN refreshID 变化 THE SYSTEM SHALL 输出 refreshIDChanged。
- WHEN diffable reconfigure/reload THE SYSTEM SHALL 输出 snapshotRefresh。
- WHEN 可见 cell 重配 THE SYSTEM SHALL 输出 visibleRefresh。
- WHEN diagnostics 关闭日志 THE SYSTEM SHALL 不输出 summary。

## Requirement 6: Prefetch 携带 model

**User Story:** 作为页面开发者，我希望 prefetch/cancelPrefetch 可以直接拿到 model，避免手动捕获或按 indexPath 回查。

### Acceptance Criteria

- WHEN 声明 prefetch THE SYSTEM SHALL 支持 `.onPrefetch { model, context in ... }`。
- WHEN 声明 cancel prefetch THE SYSTEM SHALL 支持 `.onCancelPrefetch { model, context in ... }`。
- WHEN 旧 API 使用 `.onPrefetch { context in ... }` THE SYSTEM SHALL 继续兼容。

## Requirement 7: Selection State

**User Story:** 作为开发者，我希望礼物、标签和用户选择等场景能声明 selection mode、初始选中态和变化回调。

### Acceptance Criteria

- WHEN section 需要多选 THE SYSTEM SHALL 支持 `.selectionMode(.multiple)`。
- WHEN row 需要初始选中 THE SYSTEM SHALL 支持 `.selected(true)`。
- WHEN 选中状态变化 THE SYSTEM SHALL 支持 `.onSelectionChange { isSelected, context in ... }`。
- WHEN 需要 model THE SYSTEM SHALL 支持 `.onSelectionChange { model, isSelected, context in ... }`。

## Requirement 8: Supplementary 增强

**User Story:** 作为页面开发者，我希望 header/footer/custom supplementary 能拥有更完整的刷新和布局附加能力。

### Acceptance Criteria

- WHEN supplementary 数据变化 THE SYSTEM SHALL 支持 `.refreshID(...)` 和 `.refreshPolicy(...)`。
- WHEN section header 需要吸顶 THE SYSTEM SHALL 支持 `.stickyHeader()` 元数据。
- WHEN section 需要 background decoration THE SYSTEM SHALL 支持 `.backgroundDecoration(...)` 元数据。
- WHEN section 需要多个 custom kind THE SYSTEM SHALL 支持多次 `.supplementary(kind, ...)`。

## Requirement 9: Delegate Forwarding

**User Story:** 作为已有页面迁移者，我希望 `CollectionListAdapter` 接管 delegate 后，不丢失 scroll 和 flow layout 扩展点。

### Acceptance Criteria

- WHEN 页面设置 `scrollDelegate` THE SYSTEM SHALL 转发常用 `UIScrollViewDelegate` 回调。
- WHEN 页面设置 `layoutDelegate` THE SYSTEM SHALL 转发常用 `UICollectionViewDelegateFlowLayout` 回调。
- WHEN 未设置转发 delegate THE SYSTEM SHALL 使用 layout 自身默认值。

## Requirement 10: Apply 级刷新策略

**User Story:** 作为页面开发者，我希望除了 Row 级策略，也能在一次 apply 上选择全局刷新行为。

### Acceptance Criteria

- WHEN 使用 `.automatic` THE SYSTEM SHALL 沿用 Row refresh policy。
- WHEN 使用 `.visibleOnly` THE SYSTEM SHALL 跳过 diffable reconfigure/reload，只做可见重配。
- WHEN 使用 `.diffableOnly` THE SYSTEM SHALL 只做 diffable reconfigure/reload，跳过默认可见重配。
- WHEN 使用 `.forceReload` THE SYSTEM SHALL 对当前 snapshot item 执行 reconfigure/reload。

## Requirement 11: UITableView Adapter

**User Story:** 作为仍使用 UITableView 的页面开发者，我希望后续可以复用 ListKit 的 identity、refresh、diagnostics、event 和 reusable 语义。

### Acceptance Criteria

- WHEN 进入 P2 THE SYSTEM SHALL 新增独立 spec 设计 `TableListAdapter`。
- WHEN 设计 table adapter THE SYSTEM SHALL 使用独立 Table DSL，不泛化当前 collection-only `Row/ListSection/ListContext`。
- WHEN 首版 table adapter 实现 THE SYSTEM SHALL 覆盖 UIKit 原生 UITableView 常用能力，包括 cell/header/footer、selection、display、prefetch、高度、editing、move、context menu、swipe 和可见刷新。
- WHEN 页面使用第三方 swipe THE SYSTEM SHALL 不把 `SwipeCellKit` 引入 ListKit package。

## Requirement 12: 文件结构拆分

**User Story:** 作为维护者，我希望增强能力稳定后把集中式 `ListKit.swift` 拆成更清晰的文件。

### Acceptance Criteria

- WHEN P0/P1 API 稳定 THE SYSTEM SHALL 拆分 Identity、Reusable、Row、Supplementary、Builder、Adapter、Events、Diagnostics。
- WHEN 拆分文件 THE SYSTEM SHALL 保持 public API 不变。
- WHEN 拆分完成 THE SYSTEM SHALL 继续通过包级 XCTest。

## Requirement 13: 宏或代码生成探索

**User Story:** 作为框架维护者，我希望评估宏是否能减少事件绑定和 cell 配置样板，但不希望首版过早依赖宏。

### Acceptance Criteria

- WHEN P2 调研 THE SYSTEM SHALL 输出宏/代码生成设计结论。
- WHEN API 未稳定 THE SYSTEM SHALL 不把宏作为默认实现路径。
- WHEN 需要兼容 iOS 14 THE SYSTEM SHALL 确认宏只影响编译期，不引入运行时依赖。
