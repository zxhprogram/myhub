# 书签自定义 Collections 功能收尾计划

## 1. 概要

当前书签页面的 Collections 核心 UI、后端 API、本地数据库模型与仓库层已基本实现。本计划旨在完成剩余收尾工作：修复级联删除测试失败、统一前后端排序协议、修复本地缓存中书签 ID 与会话关系不一致的问题、补充加载与成功/失败反馈、并在修改收藏关联后刷新书签列表，最后补充前后端测试。

## 2. 当前状态分析

### 2.1 已完成的实现

- **后端**
  - `nexus_hub_api/lib/database.dart` 已新增 `collections` 与 `bookmark_collections` 表，并配置 `ON DELETE CASCADE`。
  - `nexus_hub_api/lib/models/collection.dart` 已定义 `Collection` 模型及 `copyWith`。
  - `nexus_hub_api/routes/collections/index.dart` 实现 Collections 列表（GET）与创建（POST）。
  - `nexus_hub_api/routes/collections/[id].dart` 实现单个 Collection 查询、重命名、删除。
  - `nexus_hub_api/routes/collections/[id]/bookmarks/index.dart` 实现查询/添加书签到收藏集。
  - `nexus_hub_api/routes/collections/[id]/bookmarks/[bookmarkId].dart` 实现从收藏集移除书签。
  - `nexus_hub_api/routes/bookmarks/index.dart` 与 `[id].dart` 已在响应中附带 `collectionIds`。
  - 已存在 `test/collection_test.dart` 与 `test/routes/collections_test.dart`。

- **前端**
  - `nexus_hub_app/lib/data/models/collection_model.dart` 与 `bookmark_model.dart` 已支持 `collectionIds`。
  - `nexus_hub_app/lib/data/services/local_database.dart` 版本已升级到 5，已创建对应表。
  - `nexus_hub_app/lib/data/repositories/collection_repository.dart` 已提供 CRUD 及书签关联管理，并带离线兜底。
  - `nexus_hub_app/lib/presentation/states/collections_state.dart` 已提供加载、创建、重命名、删除、排序、添加/移除书签方法。
  - `nexus_hub_app/lib/presentation/states/bookmarks_state.dart` 已支持按收藏集筛选。
  - `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart` 已包含：
    - 侧边栏收藏集列表（含计数）
    - 管理收藏集弹窗（创建、重命名、删除确认、排序切换）
    - 书签卡片/列表行显示所属收藏集徽章
    - “Add to Collection”弹窗，支持勾选/取消收藏集

### 2.2 需要修复的问题

| 问题 | 影响 | 相关文件 |
|------|------|----------|
| `DELETE /collections/:id` 测试期望关联表记录为 0，实际为 1 | 后端测试失败；生产环境若外键未生效会残留脏数据 | `nexus_hub_api/routes/collections/[id].dart` |
| 前端 `fetchCollections` 使用 `sort=name_asc` 等单参数，后端只识别 `sort`/`order` 两个参数 | 后端排序实际退化为默认排序，线上线下表现不一致 | `nexus_hub_api/routes/collections/index.dart` |
| `BookmarkRepository._insertLocal` 未写入 `id` | 每次同步后本地书签 ID 被重新生成，与 `bookmark_collections` 中的 `bookmark_id` 不一致，导致离线按收藏集筛选查不到数据 | `nexus_hub_app/lib/data/repositories/bookmark_repository.dart` |
| `CollectionRepository._loadCachedBookmarksInCollection` 返回的模型缺少 `collectionIds` | 离线/缓存状态下收藏集徽章与弹窗勾选状态丢失 | `nexus_hub_app/lib/data/repositories/collection_repository.dart` |
| Collection 操作没有明显的成功/失败反馈；弹窗内无加载指示 | 用户体验不符合需求中“适当的加载状态提示、成功/失败反馈” | `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart`、`collections_state.dart` |
| 在“Add to Collection”弹窗保存后，书签卡片的收藏集徽章不会立即刷新 | 用户保存后看不到即时反馈 | `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart` |

### 2.3 需要补充的测试

- 前端 `CollectionRepository` 单元测试（创建、重命名、删除、添加/移除书签、缓存回退）。
- 更新 `BookmarkModel`/`CollectionModel` 测试以覆盖 `collectionIds` 序列化与 `copyWith`。
- 后端 Collections 路由增加排序参数测试。

## 3. 具体改动计划

### 3.1 后端：显式清理收藏集关联后再删除收藏集

**文件：** `nexus_hub_api/routes/collections/[id].dart`

**修改内容：** 在 `DELETE` 分支中，先执行：

```dart
db.execute('DELETE FROM bookmark_collections WHERE collection_id = ?', [collectionId]);
```

再执行原 `DELETE FROM collections WHERE id = ?`。

**原因：** 即使数据库已声明 `ON DELETE CASCADE`，测试环境或某些部署中若外键未生效，显式删除关联行可保证行为确定，并解决当前测试 `Expected: <0> Actual: <1>` 的失败。

### 3.2 后端：统一 Collections 排序参数

**文件：** `nexus_hub_api/routes/collections/index.dart`

