# 统一 GridLayout 复查与修复

日期：2026-10-29。复查重点：尺寸计算、group 分页、旧布局迁移。默认 alignment 仍为 start。未提交、未推送，保留复查前的未提交修改。

> 后续更新：第 3 项的提前拒绝已由独立 elementKind 与 indexPath 映射实现替代；当前能力、精确动态分页限制及新证据见 [自适应 Grid 徽标验证](Measured-Grid-Badges.md)。本页保留当时的修复与失败记录。

## 确认的问题与处理

1. **固定 frame 未完整占位。** 固定轨道为 80、frame 为 220 时，原 top group 仍只有 80，后续 section 提前出现。增加固定交叉尺寸的外层 group，在内部保留轨道尺寸与 start/center/end 对齐。轨道及间距超过固定 frame 时提前诊断。
2. **estimatedFrame 与宽高比错误组合。** 原实现使用交叉轴估算值计算固定主轴尺寸，后续测量后比例不再成立。现在拒绝 estimatedFrame + aspectRatio（包括默认正方形）；需显式指定不依赖最终交叉尺寸的 itemSize。
3. **badge + 自适应主轴 + 多基本单元 group 重叠。** UIKit 的 subitem/count 结构使基本行/列沿主轴按估算值定位，cell 测量变大后重叠。单声明 subitems 自动重复虽然能测量，但会丢失指定 count 和组内间距语义。当前在 adapter 构建前拒绝这个组合，并给出 invalidLayout 诊断。固定主轴的分页 badge、不带 badge 的 estimated/uniform 多单元 group 保持支持。需要自适应多行和 badge 同时存在时，将 badge 放在 cell 内或自行实现 CustomLayout。
4. **HorizontalLayout 整宽 group 迁移不等价。** 旧 fractionalWidth(1) 引用完整有效容器宽度，新 fractionalViewport(1) 扣除 section 主轴 inset。每侧 14 点 inset 会使每页差 28 点，累积改变后续 item 位置及停靠点。麦位 Demo 和迁移文档改用 EnvironmentLayout + 固定为当前有效容器宽度的 fit group。fractionalViewport 本身仍保留扣除 inset 的契约。

## 回归覆盖与结果

新增 GridReviewRegressionTests 共 6 项：

- 双外层方向 × 三种对齐 × 自然/分页 group 的完整 frame 占位；同时验证实际 item 未被拉伸。
- 固定 frame 容量溢出诊断。
- 双方向 estimatedFrame + aspectRatio 诊断。
- 双方向 estimated/uniform + 多基本单元 + badge 提前拒绝，且有匹配的 supplementary 内容，避免误测成缺失内容诊断。
- 不带 badge 时保留逐基本单元测量、uniform 范围、组内间距与组间间距。
- 150、240、390、600 点容器下，对比新 Grid 与旧 UIKit 横向布局的 12 个 item 位置及尺寸，包含 section inset。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 完整 ListKit 包测试 | 通过，278 项，0 失败 | `/tmp/listkit-grid-review-full.xcresult` |
| Demo 单元与 Layout Lab 手势 | 通过，49 项（44 单元 + 5 UI），0 失败、0 跳过 | `/tmp/listkit-grid-review-demo-complete.xcresult` |
| API 编译契约 | 通过，29 项（含预期编译失败） | `/tmp/listkit-grid-review-api.log` |
| DocC | 通过，无 warning/error 诊断 | `/tmp/listkit-grid-review-docs.log` |
| 真机、iOS 15/17 runtime | 未执行 | 本轮运行环境为 iPhone 17 Pro Max / iOS 26.5；最低系统 API 仅编译检查 |

Layout Lab 手势覆盖双外层方向场景、起始/居中停靠、两行三列分页与尾组。两份最终 xcresult 均已核对：0 失败、0 跳过、无 runtime warning。

麦位 Demo 的测试同时验证环境解析后的 groupExtent 为完整 390 点，停靠行为保持 continuousGroupLeadingBoundary；背景内边距及 header 检查同步覆盖环境分支。

## 失败记录与证据边界

- `review-before.xcresult`：首次 4 个复现用例失败，确认占位、宽高比校验、迁移和测量分页问题。
- `review-second.xcresult`：frame、宽高比和迁移已通过；单声明自动重复仍无法保持多单元 count，保留该失败作为拒绝此组合的依据。
- `review-third.xcresult`：新增测试编辑时缺失括号，编译失败，已修正。
- `review-fourth.xcresult`：诊断测试最初遗漏 supplementary 内容，得到缺失内容诊断；补齐内容后完整测试通过。
- `review-demo.xcresult` 与 `review-demo-final.xcresult`：迁移中 EnvironmentLayout 修饰位置、测试尝试读取 UIKit 未公开 group 属性导致编译失败，已修正。
- `review-demo-verified.xcresult`：测试夹具用模拟环境创建原生 UIKit List，引发 Incompatible layout environment；环境分支的元数据检查改为解析配置，Grid 的实际 Section 检查保留。该次运行中止，不能作为 UI 验收。

上述短名均带 `/tmp/listkit-grid-` 前缀。旧验证文档及其截图、源码指纹保留，不作为本轮源码的新验收证据。没有放宽几何容差；不支持的 UIKit 组合改为明确拒绝，未宣称已实现。

## 工作区保护

复查前所有 tracked/untracked 非忽略文件已备份至 `/var/folders/_b/4kvsp2_s0ss21dbxf2_s7bnh0000gn/T/listkit-grid-review-f8oybgb4`，含 SHA-256 清单。相对此快照的补丁和审计保存在 `/tmp/listkit-grid-review.patch`、`/tmp/listkit-grid-review-audit.json`。本次只调整上述布局、Demo、回归及对应说明，未覆盖其他修改，未暂存或提交。
