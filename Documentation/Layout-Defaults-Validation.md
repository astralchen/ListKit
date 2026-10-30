# 布局默认值调整与验证

> 后续间距 API 已统一：删除 gridSpacing，groupLineSpacing 改为 lineSpacing，groupSpacing 改为可选覆盖（nil 跟随 lineSpacing）。下文为当时的实现与验证记录；当前契约见 [布局指南](Layout-API.md#滚动与间距)。

日期：2026-10-29。按明确选择，将 Grid 的 item 主轴尺寸默认改为 estimated(44)，三层间距默认均改为 0。未提交或推送。当前用法见 [布局指南](Layout-API.md#入口与默认值)。

## 当时契约（当前间距 API 已更新）

```swift
public var itemMainAxisSize: ListGridItemMainAxisSize = .estimated(44)
public var trackSpacing: CGFloat = 0
public var groupLineSpacing: CGFloat = 0
public var groupSpacing: CGFloat = 0
```

整数轨道、轨道定义数组、横向/纵向内容使用同一默认配置。44 是初始主轴估算值，纵向为高度、横向为宽度，最终依赖 cell 的 self-sizing；它不是固定尺寸。正方形显式使用 itemMainAxisSize(.aspectRatio(1))。默认 estimated 仍遵守已有分组限制，不自动兼容 fitting 或显式 group 主轴长度。

ListGridTrack.spacingAfter 为 nil 时继承零轨道间距，内部轨道 resolver 默认间距同步改为 0。显式 gridSpacing 和三层独立间距继续按后一次调用覆盖，轨道 spacingAfter 的显式覆盖仍有效。

未声明布局/空分支的回退简化为 GridLayout(tracks: 1)，与显式单轨道默认布局一致。回退原本就是 estimated(44) 和零间距，其运行契约不变。

## 示例、文档和测试

- README、当前 Markdown/DocC 指南、公开 API 注释同步说明 estimated(44)、零间距及 self-sizing 前提。
- Layout Lab 的 Tags 场景使用默认 estimated(44)，实际尺寸仍由 cell 测量；图片网格等显式尺寸和显式间距保持原样。
- 新增 GridDefaultsTests：两种 tracks 入口的默认值、默认回退一致性、单轨道估算交叉轴不再与默认 aspectRatio 冲突，以及四种方向/正交组合下轨道、组内行/列、组间均无默认间隔。
- 新增默认尺寸真实测量与 reload 回归：横纵两方向 × 有/无 inset，实际 item 主轴测量为 40/110 点，内容变化后更新为 170 点，再缩短为 30/35/45/50 点，证明 44 并非固定值。
- Dynamic Type 测试直接使用默认策略，继续覆盖单/双轨道字体放大后的实际尺寸与后续行位置。
- 正方形几何用例显式声明 aspectRatio(1)，保留原宽高相等、补充视图位置和吸附断言；布局失效用例按零组内间距验证 group 起点为 80×2+30=190。

## 验证记录

环境为 Xcode 27.1（27A9275），iPhone 17 Pro Max / iOS 26.5 Simulator，arm64。最低部署目标 iOS 15。

- 最终全部库测试：293 项通过，0 失败、0 跳过；`/tmp/listkit-defaults-final.xcresult`。
- iOS 15 / Swift 6 编译契约：77 项通过（17 正例、60 预期拒绝）；`/tmp/listkit-defaults-contract.log`。
- 示例单元与选定 UI：46 项通过（44 单元 + 2 UI），0 失败、0 跳过；`/tmp/listkit-defaults-demo.xcresult`。UI 覆盖网格模式/容器宽度/空内容，以及 5 个正交场景 × 两种外层方向，包括使用默认 estimated(44) 的 Tags。未重跑另外 3 个 Layout Lab UI 用例。
- DocC 编译通过，无 warning/error；`/tmp/listkit-defaults-docs.log`。

首次完整库测试 `/tmp/listkit-defaults-first.xcresult` 保留失败证据：293 个测试中，3 个测试仍依赖旧默认值，共触发 32 条断言失败。两项仍把默认 item 当作正方形，另一项仍期待 8 点组内间距。修复测试配置与预期后重新运行；未放宽几何容差或删除行为断言。新默认值回归在首次运行中已通过。

操作前备份、SHA-256 清单与本轮增量差异位于 `/tmp/listkit-default-estimated-mnm8_8w9/`。原有无关改动保留；历史报告中的旧默认值代表当时实现，不作为当前 API 参考。本轮未运行真机或 iOS 15/iOS 17 runtime。

最终当前文档相对链接有效，Markdown 与 DocC 布局指南内容一致，`git diff --check` 通过。
