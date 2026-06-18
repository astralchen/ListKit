# ListKit Adaptation Optimization Tasks

- [x] Task 1: 补 Kiro requirements/design/tasks。
- [x] Task 2: ListKit 增加 `displayDelegate`，修复 supplementary tap 只移除自身手势。
- [x] Task 3: 将 provider 兼容层和未命名空间 reusable helper 标记为 migration-only/deprecated，引导新代码使用 Row/ListSection 与 collectionView.lk。
- [x] Task 4: SeatPositionViewController 改为 `CollectionListAdapter + ListSection + Row`，引入稳定 `SeatRowID`。
- [x] Task 5: RoomPermissionsManagerViewController 改为真正 adapter 页面，移除手写 data source。
- [x] Task 6: PublicMessageViewController / ToolbarViewController 保留业务行为并移除直接 delegate 覆盖。
- [x] Task 7: Topic / InformineDetail / Profile 三页 / 收藏 / 设置 / 房间详情等 adapter 页面改用 adapter 转发，移除直接 delegate 覆盖。
- [x] Task 8: 修复 `ChannelPkInfo` Hashable、空状态和榜单随机 identity。
- [x] Task 9: 运行 ListKit build/test、Rebirth workspace build 和关键残留搜索。
- [x] Task 10: 修复 ListKit deprecated 迁移 API 警告，App 层移除旧 provider 类型调用，改由 App 侧桥接层输出原生 `ProviderRow`/`ListSection`。

## Follow-up

- [x] 已执行 `.kiro/specs/listkit-api-hardening/tasks.md`，移除 `AppListSection` / `AppListCellItem` 桥接层并增强 adapter row lookup / visible refresh API。
