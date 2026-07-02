# 书签自定义收藏夹功能实施计划

## 摘要

为 Nexus Hub 书签页面实现完整的自定义 Collections 功能。当前页面已存在静态的收藏夹 UI 区域，但数据为 mock；本计划将补齐后端 API、本地数据库、前端数据层、状态层与 UI 层的完整链路，实现收藏夹的创建、编辑、删除、排序/筛选，以及书签与收藏夹的关联管理。

## 当前状态分析

### 后端 (`nexus_hub_api`)

- `lib/database.dart`：已存在 `bookmarks`、`tasks`、`clipboard`、`rss_feeds`、`rss_items` 表，但缺少 `collections` 与 `bookmark_collections` 关联表。
- `lib/models/bookmark.dart`：`Bookmark` 领域模型未包含 `collectionIds`。
- `routes/bookmarks/index.dart` 与 `routes/bookmarks/[id].dart`：GET/POST/PUT/DELETE 已实现，但响应中未聚合收藏夹 ID。
- `routes/collections/`：目录不存在，需新建全部端点。
- `pubspec.yaml`：已包含 `dart_frog`、`sqlite3`、`path` 等所需依赖。

### 前端 (`nexus_hub_app`)

- `lib/data/services/local_database.dart`：当前版本为 4，仅有 `bookmarks`、`tasks`、`clipboard` 表，需升级到版本 5 并新增收藏夹相关表。
- `lib/data/models/bookmark_model.dart`：未包含 `collectionIds`。
- `lib/data/models/collection_model.dart`：文件不存在，需新建。
- `lib/data/repositories/bookmark_repository.dart`：已实现书签 CRUD 与本地缓存，但未处理 `collectionIds`。
- `lib/data/repositories/collection_repository.dart`：文件不存在，需新建。
- `lib/presentation/states/bookmarks_state.dart`：已实现加载、搜索、添加、排序，缺少按收藏夹过滤。
- `lib/presentation/states/collections_state.dart`：文件不存在，需新建。
- `lib/presentation/pages/bookmarks_page.dart`：`_CollectionsSection` 为静态 mock 数据，未接入真实状态；书签卡片的悬浮操作未实现编辑/删除/加入收藏夹。
- `pubspec.yaml`：已包含 `signals_flutter`、`dio`、`sqflite`、`equatable` 等所需依赖。

## 实施变更

### 阶段一：后端基础（schema + 模型 + 路由骨架）

#### 1. `nexus_hub_api/lib/database.dart`

**What**：在 `_migrate` 中新增 `collections` 表与 `bookmark_collections` 关联表，并启用外键。

**Why**：为多对多关系提供持久化存储；外键可在书签或收藏夹删除时自动清理关联。

**How**：
- 打开数据库后执行 `PRAGMA foreign_keys = ON;`。
- 创建 `collections` 表：`id`、`name UNIQUE`、`sort_order`、`created_at`、`updated_at`。
- 创建 `bookmark_collections` 表：复合主键 `(bookmark_id, collection_id)`，外键级联删除。
- 为 `bookmark_collections(collection_id)` 创建索引。

#### 2. `nexus_hub_api/lib/models/collection.dart`

**What**：新建 Collection 领域模型。

**Why**：统一后端对收藏夹数据的序列化/反序列化。

**How**：
- 字段：`id`、`name`、`sortOrder`、`createdAt`、`updatedAt`。
- 提供 `fromRow(Row)`、`toJson()`、`copyWith()`。

#### 3. `nexus_hub_api/lib/models/bookmark.dart`

**What**：在 `toJson()` 中增加 `collectionIds` 字段；保留 `fromRow` 不变（关联在查询时聚合）。

**Why**：API 响应需要告诉前端每个书签属于哪些收藏夹。

**How**：
- `toJson()` 返回 `'collectionIds': <int>[]`（由路由查询后注入）。
- 不修改构造函数，避免破坏现有书签逻辑；在路由层组装最终 JSON。

