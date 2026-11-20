# PS5-inspired Media Entertainment Center
## Flutter 产品架构与 UI/UX 设计规范包

本项目将 PS5 Homebrew UI 作为主要设计语言参考，并吸收 Emby、Jellyfin、Plex 在媒体组织、元数据展示和沉浸式浏览方面的成熟经验。

**产品定位：** 面向 Windows 与家庭大屏场景的沉浸式媒体娱乐中心，而非单纯的视频播放器。

> 重要边界：本规范描述的是独立实现的设计与架构建议，不代表 Sony、Emby、Jellyfin 或 Plex 的官方设计规范。PS5 Homebrew UI 的代码、素材及许可证应在复用前单独核查。

## 文档索引

- `docs/PRODUCT_VISION.md`：产品定位、体验原则与设计目标
- `docs/INFORMATION_ARCHITECTURE.md`：信息架构、页面地图与导航模型
- `docs/UX_INTERACTION.md`：手柄/遥控器/键盘/鼠标交互、焦点与覆盖层
- `docs/METADATA_EXPERIENCE.md`：沉浸式元数据与媒体详情体验
- `docs/DESIGN_SYSTEM.md`：主题、视觉 Token、材质、动效、声音与一致性
- `docs/MEDIA_PLAYBACK.md`：播放体验、OSD、音轨、字幕、章节和技术信息
- `docs/ACCESSIBILITY_AND_INPUT.md`：输入设备、可访问性与大屏可用性
- `architecture/FLUTTER_ARCHITECTURE.md`：Flutter 分层架构与模块边界
- `architecture/STATE_AND_FOCUS.md`：状态管理、焦点系统与导航恢复
- `specs/COMPONENT_CATALOG.md`：组件目录、职责、复用与扩展建议
- `specs/IMPLEMENTATION_ROADMAP.md`：分阶段实施路线与验收标准

## 核心原则

1. **继承设计语言，不机械照搬组件。** 从参考项目提取颜色、材质、间距、焦点、动效、声音等规则，再以 Flutter Widget 独立实现媒体扩展。
2. **媒体内容优先。** 海报、背景图、简介、演职员、系列关系和观看进度是核心内容，不应被播放器控件或装饰性 UI 抢占。
3. **大屏与手柄优先，同时支持桌面输入。** 方向键导航必须可靠；鼠标点击不能破坏焦点模型。
4. **播放引擎与呈现层解耦。** UI 不直接依赖具体解码器实现。
5. **一致性来自 Token 和行为契约。** 新增媒体组件必须复用基础材质、焦点状态、动效曲线和反馈机制。
6. **渐进增强。** 元数据缺失、图片加载失败、离线和媒体源不可用时仍能正常使用。

## 推荐技术基线

- UI：Flutter / Dart
- 状态管理：沿用项目现有方案；若尚未确定，可评估 Riverpod 或 Bloc，避免为 UI 组件引入多套状态体系
- 路由：项目现有路由方案；统一维护页面栈与焦点恢复信息
- 播放：通过抽象 `PlaybackEngine` 接入 media_kit/libmpv 或其他引擎
- 本地数据：Repository + Cache 层；元数据来源与媒体扫描解耦
- 输入：Flutter Focus 系统为基础，增加空间焦点策略与控制器映射层

具体依赖版本应在项目实施时核实兼容性，不在本规范中锁定未经验证的版本。
