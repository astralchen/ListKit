# ListKit Enhancements Tasks

## Phase P0: 诊断、安全和开发体验

- [x] Task 1: 创建 `.kiro/specs/listkit-enhancements/requirements.md`、`design.md`、`tasks.md`，把 13 条整理为可验收需求。
- [x] Task 2: 实现 identity diagnostics：重复 section、row、supplementary 检测和 DEBUG warning/assert 策略。
- [x] Task 3: 实现 `ListApplyOptions` 与 apply 级 refresh 策略，保持旧 `apply(animatingDifferences:)` 源码兼容。
- [x] Task 4: 为 Row 事件和 prefetch 增加带 model 的强类型重载。
- [x] Task 5: 增加 debug apply summary，覆盖 insert/delete/keep/reconfigure/reload 统计。

## Phase P1: DSL 能力增强

- [x] Task 6: 增加轻量 empty/loading/error Row API，不引入网络状态系统。
- [x] Task 7: 增加 section layout 绑定最小 API；完整 Layout DSL 已升级到 `.kiro/specs/listkit-layout-dsl/`。
- [x] Task 8: 增加 selection state API，覆盖单选和多选。
- [x] Task 9: 增强 supplementary：refresh policy、sticky header、background decoration、custom kind 示例。
- [x] Task 10: 增加 delegate forwarding，覆盖 scroll delegate 和 flow layout delegate 常用入口。

## Phase P2: 后续拆分和探索

- [x] Task 11: 拆分 `ListKit.swift` 并按 `Core/DSL/Reusable/Collection/Table` 目录归类，保证 public API 不变。
- [x] Task 12: 调研 UITableView adapter，并形成独立 Kiro spec：`.kiro/specs/listkit-table-adapter/`。
- [ ] Task 13: 调研宏/代码生成，只输出设计结论，不默认实现。

## Test Plan

- [x] 包级 XCTest 新增 diagnostics、重复 identity、apply options、带 model 事件、带 model prefetch、empty/loading/error、selection state、supplementary refresh、delegate forwarding 测试。
- [x] 保留现有 ListKit core tests，确保旧 DSL 不回归。
- [x] 工程集成构建：
  `xcodebuild -workspace Rebirth.xcworkspace -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- [ ] 手动回归：派对页、搜索页、房间公屏、座位列表、个人主页列表。

## Follow-Up Notes

- `UITableView Adapter` 已按独立 Table DSL 完成首版实现，不混入 collection adapter 迁移。
- Rebirth app 内直接管理的 UITableView 页面已迁移到 `TableListAdapter`；`SwipeCellKit` 会话列表按 app-side bridge 保留。
- 宏探索继续放入 P2，避免一次改动过大。
- 当前增强实现保持 UIKit 相关 API 在 `@MainActor` 使用路径上执行。
- 业务 model 仍不需要 conform ListKit 协议；带 model 事件重载不会额外要求 model conform `Sendable`。