**修改内容：** 将 `sort` 查询参数解析扩展为支持：

- `name_asc` -> `name ASC`
- `name_desc` -> `name DESC`
- `created_asc` -> `created_at ASC`
- `created_desc` -> `created_at DESC`
- 其他/空 -> `sort_order ASC, name ASC`

保留对旧 `sort`+`order` 的兼容或直接用新格式；推荐统一为新格式。

**原因：** 与 `CollectionRepository.fetchCollections` 和 `_orderByClause` 的命名保持一致，避免线上线下排序结果不同。

### 3.3 前端：缓存书签时保留原 ID

**文件：** `nexus_hub_app/lib/data/repositories/bookmark_repository.dart`

**修改内容：** 在 `_insertLocal` 的插入 Map 中增加 `'id': bookmark.id`，并改用 `conflictAlgorithm: ConflictAlgorithm.replace`。

**原因：** 后端返回的书签带有真实 ID，本地 `bookmark_collections` 的 `bookmark_id` 依赖这些 ID；若本地重新生成，会导致关联查询失效。

### 3.4 前端：离线缓存的收藏集书签补全 `collectionIds`

**文件：** `nexus_hub_app/lib/data/repositories/collection_repository.dart`

**修改内容：** 在 `_loadCachedBookmarksInCollection` 返回的每个 `BookmarkModel` 上设置 `collectionIds: [collectionId]`。

**原因：** 离线时无法从后端获取完整关联，但既然查询是按某个收藏集过滤，可确定该书签至少属于该收藏集。

### 3.5 前端：操作反馈与加载状态

**文件：** `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart`

**修改内容：**

1. 在 `_BookmarksPageState` 中监听 `_collectionsState.error` 与 `_state.error`，通过 `ScaffoldMessenger` 显示 `SnackBar`。
2. 在 `_ManageCollectionsDialog` 中使用 `Watch` 监听 `collectionsState.isLoading`，当加载时显示半透明遮罩 + `CircularProgressIndicator`。
3. 在 `_AddToCollectionDialog` 的保存按钮上，保存期间显示小型加载指示并禁用按钮。

**原因：** 满足需求中的加载提示与成功/失败反馈，避免用户重复点击。

### 3.6 前端：收藏关联修改后刷新书签列表

**文件：** `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart`

**修改内容：** 将 `_state`（`BookmarksState`）传入 `_AddToCollectionDialog`；在弹窗保存逻辑结束后调用 `_state.load()`（如果当前已按收藏集筛选，则 `load()` 会重新拉取该收藏集数据）。

**原因：** 使书签卡片上的收藏集徽章与侧边栏计数在保存后立即更新。

### 3.7 测试补充

**新增文件：**

- `nexus_hub_app/test/data/collection_repository_test.dart`
  - 使用内存 `sqflite` 测试创建、重命名、删除、添加/移除书签、离线回退。
- `nexus_hub_app/test/data/bookmark_model_test.dart`（若不存在则新增，否则编辑）
  - 验证 `collectionIds` 在 `fromJson`/`toJson`/`copyWith` 中正确传递。

**编辑文件：**

- `nexus_hub_api/test/routes/collections_test.dart`
  - 为 `GET /collections?sort=name_desc` 与 `sort=created_desc` 增加断言。
  - 验证 `DELETE /collections/:id` 后 `bookmark_collections` 记录为 0（当前测试已包含，修复后应通过）。

## 4. 假设与决策

- **外键兜底：** 后端 schema 已声明 `ON DELETE CASCADE`，但为兼容测试失败与潜在外键未开启的环境，选择显式先删关联。这是防御性实现，不影响正确配置的数据库。
- **排序协议：** 采用 `name_asc` / `name_desc` / `created_asc` / `created_desc` 单一参数，与前端仓库 `_orderByClause` 保持一致。
- **反馈形式：** 使用 `SnackBar` 显示错误；创建/删除成功不额外弹成功提示，而是关闭弹窗并刷新列表，保持界面简洁。若后续需要明确成功提示，可再调整。
- **离线关联补全：** 离线按收藏集筛选时，默认将目标收藏集 ID 写入返回书签的 `collectionIds`，保证徽章显示。

## 5. 验证步骤

1. 在 `nexus_hub_api` 目录运行 `dart test`，确认所有测试通过，尤其是 `DELETE /collections/:id` 测试。
2. 在 `nexus_hub_api` 目录运行 `dart analyze`，确认无静态错误。
3. 在 `nexus_hub_app` 目录运行 `flutter analyze` / `dart analyze`，确认无静态错误。
4. 在 `nexus_hub_app` 目录运行 `flutter test`，确认新增与现有测试通过。
5. 启动后端与前端的 Windows debug，进行手动端到端验证：
   - 创建、重命名、删除收藏集。
   - 将书签添加/移除收藏集，观察卡片徽章与侧边栏计数即时更新。
   - 切换排序（Name A-Z / Newest 等），观察顺序变化。
   - 模拟后端不可用时（如关闭后端），验证离线创建收藏集、添加书签到收藏集、按收藏集筛选仍能工作。
