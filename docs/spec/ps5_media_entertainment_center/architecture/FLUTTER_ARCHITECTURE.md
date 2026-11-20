# Flutter 应用架构

## 1. 分层建议

```text
Presentation
  Screens
  Widgets
  ViewModels / Controllers
  Design System
       |
Application
  Use Cases
  Commands
  State Coordination
       |
Domain
  Entities
  Value Objects
  Repository Interfaces
  Playback Contracts
       |
Infrastructure
  Media Server Adapters
  Local Library Scanner
  Metadata Providers
  Cache / Database
  Playback Engine Adapter
  File System / Platform APIs
```

## 2. 模块边界

- `design_system`：只负责视觉、组件和交互呈现，不访问媒体 API。
- `features/home`：组合 Shelf 和 Hero，不直接解析服务端响应。
- `features/library`：筛选、排序、分页与媒体库浏览。
- `features/details`：媒体详情、人物、系列和关联作品。
- `features/player`：播放 UI 与 PlaybackController。
- `core/focus`：统一焦点管理和空间导航策略。
- `core/navigation`：页面栈、路由和焦点恢复。
- `data`：服务端 API、缓存、媒体扫描和数据映射。
- `playback`：播放引擎适配器和统一播放状态。

## 3. 推荐目录

```text
lib/
├── app/
│   ├── app.dart
│   ├── router/
│   └── shell/
├── design_system/
│   ├── tokens/
│   ├── theme/
│   ├── primitives/
│   ├── components/
│   └── patterns/
├── core/
│   ├── focus/
│   ├── input/
│   ├── navigation/
│   ├── overlay/
│   ├── animation/
│   └── feedback/
├── features/
│   ├── home/
│   ├── movies/
│   ├── series/
│   ├── collections/
│   ├── search/
│   ├── people/
│   ├── details/
│   ├── player/
│   └── settings/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── use_cases/
├── data/
│   ├── datasources/
│   ├── dto/
│   ├── mappers/
│   ├── repositories/
│   └── cache/
└── playback/
    ├── contracts/
    ├── adapters/
    └── models/
```

## 4. 关键原则

- Widget 不应直接调用 Emby/Jellyfin/Plex API。
- 页面不应直接依赖 media_kit 的具体 Player 类型。
- DTO 与领域模型分离。
- 图片加载、认证、缓存由统一图片/媒体资源层管理。
- 焦点 ID 应稳定且可恢复。
- 主题 Token 不要散落为页面内硬编码数值。
- 不要为了目录整齐而过度拆分微小 Widget；以复用边界和职责为准。
