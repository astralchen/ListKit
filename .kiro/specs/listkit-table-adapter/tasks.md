# ListKit Table Adapter Tasks

## Phase P0: Spec

- [x] Task 1: 新增 `.kiro/specs/listkit-table-adapter/requirements.md`、`design.md`、`tasks.md`。
- [x] Task 2: 明确 Table DSL 独立于 Collection DSL，不泛化现有 `Row/ListSection/ListContext`。
- [x] Task 3: 明确首版完整 UITableView 能力范围，并排除 `SwipeCellKit` package 依赖。
- [x] Task 4: 更新 `listkit-enhancements` P2 任务和 README 入口说明。

## Phase P1: Core Table Types

- [x] Task 5: 新增 `TableListContext`、`TableApplyResult`、`TableSection`、`TableRow`、`TableHeader`、`TableFooter` 和 table result builders。
- [x] Task 6: 新增 `UITableView.lk` reusable namespace，覆盖 cell 和 header/footer class/nib 自动注册、类型安全 dequeue。
- [x] Task 7: 新增 table diagnostics，覆盖 duplicate section/row/header/footer identity。

## Phase P2: Adapter Apply and Refresh

- [x] Task 8: 实现 `TableListAdapter<SectionID>` 初始化并接管 `UITableViewDataSource`、`UITableViewDelegate`、`UITableViewDataSourcePrefetching`。
- [x] Task 9: 实现 apply overloads、diffable snapshot、lookup table rebuild、自动注册和 apply summary。
- [x] Task 10: 实现 `refreshID`、`RowRefreshPolicy`、`ListApplyRefreshStrategy`、可见轻刷和可见 reload。
- [x] Task 11: 实现 `sectionIdentifier`、`rowCount/itemCount`、`indexPaths`、`scrollToLastRow` 查询和滚动 helper。

## Phase P3: UITableView Delegate Surface

- [x] Task 12: 实现 selection、display/endDisplay、prefetch/cancelPrefetch。
- [x] Task 13: 实现 row/header/footer fixed、automatic、estimated height。
- [x] Task 14: 实现 context menu、editing、move/reorder、leading/trailing `UISwipeActionsConfiguration`。
- [x] Task 15: 实现 `scrollDelegate` 和 `tableDelegate` forwarding。

## Phase P4: Verification and Docs

- [x] Task 16: 增加 ListKit XCTest 覆盖 table apply、diagnostics、refresh、visible refresh、selection、display、prefetch、高度、editing、swipe、reusable namespace。
- [x] Task 17: 更新 README 和 Swift Doc，说明 Table DSL 的推荐写法和与 Collection DSL 的边界。
- [x] Task 18: 运行 `git diff --check`、targeted search、ListKit test 或记录 UIKit/macOS route 错误，并使用 Rebirth workspace build 兜底。

## Verification

- `rg -n "TableListAdapter|UITableView Adapter|listkit-table-adapter" SharePackage/ListKit/.kiro SharePackage/ListKit/README.md`
- `git diff --check`
- 实现阶段再运行 `swift test` 于 `SharePackage/ListKit`；如因 UIKit/macOS route 失败，记录原始错误。
- 实现阶段使用 `xcodebuild -quiet -workspace Rebirth.xcworkspace -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/RebirthDerivedData-ListKitTableAdapter` 兜底编译。