#### 4. `nexus_hub_api/routes/collections/index.dart`

**What**：实现 `GET /collections` 与 `POST /collections`。

**How**：
- `GET`：支持 `?sort=name|createdAt` 与 `?order=asc|desc`，默认按 `sort_order ASC, name ASC`。
- `POST`：请求体 `{ "name": "..." }`；校验名称非空；冲突时返回 `409 Conflict`；成功返回 `201 Created`。

#### 5. `nexus_hub_api/routes/collections/[id].dart`

**What**：实现 `GET /collections/:id`、`PUT /collections/:id`、`DELETE /collections/:id`。

**How**：
- `GET`：不存在返回 `404`。
- `PUT`：仅支持重命名，校验非空与唯一性，冲突返回 `409`。
- `DELETE`：由于外键级联，删除收藏夹会自动清空关联；返回 `204 No Content`。

### 阶段二：后端关联 API

#### 6. `nexus_hub_api/routes/collections/[id]/bookmarks/index.dart`

**What**：实现 `GET /collections/:id/bookmarks` 与 `POST /collections/:id/bookmarks`。

**How**：
- `GET`：通过 `bookmark_collections` 查询该书签夹下的书签完整信息，并注入 `collectionIds`。
- `POST`：请求体 `{ "bookmarkIds": [1, 2] }`；批量插入关联，忽略已存在项；校验收藏夹存在。

#### 7. `nexus_hub_api/routes/collections/[id]/bookmarks/[bookmarkId].dart`

**What**：实现 `DELETE /collections/:id/bookmarks/:bookmarkId`。

**How**：
- 删除指定关联；收藏夹或书签不存在不影响幂等性，返回 `204`。

#### 8. `nexus_hub_api/routes/bookmarks/index.dart` 与 `routes/bookmarks/[id].dart`

**What**：在返回书签 JSON 前聚合 `collectionIds`。

**How**：
- 新增辅助函数 `_attachCollectionIds(Database db, List<Bookmark> bookmarks)`：使用 `IN` 查询批量读取关联，避免 N+1。
- 在 GET /bookmarks、GET /bookmarks/:id、POST /bookmarks、PUT /bookmarks/:id、PUT /bookmarks（排序）响应中均注入该字段。

### 阶段三：前端数据层

#### 9. `nexus_hub_app/lib/data/services/local_database.dart`

**What**：升级数据库到版本 5，新增两张表。

**How**：
- `_open()` 中 `version: 5`。
- `_onCreate` 中增加 `collections` 与 `bookmark_collections` 建表语句。
- `_onUpgrade` 中增加 `oldVersion < 5` 分支，使用 `CREATE TABLE IF NOT EXISTS` 兼容已存在表的情况。

#### 10. `nexus_hub_app/lib/data/models/collection_model.dart`

**What**：新建收藏夹模型。

**How**：
- 字段：`id`、`name`、`sortOrder`、`createdAt`、`updatedAt`。
- 提供 `fromJson`、`toJson`、`copyWith`、`props`（继承 `Equatable`）。

#### 11. `nexus_hub_app/lib/data/models/bookmark_model.dart`

**What**：新增 `collectionIds` 字段。

**How**：
- 构造函数增加 `this.collectionIds = const []`。
- `fromJson` 解析 `collectionIds` 为 `List<int>`。
- `toJson` 输出 `collectionIds`。
- `copyWith` 支持 `collectionIds`。

#### 12. `nexus_hub_app/lib/data/repositories/collection_repository.dart`

**What**：新建收藏夹仓库，实现 API 优先 + 本地 SQLite 缓存 fallback。

