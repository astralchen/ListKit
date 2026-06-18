# ListKit Item Supplementary Refresh Tasks

- [x] Task 1: 新增本 Kiro requirements/design/tasks。
- [x] Task 2: 为 `ListSectionSupplementary.itemSupplementaryLayout(...)` API rename 增加失败测试。
- [x] Task 3: 为 item supplementary 可见自动刷新、`.never` 跳过、手动刷新和 summary 统计增加失败测试。
- [x] Task 4: 将 `ListSectionSupplementary` 的旧短名 item layout modifier 改名为 `itemSupplementaryLayout(...)`，并更新 README 示例。
- [x] Task 5: 为 `AnySupplementary` 和 `CollectionListAdapter` 补齐 visible supplementary refresh 实现。
- [x] Task 6: 运行 ListKit build/test、残留搜索和 diff check，记录验收结果。

## Verification

- `xcodebuild -quiet -scheme ListKit -destination 'generic/platform=iOS Simulator' build` 通过。
- `xcodebuild -quiet -scheme ListKit -destination 'platform=iOS Simulator,name=iPhone 17' test` 通过。
- `rg -n "\\.item\\(" SharePackage/ListKit/Sources/ListKit SharePackage/ListKit/README.md SharePackage/ListKit/.kiro` 无命中。
- `git diff --check` 通过。

Note: 本机没有 `iPhone 16` simulator，可用目的地为 `iPhone 17` 等 iOS 26.3.1 simulator，因此 test 验证使用 `iPhone 17`。
