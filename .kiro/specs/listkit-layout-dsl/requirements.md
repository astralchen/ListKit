# ListKit Layout DSL Requirements

## Requirement 1: Section Layout DSL

**User Story:** 作为 ListKit 页面开发者，我希望 section 可以直接声明列表或网格布局，减少 VC 中重复的 compositional layout 代码。

### Acceptance Criteria

- WHEN 开发者声明 section THE SYSTEM SHALL 支持 `.layout(.list(...))`。
- WHEN 开发者声明 section THE SYSTEM SHALL 支持 `.layout(.grid(columns: 2, spacing: 12))`。
- WHEN 开发者声明横向自适应 section THE SYSTEM SHALL 支持 `.layout(.horizontal(...))`。
- WHEN 开发者需要完全自定义 compositional layout THE SYSTEM SHALL 支持 `.layout(.custom(id: ...) { section, index, environment in ... })`。
- WHEN 旧页面使用 `.layout("legacy-id")` THE SYSTEM SHALL 保持源码兼容并继续写入 `layoutID`。

## Requirement 2: Compositional Layout Helper

**User Story:** 作为 UIKit 页面开发者，我希望 ListKit 能根据 section DSL 生成 `UICollectionViewCompositionalLayout`，但不强制接管 layout 生命周期。

### Acceptance Criteria

- WHEN adapter 已经 apply sections THE SYSTEM SHALL 提供 `makeCompositionalLayout(fallback:)`。
- WHEN 页面调用 helper THE SYSTEM SHALL 返回可赋值给 `collectionView.collectionViewLayout` 的 layout。
- WHEN section 未声明 layout THE SYSTEM SHALL 使用 `.list()` 默认布局。
- WHEN section 使用 `.custom(id:) { ... }` THE SYSTEM SHALL 使用闭包返回的 section，再补充 supplementary layout。

## Requirement 3: Boundary Supplementary Layout

**User Story:** 作为列表开发者，我希望 header、footer 和 custom supplementary 可以自动出现在 compositional layout 中。

### Acceptance Criteria

- WHEN section 声明 header THE SYSTEM SHALL 自动生成 top boundary supplementary。
- WHEN section 声明 footer THE SYSTEM SHALL 自动生成 bottom boundary supplementary。
- WHEN section 声明 custom kind supplementary 且没有显式布局 THE SYSTEM SHALL 默认生成 top boundary supplementary。
- WHEN 开发者调用 `.boundarySupplementaryLayout(...)` THE SYSTEM SHALL 覆盖对应 kind 的 alignment、尺寸、pin、zIndex。
- WHEN section 调用 `.stickyHeader()` THE SYSTEM SHALL 仅让 header boundary `pinToVisibleBounds = true`。

## Requirement 4: Item-Level Supplementary Layout

**User Story:** 作为业务页面开发者，我希望 badge、角标等 custom supplementary 可以挂到每个 item 上。

### Acceptance Criteria

- WHEN 开发者调用 `.itemSupplementaryLayout(...)` THE SYSTEM SHALL 生成 `NSCollectionLayoutSupplementaryItem`。
- WHEN item-level supplementary 被配置 THE SYSTEM SHALL 复用现有 Supplementary 的注册、dequeue、configure、tap 和 refresh policy。
- WHEN supplementary provider 收到 item-level indexPath THE SYSTEM SHALL 使用该 item indexPath 构造 `ListContext`。

## Requirement 5: Layout Diagnostics

**User Story:** 作为框架使用者，我希望错误布局配置能在 DEBUG 下被清晰报告。

### Acceptance Criteria

- WHEN `.grid(columns:)` 小于 1 THE SYSTEM SHALL 产生 diagnostics issue，并在布局生成时按 1 column 兜底。
- WHEN 同一个 kind 同时配置 boundary 和 item placement THE SYSTEM SHALL 产生 diagnostics issue。
- WHEN 发生 placement 冲突 THE SYSTEM SHALL 采用最后一次显式配置。