**How**：
- `fetchCollections({String? sort})`：GET `/collections`；成功时写入本地；失败时读取本地缓存。
- `createCollection(String name)`：POST `/collections`；失败时本地创建临时记录（id 为自增，后续同步策略保持一致）。
- `updateCollection(int id, String name)`：PUT `/collections/:id`；同时更新本地。
- `deleteCollection(int id)`：DELETE `/collections/:id`；同时删除本地记录与关联。
- `addBookmarksToCollection(int collectionId, List<int> bookmarkIds)`：POST `/collections/:id/bookmarks`；同时写入本地关联表。
- `removeBookmarksFromCollection(int collectionId, List<int> bookmarkIds)`：DELETE `/collections/:id/bookmarks`（批量版本）或逐个 DELETE；同时删除本地关联。
- `getBookmarksInCollection(int collectionId)`：GET `/collections/:id/bookmarks`；失败时本地 JOIN 查询。
- 本地缓存方法：`_cacheCollections`、`_insertLocalCollection`、`_loadCachedCollections`、`_cacheBookmarkCollections`、`_loadCachedBookmarkIds`。

### 阶段四：前端状态层

#### 13. `nexus_hub_app/lib/presentation/states/collections_state.dart`

**What**：新建 Signals 状态管理。

**How**：
- Signals：`collections`、`isLoading`、`error`、`sort`（`'name_asc'`、`'name_desc'`、`'created_asc'`、`'created_desc'`）。
- 方法：`load()`、`create(String name)`、`rename(int id, String name)`、`delete(int id)`、`setSort(String value)`、`addBookmarks(int collectionId, List<int> bookmarkIds)`、`removeBookmarks(int collectionId, List<int> bookmarkIds)`。
- 每个异步操作均设置 `isLoading`、捕获异常写入 `error`、成功后刷新列表。

#### 14. `nexus_hub_app/lib/presentation/states/bookmarks_state.dart`

**What**：扩展以支持按收藏夹过滤。

**How**：
- 新增 `selectedCollectionId` signal（`int?`）。
- 新增 `filterByCollection(int? collectionId)` 方法。
- `load()` 与 `search()` 在请求时如 `selectedCollectionId` 不为空，则优先调用 `CollectionRepository.getBookmarksInCollection`。
- 在 `add` 成功后若该书签不属于当前选中收藏夹，则不在列表中插入。

### 阶段五：前端 UI 层

#### 15. `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart`

**What**：改造书签页面以接入真实收藏夹功能。

**How**：
- 在 `_BookmarksPageState` 中创建 `CollectionsState _collectionsState`，并在 `initState` 中调用 `load()`。
- 改造 `_CollectionsSection`：
  - 使用 `Watch` 监听 `_collectionsState.collections`。
  - 每项显示收藏夹名称与书签数量（通过本地/服务器计数）。
  - 点击项调用 `_state.filterByCollection(collection.id)` 过滤主区域。
  - 右上角 `+` 按钮改为 `IconButton` 并打开 `ManageCollectionsDialog`。
  - 增加 "All Bookmarks" 默认项重置过滤。
- 新增 `ManageCollectionsDialog`：
  - 列表展示收藏夹，每项可重命名、删除。
  - 顶部提供名称输入框与创建按钮。
  - 提供排序切换按钮组（名称/创建时间、升/降序）。
  - 删除前弹出 `AlertDialog` 二次确认。
- 新增 `AddToCollectionDialog`：
  - 展示所有收藏夹复选列表。
  - 根据书签当前所属集合初始化选中状态。
  - 点击确认批量添加/移除。
- 书签卡片改造：
  - `_BookmarkGridCard` 悬浮操作栏增加“加入收藏夹”图标按钮。
  - 编辑按钮打开编辑弹窗（复用 `_AddBookmarkDialog` 扩展）。
  - 删除按钮弹出确认对话框。
  - 在卡片底部显示所属收藏夹小标签（chips）。
- `_BookmarkListRow` 同样增加收藏夹入口与所属标签。

#### 16. `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart`（编辑弹窗）

**What**：扩展 `_AddBookmarkDialog` 支持编辑模式与收藏夹选择。

**How**：
- 新增可选 `bookmark` 参数；存在时预填充字段，标题改为 "Edit Bookmark"。
- 保存时若处于编辑模式则 PUT `/bookmarks/:id`（需新增 `BookmarkRepository.updateBookmark`）。
- 底部增加“Collections”区域，可打开 `AddToCollectionDialog`。

