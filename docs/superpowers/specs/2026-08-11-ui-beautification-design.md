# Nexus Hub UI 美化设计规范

## 1. 背景与目标

在不影响任何业务功能、路由、状态管理的前提下，对 Nexus Hub 进行全局视觉美化。保持现有 macOS 桌面风格（Dock + 多窗口 + 桌面图标），但提升材质层次、一致性、微交互动效，并引入 Light / Dark / Auto 三套主题。

## 2. 设计原则

- **克制**：不过度使用渐变、阴影、动画，保持生产力工具的高效感。
- **一致**：所有页面共享同一套颜色、圆角、间距、字体、阴影。
- **层次**：通过背景色、边框、半透明、模糊区分空间层级。
- **反馈**：悬停、按下、聚焦、加载状态都有清晰但不打扰的动效。

## 3. 主题系统

### 3.1 模式

- **Light**：清爽蓝灰，参考 `Design/nexus_hub/DESIGN.md`。
- **Dark**：深空蓝紫，保护视力，与现有桌面渐变背景更协调。
- **Auto**：跟随系统 `MediaQuery.platformBrightnessOf(context)`。

### 3.2 实现

- 在 `theme/colors.dart` 中新增 `NexusColorScheme` 数据类，包含 light / dark 两套完整色板。
- `NexusColors` 保持向后兼容，但标记为基于当前主题的解析入口（通过 `NexusColors.of(context)` 或继续保留静态 light 值供无 context 处使用）。
- `NexusAppTheme` 增加 `dark()` 方法，与 `light()` 对称。
- `app.dart` 中 `MaterialApp.router` 增加 `darkTheme` 与 `themeMode`。
- 新增 `ThemeState`（单例，基于 `shared_preferences` 持久化 `themeMode`），在桌面菜单栏和移动 TopAppBar 提供切换入口。
- `NexusTypography` 中的颜色不再硬编码，改为通过 `ColorScheme` 解析；保留字体家族、字号、行高、字距。

### 3.3 色板（关键色）

**Light**

| Token | 色值 | 用途 |
|-------|------|------|
| background | `#F8F9FF` | 页面背景 |
| surface | `#FFFFFF` | 卡片、窗口内容区 |
| surfaceContainerLow | `#EFF4FF` | 输入框背景、侧边栏背景 |
| surfaceContainer | `#E5EEFF` | 悬停态、次级容器 |
| surfaceContainerHigh | `#DCE9FF` | 选中态、拖拽高亮 |
| onSurface | `#0B1C30` | 主文本 |
| onSurfaceVariant | `#45464D` | 次级文本、图标 |
| primary | `#000000` | 主按钮、标题栏图标 |
| secondary | `#0058BE` | 强调色、链接、趋势 |
| outline | `#76777D` | 聚焦边框 |
| outlineVariant | `#C6C6CD` | 分隔线、卡片边框 |

**Dark**

| Token | 色值 | 用途 |
|-------|------|------|
| background | `#0B1020` | 页面背景 |
| surface | `#151B2E` | 卡片、窗口内容区 |
| surfaceContainerLow | `#1B2238` | 输入框背景 |
| surfaceContainer | `#232B45` | 悬停态 |
| surfaceContainerHigh | `#2C3654` | 选中态 |
| onSurface | `#EAF1FF` | 主文本 |
| onSurfaceVariant | `#9AA3B8` | 次级文本、图标 |
| primary | `#FFFFFF` | 主按钮 |
| secondary | `#4A9EFF` | 强调色 |
| outline | `#6B7280` | 聚焦边框 |
| outlineVariant | `#2E3A57` | 分隔线、卡片边框 |

## 4. 全局 Shell

### 4.1 桌面背景

- Light：柔和的蓝灰径向渐变（中心亮、边缘暗），不干扰白色窗口。
- Dark：保留现有深空蓝紫渐变，但稍微降低饱和度避免刺眼。
- 用户自定义壁纸保持原有逻辑，仅在其上叠加一层按主题变化的暗色/亮色遮罩，保证文字可读性。

### 4.2 Dock

- 背景使用 `BackdropFilter` 模糊，颜色改为基于主题的 `surface` 带 18% 透明度。
- 边框使用 `outlineVariant` 带 20% 透明度，圆角 22px。
- 图标悬停放大从 48 → 56，动画时长 120ms，曲线 `Curves.easeOutCubic`。
- 活跃指示点使用主题主色，增加呼吸动画（持续 2s，透明度 0.6 ↔ 1.0）。
- 标签提示背景使用 `inverseSurface` 80% 透明度 + 模糊，文字 `inverseOnSurface`。
- 窗口预览卡片使用主题 surface，交通灯颜色保持不变。

### 4.3 菜单栏

- 高度保持 32px，背景改为基于主题的半透明模糊。
- Light：白色 20% 透明度；Dark：黑色 25% 透明度。
- 时钟字体使用 `NexusTypography.labelMd`，增加日期与时间的间距。
- 右侧增加主题切换图标、通知图标，与左侧 Apple 图标/应用名形成平衡。

### 4.4 窗口

- 窗口背景使用主题 `surface`。
- 标题栏高度 32px，背景 `surfaceContainerLow`。
- 交通灯按钮增加悬停状态：红/黄/绿各自显示对应符号（× / − / +），透明度 0 → 1，时长 150ms。
- 窗口阴影在 Light 下更柔和（0 8 24 rgba(0,0,0,0.08)），Dark 下更收敛（0 8 24 rgba(0,0,0,0.25)）。
- 窗口圆角统一 12px。
- 窗口聚焦时标题栏文字变深/变亮，非聚焦时 `onSurfaceVariant`。

