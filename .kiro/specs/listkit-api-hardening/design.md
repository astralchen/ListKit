# ListKit API Hardening Design

## Adapter Row Lookup

`CollectionListAdapter` 基于内部 `sections` 和 diffable snapshot 暴露稳定查询能力：

- `indexPaths(forRowID:in:)` 按业务 rowID 和可选 sectionID 返回当前 indexPath。
- `itemCount(in:)` 返回 section 当前 row 数量。
- `scrollToLastItem(in:at:animated:)` 封装空 section 判断和滚动到底部。

这些 API 只读取 adapter 当前描述树和 collection view 状态，不改变 diff 规则。

## Visible Refresh

实时页面通过 adapter API 刷新当前可见 row：

- `reconfigureVisibleRows(forRowID:in:)` 只调用 row 的 `configureVisibleCell` 和 display handler，适合状态轻刷新。
- `reloadVisibleRows(forRowID:in:)` 通过 diffable snapshot reload 当前可见 identity，适合自适应高度或内部布局变化。

两者都只影响当前可见 indexPath，返回实际刷新数量。

## App DSL Migration

App 页面直接构建 `ListSection`：

- 普通业务模型用 `Row(model:id:cell:)`。
- 多 cell 或保留旧配置器的复杂场景用 `ProviderRow`，但不再定义 App 级 provider 协议。
- 原 `AppListCellItem` 类型改成普通 view model/configurer，或在页面内联配置闭包。

页面不再保存 `AppListSection`，需要 item count、indexPath、可见刷新时调用 adapter。

## Documentation

ListKit README 增加实时列表刷新示例，并说明 `ProviderRow` 是少量复杂迁移场景的逃生口，不应重新包装成 App 级协议层。
