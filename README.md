# XnX Player

PlayStation 5 风格的 Windows 桌面播放器。Flutter 负责界面，mpv（`libmpv-2.dll` + `wid` 原生子窗口）负责解码与出画。

界面不是「深色主题的列表」，而是按 PS5 系统的工艺规则重建的（参考 [ps5-homebrew-ui](https://github.com/leolobato/ps5-homebrew-ui) 的 `docs/CRAFT.md` 与 `concepts/aurora.cpp`）：1920×1080 虚拟画布、弹簧驱动的动效、**一个在项之间滑动的焦点高亮**、随选中封面换色的程序化背景、交错入场、毛玻璃浮层。

## 这一版做了什么

**前端（重写）**

- `lib/design/ps_motion.dart` — 弹簧积分器（隐式半拉格朗日，帧率无关、可中断）、`SpringRect`、`SpringColor`、交错入场、缓动、呼吸与抖动。
- `lib/ui/core/motion_clock.dart` — 全应用一个 ticker；所有动效读 `dt` 推进，不再各自持有 `AnimationController`。
- `lib/ui/core/focus_highlight.dart` — **唯一的焦点高亮对象**：任意深度的可聚焦项把矩形交给舞台，矩形以弹簧滑过去。
- `lib/ui/core/tv_focusable.dart` — key-up 触发、hover 抢焦点、左右键可被滑块/步进器消费（`onAdjust`）。
- `lib/ui/widgets/ps_backdrop.dart` — 三层极光背景，颜色跟随当前封面，慢速漂移。
- 首页 — hero（440² 封面、88 号标题、20/字距 4 眉标、420×8 进度条、Play/收藏/更多）+ 可竖向滑动的货架（196 卡片、26 间距、聚焦放大 1.2、底边对齐、行距 304、距离淡出）。
- 详情页（Hub）、媒体库（来源导轨 + 海报墙 + 添加来源对话框）、设置页（画质 / 直通 / HDR / 平滑 / 去色带 / 音量 / 字幕 / 减少动效）。
- 搜索层 — 从顶栏放大镜或 `/` 打开，输入框自动取键盘，`↓` 把焦点环交给结果网格（`FocusNavigator.focusIn`），`Esc` 关闭；结果来自本地索引，打字时不会请求后端。

**数据层（新增，全部真实实现）**

- `lib/data/net.dart` — 基于 `dart:io` 的 HTTP（含 PROPFIND）与一个命名空间无关的小型 XML 读取器。**不引入任何新依赖**。
- Emby / Jellyfin：登录、最新、续播、剧集、直连播放（`/Videos/{id}/stream?static=true`，避免转码）、进度回报。
- IPTV：m3u 解析 + XMLTV 节目单（时区偏移正确处理）。
- OpenList / AList：`fs/list`、`fs/get` 取直链。
- WebDAV：PROPFIND 207 解析，Basic 认证。
- 本地文件夹：递归扫描 + 扩展名过滤 + 大小/分辨率标签。
- `lib/data/store.dart` — 统一媒体模型聚合、续播记忆、`%APPDATA%\XnX Player\state.json` 持久化。

**播放（mpv 内部 UI）**

视频画在原生子窗口里，永远压在 Flutter 之上，所以播放器内的界面全部由 `assets/mpv/player_osd.lua` 以 1920×1080 的 ASS 叠加层绘制——和参考整合包（mpv-Yaozhi）的 uosc 是同一套思路。这一层现在是完整播放器外壳，而不只是一条进度条：

- **底部控制条**：播放/暂停、−10/+10 秒、当前/总时长、进度条（缓冲段、章节刻度、片头片尾标记、hover 时间气泡）、右侧七个入口。
- **格式标签**：进度条上方常驻 `3840x2160 · HEVC 10bit · HDR10 · 23.976 fps · D3D11 · EAC3 · 32.4 Mbps`，不用开统计面板就能确认硬解与 HDR 状态。
- **七个菜单**（键盘 + 鼠标，PS5 式焦点：整行反白、左箭头调值）：
  - 音轨 / 字幕（含关闭、延迟、字号、垂直位置、加载外挂字幕）
  - 章节 / 倍速 / 播放列表
  - 画面：亮度、对比度、饱和度、伽马、缩放、镜像、旋转，一键恢复
  - 更多：循环模式、去色带、插帧、HDR 直通、A-B 循环、画面比例、截图、退出
- **统计面板**：文件、容器、大小、时长、分辨率、编码、像素格式、位深、色彩空间、解码方式、帧率、实测帧率、刷新率、丢帧、音频编码/声道/采样率、缓存、码率，全中文化、两栏。
- **片头片尾**：按章节名（opening/intro/片头/ending/片尾…）自动识别，或 Alt+N 手动打点；写入 `%APPDATA%\XnX Player\segments.json`，按文件记忆；开启后自动跳过，并在时间轴上画出区间。
- **连播**：从详情页的剧集货架起播时，整季会作为 mpv 播放列表入队，`N` / `PgDn` 直接下一集，不需要回到列表。
- **音乐模式**：没有视频轨的文件改画整屏标题 + 音频参数，控制条照常可用，不再是一块黑屏。
- **鼠标**：hover 高亮、点击执行、滚轮调音量、右键开「更多」、移动鼠标唤出控制条。

## 按键

**界面（Flutter）**

| 键 | 作用 |
|---|---|
| 方向键 | 移动焦点（几何打分：`gap + crossOffset × 2.5`） |
| Enter / 空格 | 选择 |
| 右键（Context Menu） | 长按菜单（媒体库里为「移除来源」） |
| Tab | 控制中心 |
| `/` 或 Ctrl+F | 搜索 |
| F11 | 全屏 |
| Esc | 返回 / 关闭浮层 |

**播放（mpv OSD）**

| 键 | 作用 |
|---|---|
| 空格 / K | 播放 / 暂停 |
| ← → / Shift + ← → | 快退快进 5 秒 / 30 秒 |
| ↑ ↓ | 音量 ±5 |
| M | 静音 |
| J / Shift+J | 下一个 / 上一个字幕 |
| V | 字幕显示开关 |
| Z / X | 字幕延迟 −0.1 / +0.1 |
| A / Shift+A | 下一个 / 上一个音轨 |
| `[` / `]` / Backspace | 减速 / 加速 / 恢复 1.0× |
| C | 下一个章节 |
| , / . | 逐帧后退 / 前进（暂停时） |
| S / Shift+S | 截图 / 含字幕截图 |
| I | 统计面板 |
| L | 循环模式 |
| Alt+N | 标记片头（起点 → 终点 → 清除） |
| Alt+O | 加载外挂字幕 |
| N / PgUp / PgDn | 播放列表下一个 / 上一个 |
| 1–9 | 跳到 10% – 90% |
| F7 / F8 / F9 / F10 / F11 | 列表 / 章节 / 画面 / 音轨 / 字幕菜单 |
| Tab | 显示 / 隐藏控制条 |
| H | 快捷键总览 |
| Esc | 关菜单 → 藏控制条 → 退出播放 |
| F1 | 诊断面板（mpv 日志 + 子窗口枚举） |

## 构建

本机不需要 Flutter：推送到 GitHub 后由 Actions 构建（`flutter analyze --fatal-warnings` 作为门禁，然后 `flutter build windows --release`，产物为整个 Release 目录）。

```bash
git push origin main
```

`windows/` 模板与 `libmpv-2.dll` 都由 CI 生成/下载，不进版本库。

## 已知限制

- 代码仍未在本地编译（开发机没有 Flutter SDK），以 CI 结果为准。
- 弹幕未实现：需要外部弹幕 API、剧集匹配与 roll 渲染，属于独立子系统。
- ISO（`bd://`）未接入，`.iso` 会按普通文件路径交给 mpv。
- 手柄导航未接入（键盘/鼠标已完整）。
- 外挂字幕依赖 Flutter 的文件对话框，播放页需在前台。
