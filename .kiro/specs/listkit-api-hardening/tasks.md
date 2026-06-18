# ListKit API Hardening Tasks

- [x] Task 1: 新增本 Kiro requirements/design/tasks，并把旧优化任务的 follow-up 指向本 spec。
- [x] Task 2: 为 `CollectionListAdapter` row lookup / visible refresh API 增加失败测试。
- [x] Task 3: 实现 `indexPaths(forRowID:in:)`、`itemCount(in:)`、`scrollToLastItem(in:at:animated:)`、`reconfigureVisibleRows(forRowID:in:)`、`reloadVisibleRows(forRowID:in:)`。
- [x] Task 4: 第一批页面移除 `AppListSection/AppListCellItem`：PublicMessage、Toolbar、RoomSettings、RoomView。
- [x] Task 5: 第二批页面移除 `AppListSection/AppListCellItem`：Community、Profile、Explore、Search 相关残留。
- [x] Task 6: 删除 `Rebirth/Utilities/ListKitAppMigrationSupport.swift`，更新 ListKit README。
- [x] Task 7: 运行 ListKit test/build、Rebirth build、残留搜索并记录验收结果。

## Verification

- `xcodebuild -quiet -scheme ListKit -destination 'id=714D7775-9CE5-4F6A-8036-C0B93E45FA04' test` 通过。
- `xcodebuild -quiet -scheme ListKit -destination 'generic/platform=iOS Simulator' build` 通过。
- `xcodebuild -quiet -workspace Rebirth.xcworkspace -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` 通过。
- `rg -n "AppListSection|AppListCellItem|AnyAppListCellItem|AppListSectionBuilder|ListProviderSection|ListCellProvider|ListSupplementaryProvider|AnyListCellProvider|eraseToAnyListCellProvider" Rebirth` 无命中。
- `rg -n "CollectionViewController|CollectionViewSectionType|CollectionViewCellItem|CollectionViewSupplementary|CellItemsBuilder|SectionsBuilder" Rebirth Rebirth.xcodeproj/project.pbxproj AGENTS.md CLAUDE.md` 无命中。
- `rg -n "dequeueReusableCell\\(withCellClass:|dequeueReusableSupplementaryView\\(ofKind:.*withViewClass" Rebirth` 仅剩 FSPagerView 场景。
- `git diff --check` 通过。
