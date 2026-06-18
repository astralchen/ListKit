# ListKit Adapter Core Refactor Design

## Architecture

新增 `Core/ListApplyCore.swift`，承载纯 Swift 的 apply planning、summary、refresh decision、diagnostics stop policy 和 event router。Adapter 每次 apply 时把自身 section 描述树转换成 `ListSectionSnapshot`，core 返回 `ListApplyPlan`，adapter 只负责注册 view、构建 UIKit diffable snapshot、执行 UIKit apply 和可见 view 重配。

Core types are internal to ListKit:

```swift
struct ListNodeSnapshot {
    let identity: AnyListIdentity
    let refreshID: AnyListID?
    let refreshPolicy: RowRefreshPolicy
    let role: ListNodeRole
}

struct ListSectionSnapshot {
    let sectionID: AnyListID
    let rows: [ListNodeSnapshot]
    let supplementaries: [ListNodeSnapshot]
}
```

`ListNodeRole` distinguishes row and supplementary-like nodes. Collection headers/footers/custom supplementary and Table header/footer all map to supplementary nodes. Row insert/delete/keep counts remain row-only to preserve `ListApplySummary` public semantics; supplementary changes use the existing supplementary fields.

## Apply Planner

`ListApplyPlanner.makePlan(old:new:options:diagnosticsIssues:)` returns:

- `shouldApplyDiffable`
- `snapshotRefreshItems`
- `shouldRunVisibleRefresh`
- `initialSummary`
- `completedSummary(visibleRefreshCount:visibleSupplementaryRefreshCount:)`
- old/new row and supplementary node lookups for adapter completion work

Refresh rules:

- `.automatic` / `.diffableOnly`: snapshot refresh rows whose policy is `.whenRefreshIDChanges` and whose kept `refreshID` changed.
- `.visibleOnly`: no snapshot refresh; visible refresh may run.
- `.forceReload`: snapshot refresh kept row identities only; no visible refresh.
- default visible row refresh runs for `.automaticVisible` and `.alwaysVisible`.
- supplementary visible refresh runs for `.automaticVisible`, `.alwaysVisible`, and `.whenRefreshIDChanges` when the kept supplementary `refreshID` changed.

Diagnostics stop rules are centralized. `.warning` and `.assertion` return `shouldApplyDiffable == false`; `.assertion` also calls `assertionFailure`.

## Adapter Boundaries

Collection adapter keeps:

- `UICollectionViewDiffableDataSource`
- iOS 15 `reconfigureItems` vs iOS 14 `reloadItems`
- supplementary lookup by kind/section
- layout signature/invalidation
- compositional layout diagnostics

Table adapter keeps:

- `UITableViewDiffableDataSource`
- row/header/footer registration and delegate callbacks
- row visible reconfigure/reload helpers
- header/footer visible refresh after apply completion

Both adapters replace duplicated event dictionaries with `ListEventRouter<Context>`.

## Testing

Core tests use `@testable import ListKit` and construct `ListNodeSnapshot` directly. Adapter tests cover integration gaps that pure core cannot see, especially Table header/footer visible refresh and Collection layout invalidation.

`swift test --package-path SharePackage/ListKit` is expected to fail on macOS because ListKit imports UIKit. iOS verification uses `xcodebuild` with a writable `-derivedDataPath`.
