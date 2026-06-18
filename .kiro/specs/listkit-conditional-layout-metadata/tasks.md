# ListKit Conditional Layout Metadata Tasks

- [x] Task 1: 新增本 Kiro requirements/design/tasks。
- [x] Task 2: 为 conditional layout metadata、conditional supplementary、background decoration 增加失败测试。
- [x] Task 3: 实现 `ListBackgroundDecoration` 和 `ListSection.backgroundDecoration(...)` typed/raw/nil API。
- [x] Task 4: 实现条件 supplementary 测试覆盖，最终由 SwiftUI-like builder API 承载。
- [x] Task 5: 在 `makeCompositionalLayoutSection()` 追加 background decoration item，并保留 custom layout 原有 decoration。
- [x] Task 6: 在 `CollectionListAdapter` 增加 layout metadata diff、自动 decoration 注册和自动 invalidate。
- [x] Task 7: 更新 README 使用示例。
- [x] Task 8: 运行 ListKit test/build、Rebirth build 和 `git diff --check`。
- [x] Task 9: 根据 API 评审反馈，把条件 header/footer/supplementary 调整为 SwiftUI-like builder 写法。
- [x] Task 10: 将 background decoration 也补齐为 SwiftUI-like `background:` builder，并保留 `.backgroundDecoration(...)` 固定配置简写。
- [x] Task 11: 将 section layout 和 supplementary layout 补齐为 SwiftUI-like `layout:` / `supplementaryLayouts:` builder，并新增 `ListLayout`、`GridLayout`、`HorizontalLayout`、`BoundarySupplementaryLayout`、`ItemSupplementaryLayout` 工厂。
- [x] Task 12: 清理 `headerIf`、`footerIf`、`supplementaryIf` 条件参数 API，避免与 builder 条件分支重复。

## Verification

- `xcodebuild -quiet -scheme ListKit -destination 'id=714D7775-9CE5-4F6A-8036-C0B93E45FA04' test`（在 `SharePackage/ListKit` package 目录运行）通过。
- `xcodebuild -quiet -scheme ListKit -destination 'generic/platform=iOS Simulator' build` 通过。
- `xcodebuild -quiet -workspace Rebirth.xcworkspace -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` 通过。
- `git diff --check` 通过。
