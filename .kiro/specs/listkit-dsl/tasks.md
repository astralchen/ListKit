# ListKit DSL Tasks

## Completed

- [x] Task 1: 创建 `SharePackage/ListKit` 本地 SPM，配置 iOS 14、Swift 6、`ListKit` library product。
- [x] Task 2: 实现 reusable 基础层：reuse id、自动 nib/class 注册、UICollectionView cell/supplementary 类型安全 dequeue。
- [x] Task 3: 实现 DSL builder：`ListSectionBuilder`、`ListRowBuilder`、`ForEach`、条件分支支持。
- [x] Task 4: 实现 Row/Supplementary 描述模型和内部类型擦除。
- [x] Task 5: 实现 identity 规则：默认使用 `rowID + Cell.self`，支持 `.variant(...)`。
- [x] Task 6: 实现 refresh 策略：`.automaticVisible`、`.whenRefreshIDChanges`、`.never`、`.alwaysVisible`。
- [x] Task 7: 实现 `CollectionListAdapter`，包括 diffable data source、apply、snapshot、visible reconfigure。
- [x] Task 8: 实现内置事件桥接：select、display、prefetch、context menu、swipe actions。
- [x] Task 9: 实现 Header/Footer 声明、注册、配置、tap 事件。
- [x] Task 10: 实现自定义事件系统：`ListEvent`、`context.send`、`.onEvent`。
- [x] Task 11: 添加 iOS XCTest，覆盖 builder、identity、cell type 切换、refreshID、Header/Footer、自定义事件。
- [x] Task 12: 将 `PartyViewController` 迁移到 ListKit，验证 if/else Row、Cell 类型切换、刷新和点击事件。
- [x] Task 13: 将 `SearchViewController` 迁移到 ListKit，验证 Header 事件、自定义事件、分区 DSL。
- [x] Task 14: 运行包级 iOS 测试和 Rebirth workspace 集成构建。
- [x] Task 15: 更新迁移说明，列出 CellKit 到 ListKit 的常用写法对照。
- [x] Task 16: 优化 Row 初始化 API：`ForEach` 内继承 id、单个 `Identifiable` model 自动 id、普通 model 支持 keyPath/closure id。
- [x] Task 17: 为 ListKit 包补齐 `.gitignore`，避免 `.swiftpm` 和 `.DS_Store` 等本地文件进入仓库。

## Verification

- [x] 包级测试：

```bash
xcodebuild test -scheme ListKit -destination 'id=40789BEC-6977-4FC6-AA42-0ACDF687EF7D'
```

结果：9 tests, 0 failures。

- [x] 工程集成构建：

```bash
xcodebuild -workspace Rebirth.xcworkspace -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

结果：`BUILD SUCCEEDED`。

- [x] 格式检查：

```bash
git diff --check
```

结果：通过。

## Remaining Follow-up

- [ ] 手动回归：派对页、搜索页、房间公屏、座位列表、个人主页列表。
- [ ] 按业务优先级继续迁移更多 CellKit 页面。
- [ ] 后续评估 UITableView DSL adapter 是否纳入 ListKit。
