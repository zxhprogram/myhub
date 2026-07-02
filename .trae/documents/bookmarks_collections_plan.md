# 书签自定义收藏夹功能实现计划

## 背景与目标

当前书签页面右侧边栏的 `_CollectionsSection` 仅包含静态 mock 数据，无法创建、编辑、删除收藏夹，也无法将书签加入收藏夹。本计划旨在实现完整的自定义收藏夹功能，包括收藏夹 CRUD、书签与收藏夹的关联管理、收藏夹排序/筛选，以及前后端持久化。

## 方案概述

- 收藏夹与书签采用**多对多**关系：一个收藏夹可包含多个书签，一个书签可属于多个收藏夹。
- 数据模型新增 `Collection` / `CollectionModel`，并在 `Bookmark` / `BookmarkModel` 中新增 `collectionIds` 字段。
- 后端新增 `/collections` 路由族，前端新增 `CollectionRepository` 与 `CollectionsState`。
- UI 复用现有设计系统组件（`NexusButton`、`NexusInput`、`NexusCard` 等），在书签页面侧边栏改造 `_CollectionsSection`。

## 关键文件

### 后端
- `nexus_hub_api/lib/database.dart`：新增 `collections` 表与 `bookmark_collections` 关联表
- `nexus_hub_api/lib/models/collection.dart`：新建 Collection 领域模型
- `nexus_hub_api/lib/models/bookmark.dart`：增加 `collectionIds` 序列化
- `nexus_hub_api/routes/collections/index.dart`：GET /collections、POST /collections
- `nexus_hub_api/routes/collections/[id].dart`：GET/PUT/DELETE /collections/:id
- `nexus_hub_api/routes/collections/[id]/bookmarks/index.dart`：GET/POST /collections/:id/bookmarks
- `nexus_hub_api/routes/collections/[id]/bookmarks/[bookmarkId].dart`：DELETE /collections/:id/bookmarks/:bookmarkId
- `nexus_hub_api/routes/bookmarks/index.dart`：返回书签时聚合 `collectionIds`
- `nexus_hub_api/routes/bookmarks/[id].dart`：同上

### 前端
- `nexus_hub_app/lib/data/services/local_database.dart`：升级版本到 5，新增两张表
- `nexus_hub_app/lib/data/models/collection_model.dart`：新建
- `nexus_hub_app/lib/data/models/bookmark_model.dart`：新增 `collectionIds`
- `nexus_hub_app/lib/data/repositories/collection_repository.dart`：新建
- `nexus_hub_app/lib/data/repositories/bookmark_repository.dart`：处理 `collectionIds` 缓存
- `nexus_hub_app/lib/presentation/states/collections_state.dart`：新建
- `nexus_hub_app/lib/presentation/states/bookmarks_state.dart`：增加按收藏夹过滤
- `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart`：改造侧边栏、添加管理弹窗、为书签卡片增加收藏夹入口

## 数据库 Schema

### collections
```sql
CREATE TABLE IF NOT EXISTS collections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

### bookmark_collections
```sql
CREATE TABLE IF NOT EXISTS bookmark_collections (
  bookmark_id INTEGER NOT NULL,
  collection_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (bookmark_id, collection_id),
  FOREIGN KEY (bookmark_id) REFERENCES bookmarks (id) ON DELETE CASCADE,
  FOREIGN KEY (collection_id) REFERENCES collections (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_bookmark_collections_collection_id
  ON bookmark_collections(collection_id);
```

> 注意：SQLite 默认外键关闭，需在数据库连接后执行 `PRAGMA foreign_keys = ON;`。

## API 设计

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/collections` | 列出收藏夹，支持 `?sort=name` / `?sort=createdAt` / `?order=asc` |
| POST | `/collections` | 创建收藏夹，`{ "name": "Read Later" }` |
| GET | `/collections/:id` | 获取单个收藏夹 |
| PUT | `/collections/:id` | 重命名收藏夹，`{ "name": "New Name" }` |
| DELETE | `/collections/:id` | 删除收藏夹 |
| GET | `/collections/:id/bookmarks` | 获取收藏夹下的书签 |
| POST | `/collections/:id/bookmarks` | 批量添加书签，`{ "bookmarkIds": [1, 2] }` |
| DELETE | `/collections/:id/bookmarks` | 批量移除书签，`{ "bookmarkIds": [1, 2] }` |

书签响应示例：
```json
{
  "id": 1,
  "title": "Flutter",
  "url": "https://flutter.dev",
  "tags": ["dev"],
  "category": "framework",
  "image": "",
  "sortOrder": 0,
  "collectionIds": [2, 5],
  "createdAt": "2026-07-02T...",
  "updatedAt": "2026-07-02T..."
}
```

## 前端状态管理

- `CollectionsState`：管理收藏夹列表、加载/错误状态、排序方式，提供 `load/create/rename/delete/setSort`。
- `BookmarksState`：新增 `selectedCollectionId` signal 与 `filterByCollection` 方法，按收藏夹过滤书签。
- 关系维护通过 `CollectionRepository.addBookmarksToCollection` / `removeBookmarksFromCollection` 实现。

## UI 改动

1. **侧边栏 `_CollectionsSection`**
   - 从静态 mock 改为读取 `CollectionsState`
   - 显示真实收藏夹名称与书签数量
   - 点击收藏夹过滤主区域
   - 右上角新增管理入口按钮

2. **`ManageCollectionsDialog`**
   - 创建收藏夹
   - 重命名收藏夹
   - 删除收藏夹（二次确认）
   - 排序切换（名称升序/降序、创建时间升序/降序）

3. **`AddToCollectionDialog`**
   - 多选列表展示所有收藏夹
   - 将书签加入/移除收藏夹

4. **书签卡片**
   - 悬浮操作栏增加“加入收藏夹”按钮
   - 显示所属收藏夹的小标签

## 测试计划

### 后端
- `test/collection_test.dart`：Collection 模型序列化
- `test/routes/collections_test.dart`：创建、重命名、删除、关联管理、404/409 边界
- 数据库迁移测试：内存数据库运行 `_migrate` 验证新表存在

### 前端
- `test/data/collection_repository_test.dart`：API 优先 + 本地 fallback
- `test/data/bookmark_repository_test.dart`：补充 `collectionIds` 解析
- 可选 widget 测试：管理弹窗创建/删除、侧边栏过滤

### 边界情况
- 空名称收藏夹 → 400
- 重命名冲突 → 409
- 删除收藏夹仅解除关系，不删除书签
- 网络中断时本地操作成功

## 实施顺序

1. 后端 schema + Collection model + `/collections` 路由
2. 后端增强 bookmark 响应 `collectionIds`
3. 前端本地数据库升级 + 模型扩展
4. 前端 `CollectionRepository` + `CollectionsState`
5. 前端侧边栏改造 + 管理收藏夹弹窗
6. 前端书签卡片增加收藏夹入口与标签
7. 运行 analyzer、测试与构建验证

## 验证方式

- `dart analyze`（后端）无错误
- `dart test`（后端）全部通过
- `flutter analyze`（前端）无错误
- `flutter build windows --debug` 成功
- 启动应用验证收藏夹创建、编辑、删除、书签关联、过滤功能