### 4.5 桌面图标

- 文件夹背景使用 `surface` 带 15% 透明度 + 边框，悬停时提升到 30%。
- 应用图标选中态增加主题色光晕，替代当前固定的渐变色光晕。
- 文字阴影在 Light 下减弱，Dark 下保持。

## 5. 组件库

### 5.1 NexusCard

- Light：白色背景，1px `outlineVariant` 边框，圆角 `xl`（16px），阴影 `0 2 8 rgba(0,0,0,0.04)`。
- Dark：`surface` 背景，`outlineVariant` 边框，阴影 `0 2 8 rgba(0,0,0,0.16)`。
- 可点击卡片悬停时背景升层到 `surfaceContainerLow`，阴影加深，过渡 150ms。
- 默认内边距保持 16px，header 区域支持 icon + title + action 的标准结构。

### 5.2 NexusButton

- `filled`：主题 `primary` 背景，`onPrimary` 文字，无阴影，按下时缩放 0.98。
- `tonal`：`secondaryContainer` 背景，`onSecondaryContainer` 文字。
- `outlined`：透明背景，`outlineVariant` 边框，悬停时背景填充 `surfaceContainerLow`。
- `text`：透明背景，悬停时背景填充 `surfaceContainerLow`。
- 所有变体统一圆角 8px，高度 36px，图标与文字间距 8px。
- Loading 状态保留现有指示器，但颜色随主题变化。

### 5.3 NexusInput

- 背景 `surfaceContainerLow`，Light 下边框 1px `outlineVariant`，Dark 下默认无边框。
- 聚焦时边框颜色 `secondary`，并添加 2px 外发光（`secondary` 20% 透明度）。
- 圆角 8px，内边距 12px 水平 / 10px 垂直。
- 错误状态边框 `error`，提示文字 `error`。
- 占位符颜色 `onSurfaceVariant` 60% 透明度。

### 5.4 NexusChip / NexusBadge

- Chip：小圆角胶囊形，背景 `surfaceContainer`，文字 `onSurfaceVariant`，可选选中态 `secondaryContainer` + `onSecondaryContainer`。
- Badge：小号圆角矩形，背景 `surfaceContainerHigh`，文字 `onSurface`，增加 1px 边框避免与背景融合。

### 5.5 NexusIcon

- 默认颜色 `onSurfaceVariant`，尺寸规范化为 16/20/24 三档。
- 支持主题感知：active 状态使用 `onSurface` 或 `secondary`。

## 6. 页面美化策略

所有页面遵循以下统一改造：

1. **PageScaffold**：根据主题切换背景色，内容区最大宽度 1440px 并居中，保持 24px 外边距。
2. **标题区**：页面标题使用 `headlineXl`，副标题 `bodyMd` + `onSurfaceVariant`。
3. **卡片布局**：优先使用 12 列网格思想，卡片间距 16px，宽屏下多列、窄屏下堆叠。
4. **列表项**：统一悬停背景 `surfaceContainerLow`，选中背景 `surfaceContainerHigh`，过渡 100ms。
5. **空状态**：提供主题感知的插画占位（使用 Lucide 大图标 + 柔和颜色 + 提示文字 + 操作按钮）。
6. **具体页面重点**：
   - **Dashboard**：Metric 卡片增加图标和进度条感；Focus Hours 改为更平滑的柱状图；Quick Actions 按钮间距统一。
   - **Tasks**：看板列头部增加计数徽章；任务卡片增加标签、截止日期、头像；拖拽时增加阴影和缩放。
   - **Bookmarks**：卡片网格增加 favicon 占位、悬停遮罩、收藏心形按钮。
   - **Mail**：邮件列表增加未读指示、悬停快捷操作；阅读区使用更舒适的行高。
   - **RSS / Clipboard / Stocks / DevTools / My Computer**：统一卡片、列表、输入框、按钮风格，增加空状态。
   - **AI Chat**：输入框固定在底部，消息气泡使用 `surfaceContainerLow` 和 `secondaryContainer` 区分用户/AI。
   - **Pomodoro / Terminal / Camera / Calendar / Trending**：保证主题切换后无 hard-coded 颜色，按钮和面板使用主题组件。

## 7. 不动范围

- 不修改业务逻辑、API 调用、数据模型、路由结构。
- 不改变桌面端 macOS 交互范式（Dock、窗口、桌面图标）。
- 不引入新的依赖（仅使用现有 `flutter/material`、`shadcn_flutter`、平台能力）。
- 不删除现有组件的 public API，只调整内部实现与默认样式。

## 8. 验收标准

- [ ] 应用可在 Light / Dark / Auto 三种主题间切换，切换后无 hard-coded 颜色残留。
- [ ] 桌面端 Dock、菜单栏、窗口、桌面图标在两种主题下均视觉协调。
- [ ] 移动端底部导航和 TopAppBar 在两种主题下均视觉协调。
- [ ] 所有页面卡片、按钮、输入框、列表、空状态风格统一。
- [ ] 原有功能（打开窗口、拖拽图标、壁纸切换、任务看板、邮件、RSS 等）完全可用。
- [ ] `flutter analyze` 无新增错误，`flutter test` 现有测试全部通过。
