# ListKit Layout DSL Tasks

- [x] Task 1: 新增 `requirements.md`、`design.md`、`tasks.md`，按 Kiro 记录 layout DSL 目标。
- [x] Task 2: 先添加失败 XCTest，覆盖 DSL、helper、supplementary、diagnostics。
- [x] Task 3: 新增布局描述类型：`ListSectionLayout`、`ListLayoutDimension`、`ListLayoutInsets`、`ListSupplementaryLayout`。
- [x] Task 4: 为 `ListSection` 增加 `.layout(_:)`、`.boundarySupplementaryLayout(...)`、`.itemSupplementaryLayout(...)`。
- [x] Task 5: 实现 `ListSection.makeCompositionalLayoutSection()` 和 supplementary 默认规则。
- [x] Task 6: 实现 `CollectionListAdapter.makeCompositionalLayout(fallback:)` compositional layout helper 和 `makeCompositionalSection(for:)`。
- [x] Task 7: 扩展 diagnostics：invalid columns、supplementary placement conflict。
- [x] Task 8: 更新 README，加入 Layout DSL 和 item-level supplementary 示例。
- [x] Task 9: 运行 ListKit tests、ListKit build、Rebirth workspace build。

## Verification

```bash
xcodebuild test -scheme ListKit -destination 'id=<booted-simulator-id>'
xcodebuild -scheme ListKit -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace Rebirth.xcworkspace -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```
