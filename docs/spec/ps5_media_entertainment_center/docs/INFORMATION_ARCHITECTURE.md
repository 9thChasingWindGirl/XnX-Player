# 信息架构与页面地图

## 1. 顶层导航建议

建议采用主机式横向主导航，避免传统桌面软件的密集工具栏：

- Home：继续观看、最近添加、精选、推荐和快捷入口
- Movies：电影库
- Series：剧集库
- Collections：合集、系列、专题
- People：演员、导演及制作人员（可作为详情页内入口，未必需要常驻一级导航）
- Search：全局搜索
- Settings：系统与媒体设置

如果用户拥有多个媒体源或多个媒体库，可在 Home 或 Library 顶部提供来源切换，不要把服务端管理概念暴露为主要导航。

## 2. 页面地图

```text
App Shell
├── Home
│   ├── Continue Watching
│   ├── Recently Added
│   ├── Recommended
│   ├── Featured Collections
│   └── Library Shortcuts
├── Movies
│   ├── Movie Browse
│   ├── Filters / Sort
│   └── Movie Detail
├── Series
│   ├── Series Browse
│   ├── Series Detail
│   │   ├── Season Selector
│   │   └── Episode List
│   └── Episode Detail (optional)
├── Collections
│   ├── Collection Browse
│   └── Collection Detail
├── People
│   └── Person Detail
├── Search
│   ├── Search Results
│   └── Search Suggestions
├── Player
│   ├── Playback OSD
│   ├── Audio / Subtitle Menus
│   ├── Chapters
│   ├── Playback Queue
│   └── Playback Information
├── Global Control Center
├── Notifications
└── Settings
    ├── Playback
    ├── Audio
    ├── Subtitles
    ├── Display
    ├── Library
    ├── Sources
    ├── Input / Controller
    └── About / Diagnostics
```

## 3. 首页内容架构

首页不应只是海报网格。建议采用可配置的内容 Shelf：

1. Hero Feature：一部精选作品或用户正在观看的内容。
2. Continue Watching：带进度的横向卡片架。
3. Recently Added：最近入库内容。
4. Next Up：待观看下一集。
5. Recommended for You：推荐内容。
6. Collections：系列、导演专题或自定义合集。
7. Recently Played：最近播放记录。

每个 Shelf 可独立加载、隐藏、排序；空 Shelf 不应留下巨大空白。

## 4. 导航与返回

- 详情页进入播放后，返回应回到原详情页，并恢复原滚动位置和焦点。
- 从媒体库进入详情再返回，应恢复筛选、排序、滚动偏移和焦点项。
- 控制中心、菜单和 Dialog 属于 Overlay，不应无故创建新的主页面栈。
- 搜索结果进入详情后返回，应保留查询词和结果位置。
- 明确区分 Back（返回上一层）、Close（关闭当前 Overlay）和 Home（回到首页）。
