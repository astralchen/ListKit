# ListKit Adaptation Optimization Design

## Adapter Ownership

`CollectionListAdapter` 继续独占 `UICollectionViewDataSource` 与 `UICollectionViewDelegate`。页面需要滚动、布局、展示回调时，通过 adapter 的转发属性接入：

- `scrollDelegate`
- `layoutDelegate`
- `displayDelegate`

点击、cell 内按钮、可见刷新优先由 Row DSL 表达。

## Migration Support

`ListCellProvider`、`AnyListCellProvider`、`ListSupplementaryProvider`、`AnyListSupplementaryProvider`、`ListProviderSection` 和相关 builder 标记为 migration-only deprecated API。这样保留编译兼容，同时让新代码和后续迁移明确转向 DSL。

## Stable Identity

麦位页引入 `SeatRowID(seatIndex, variant, camp)`：

- `SeatPositionInfo` 只作为 Row model/refreshID，不作为 row identity。
- PK 红蓝阵营用 `camp` 区分同号麦位。
- 普通麦位、PK 主持位、PK 成员位用 `variant` 区分展示 cell。

空状态使用固定字符串 ID，评论 section 使用固定 `.comment`，榜单容器 hash 不再混入随机 UUID。

## Gesture Scope

ListKit supplementary tap 使用私有 `ListTapGestureRecognizer`，复用时只移除 ListKit 自己安装的 recognizer，保留业务 view 原有手势。
