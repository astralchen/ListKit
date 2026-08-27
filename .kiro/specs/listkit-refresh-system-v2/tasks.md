# ListKit Refresh System V2 Tasks

- [x] 新增 Row 与 Supplementary 正交刷新类型，删除旧 policy 和 apply 级策略。
- [x] 迁移节点快照和共享 planner，加入 Section reload 覆盖与动作优先级。
- [x] 收敛 `ListRefreshMetrics`、`ListApplySummary` 和 `ListRefreshSummary`。
- [x] 用共享 scheduler 统一 apply、Row、Section 和 reloadAll 排队。
- [x] 保存 per-subscriber 目标/action，并接入 async cancellation bridge。
- [x] 分离 visible 与 allMatching UIKit 后端，汇总单次显式布局。
- [x] 保留 Collection outline 当前 expansion state。
- [x] 开放 RowGroup/TableRowGroup 与 Section 只读存储。
- [x] 将 LiveRoom Mic/Gift 改为幂等单向事件流。
- [x] 迁移仓库测试调用点并新增非 `@testable import` 公共 API 编译测试。
- [x] 同步 README、中文 Swift Doc 和 `.kiro/specs`。
- [ ] 完成 Simulator XCTest、UI 流程和 Demo 运行时验收，并记录环境阻塞边界。