#### 17. `nexus_hub_app/lib/data/repositories/bookmark_repository.dart`

**What**：补充更新与删除方法，并处理 `collectionIds` 缓存。

**How**：
- 新增 `updateBookmark(BookmarkModel bookmark)`：PUT `/bookmarks/:id`；失败时更新本地。
- 新增 `deleteBookmark(int id)`：DELETE `/bookmarks/:id`；同时删除本地记录与关联。
- `_insertLocal` 与 `_rowToModel` 不再直接处理 `collectionIds`（关系由 `collection_repository` 维护）。
- `fetchBookmarks` 在 API 成功时通过返回的 `collectionIds` 更新本地 `bookmark_collections`。

### 阶段六：测试

#### 18. 后端测试

- 新建 `nexus_hub_api/test/collection_test.dart`：验证 `Collection.fromRow`、`toJson`、`copyWith`。
- 新建 `nexus_hub_api/test/routes/collections_test.dart`：
  - 使用内存数据库上下文（参考 dart_frog 测试模式）。
  - 覆盖创建成功、空名 400、重名 409、重命名、删除、添加/移除书签关联、查询收藏夹书签、404/409 边界。
- 更新 `nexus_hub_api/test/bookmark_test.dart`：验证 `toJson` 包含 `collectionIds`（空列表）。

#### 19. 前端测试

- 新建 `nexus_hub_app/test/data/collection_repository_test.dart`：
  - 使用 mock `ApiClient` 验证 API 优先与本地 fallback。
  - 验证 `createCollection`、`updateCollection`、`deleteCollection`、`addBookmarksToCollection`、`removeBookmarksFromCollection` 的本地缓存一致性。
- 更新 `nexus_hub_app/test/data/bookmark_repository_test.dart`：
  - 验证 `BookmarkModel.fromJson` 正确解析 `collectionIds`。
  - 验证 `toJson` 输出 `collectionIds`。
- 可选：新增 widget 测试验证 `ManageCollectionsDialog` 创建/删除、`AddToCollectionDialog` 选中状态。

## 假设与决策

1. **数据关系**：收藏夹与书签为多对多；删除收藏夹只解除关联，不删除书签；删除书签通过外键级联自动解除关联。
2. **唯一性**：`collections.name` 在数据库层设为 `UNIQUE`，重名请求返回 `409 Conflict`。
3. **同步策略**：API 优先，网络失败时回退到本地 SQLite；本地写入保证 UI 不阻塞。离线创建/编辑的后续同步不在本次范围内，但本地数据持久化。
4. **排序**：收藏夹支持按名称升/降序、创建时间升/降序；排序由后端根据 query 参数完成，前端状态层仅传递参数。
5. **书签数量**：侧边栏显示的书签数量优先从本地缓存计算，减少额外请求。
6. **状态管理**：复用现有 `signals_flutter` 模式；`CollectionsState` 与 `BookmarksState` 在页面内共同持有。
7. **UI 组件**：复用现有 `NexusButton`、`NexusInput` 等设计系统组件；弹窗统一使用 `AlertDialog` 包装。

## 验证步骤

1. 后端静态分析：`dart analyze`（`nexus_hub_api`）无错误。
2. 后端测试：`dart test`（`nexus_hub_api`）全部通过。
3. 前端静态分析：`flutter analyze`（`nexus_hub_app`）无错误。
4. 前端测试：`flutter test`（`nexus_hub_app`）全部通过（如遇 sqlite3 native asset 锁超时，按历史处理方式清理后重试）。
5. 构建验证：`flutter build windows --debug` 成功。
6. 运行验证：
   - 启动后端 `dart_frog dev`。
   - 启动前端，进入书签页面。
   - 创建收藏夹、重命名、删除（确认弹窗）。
   - 将书签加入/移除收藏夹。
   - 点击侧边栏收藏夹过滤主区域。
   - 切换排序方式验证顺序变化。
