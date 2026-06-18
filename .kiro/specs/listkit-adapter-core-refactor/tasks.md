# ListKit Adapter Core Refactor Tasks

## Phase P0: Spec

- [x] Task 1: 新增本 Kiro requirements/design/tasks，明确抽 pure Swift core，不迁移业务页面。
- [x] Task 2: 更新 README Kiro spec 列表，补充 adapter core refactor 入口。

## Phase P1: Characterization Tests

- [x] Task 3: 新增 core planner 测试，覆盖 row summary、supplementary summary、refresh strategy matrix 和 diagnostics stop。
- [x] Task 4: 新增 shared event router 测试，覆盖 typed dispatch 和未注册事件忽略。
- [x] Task 5: 新增 Table header/footer refresh 测试，锁定 `refreshID` summary 和 visible refresh。

## Phase P2: Core Extraction

- [x] Task 6: 新增 `Core/ListApplyCore.swift`，实现 `ListNodeSnapshot`、`ListSectionSnapshot`、`ListApplyPlan`、`ListApplyPlanner`。
- [x] Task 7: 在 core 中集中 diagnostics stop policy、summary builder、refresh resolver。
- [x] Task 8: 新增 `ListEventRouter<Context>` 并由两个 adapter 复用。

## Phase P3: Collection Adapter Wiring

- [x] Task 9: 将 `ListSection` 映射为 shared core snapshot。
- [x] Task 10: 用 `ListApplyPlan` 驱动 snapshot refresh、visible refresh 和 summary 更新。
- [x] Task 11: 删除 Collection adapter 中重复的 diagnostics stop、summary、refresh decision、event dictionary helper。

## Phase P4: Table Adapter Wiring

- [x] Task 12: 将 `TableSection` 映射为 shared core snapshot，header/footer 映射为 supplementary nodes。
- [x] Task 13: 用 `ListApplyPlan` 驱动 table row snapshot reload、summary 和 row visible refresh。
- [x] Task 14: 实现 table header/footer visible refresh，并删除 table 私有 validate/summary/refresh/event 重复实现。

## Phase P5: Verification and Cleanup

- [x] Task 15: 更新 README/Swift Doc，说明 shared core、Table header/footer refresh 和 `.forceReload` 语义。
- [x] Task 16: 运行重复 helper 搜索、`git diff --check`、UIKit/macOS SwiftPM 探针和 iOS build/test 验证。

## Verification

- `rg -n "listkit-adapter-core-refactor|Shared Apply Planner|ListApplyPlanner" SharePackage/ListKit`
- `rg -n "private func (shouldStopBeforeDiffableApply|makeApplySummary|itemsNeedingSnapshotRefresh|shouldRunVisibleRefresh|logDiagnostics|logApplySummary)" SharePackage/ListKit/Sources/ListKit`
- `git diff --check`
- `swift test --package-path SharePackage/ListKit` 记录 UIKit/macOS route 失败。
- `xcodebuild -quiet -project Rebirth.xcodeproj -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/RebirthDerivedData-ListKitAdapterCore` reaches app compile but fails to resolve CocoaPods module `JXPhotoBrowser`; use workspace route per repository setup.
- `xcodebuild -quiet -workspace Rebirth.xcworkspace -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/RebirthDerivedData-ListKitAdapterCore-Workspace`
