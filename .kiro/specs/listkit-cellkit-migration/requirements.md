# ListKit CellKit Migration Requirements

## Requirement 1: 移除 App 对 CellKit 的依赖

**User Story:** 作为 Rebirth iOS 开发者，我希望 App 层统一使用 ListKit，避免 CellKit 与 ListKit 长期并行造成列表写法分裂。

### Acceptance Criteria

- WHEN 迁移完成 THE SYSTEM SHALL 不再在 `Rebirth/` 源码中 import CellKit。
- WHEN 迁移完成 THE SYSTEM SHALL 不再在 `Rebirth.xcodeproj/project.pbxproj` 中链接 CellKit product 或引用 `SharePackage/CellKit` local package。
- WHEN 迁移完成 THE SYSTEM SHALL 保留 `SharePackage/CellKit` 目录，仅作为历史实现回查。
- WHEN 文档描述本地包 THE SYSTEM SHALL 用 ListKit 替代 CellKit 作为列表工具。

## Requirement 2: 按 ListKit 最佳模式重建列表

**User Story:** 作为页面开发者，我希望页面在数据变化后 rebuild ListKit 描述树，由 identity、refreshID 和 refresh policy 决定 diff 与刷新。

### Acceptance Criteria

- WHEN 旧页面使用 `CollectionViewController` THE SYSTEM SHALL 改为显式持有 `CollectionListAdapter<Section>`。
- WHEN 旧页面使用 `CollectionViewSectionType` THE SYSTEM SHALL 改为 `ListSection` DSL。
- WHEN 行数据变化 THE SYSTEM SHALL 使用稳定 row identity 和必要的 `refreshID`。
- WHEN cell 或 supplementary 内部按钮触发业务动作 THE SYSTEM SHALL 通过 ListKit context/event 或 Row 选择回调转发到页面。

## Requirement 3: 迁移旧 item 模型

**User Story:** 作为维护者，我希望旧 `CollectionViewCellItem` / `CollectionViewSupplementary` 模型不再依赖 CellKit。

### Acceptance Criteria

- WHEN 模型只服务单个页面 THE SYSTEM SHALL 优先内联为 Row 配置闭包。
- WHEN 模型包含复杂配置或被多个页面复用 THE SYSTEM SHALL 改为普通配置器或 view model，由 Row/Supplementary 闭包调用。
- WHEN 旧模型名称保留 THE SYSTEM SHALL 不再 conform CellKit 协议。

## Requirement 4: ListKit 补齐 UIKit 工具能力

**User Story:** 作为迁移者，我希望 ListKit 提供 CellKit 里被业务页面广泛使用的 UIKit 便捷能力。

### Acceptance Criteria

- WHEN 页面需要统一 decoration kind THE SYSTEM SHALL 在 ListKit 暴露 section background/separator 等 kind 常量。
- WHEN 页面需要类名作为 supplementary kind THE SYSTEM SHALL 提供 `UICollectionView.elementKind(for:)`。
- WHEN 页面需要 nib/class 自动注册 THE SYSTEM SHALL 通过 `collectionView.lk` 和 layout helper 支持 cell、supplementary、decoration view。
- WHEN 页面需要分隔线 compositional layout THE SYSTEM SHALL 在 ListKit 提供 `UICollectionViewCompositionalSeparatorLayout`。

## Requirement 5: 验证

### Acceptance Criteria

- WHEN 迁移完成 THE SYSTEM SHALL 通过 ListKit package tests。
- WHEN 迁移完成 THE SYSTEM SHALL 通过 Rebirth workspace simulator build。
- WHEN 迁移完成 THE SYSTEM SHALL 通过全局搜索确认 App 和工程无旧 CellKit 符号残留。
