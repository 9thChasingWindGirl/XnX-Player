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

**播放**

- 设置项映射到 mpv：画质档位、HDR 直通、`audio-spdif` 四档、插帧、去色带、音量、字幕字号。
- 起播位置来自上次退出时的进度；退出时回写进度，首页「继续观看」由此而来。
- 播放器 OSD 仍画在 mpv 内部（`assets/mpv/xnx_osd.lua`），因为原生子窗口永远压在 Flutter 之上。

## 按键

| 键 | 作用 |
|---|---|
| 方向键 | 移动焦点（几何打分：`gap + crossOffset × 2.5`） |
| Enter / 空格 | 选择 |
| 右键（Context Menu） | 长按菜单（媒体库里为「移除来源」） |
| Tab | 控制中心 |
| `/` 或 Ctrl+F | 搜索 |
| F1 | 播放页：诊断面板；首页：打开本地视频 |
| F11 | 全屏 |
| Esc | 返回 / 关闭浮层 |

## 构建

本机不需要 Flutter：推送到 GitHub 后由 Actions 构建（`flutter analyze --fatal-warnings` 作为门禁，然后 `flutter build windows --release`，产物为整个 Release 目录）。

```bash
git push origin main
```

`windows/` 模板与 `libmpv-2.dll` 都由 CI 生成/下载，不进版本库。

## 已知限制

- 所有代码尚未在本地编译（开发机没有 Flutter SDK），首轮 CI 可能仍需修若干类型细节。
- 播放入口依赖 `wid` 子窗口链路；若视频仍黑屏，按 F1 看诊断面板里的子窗口类名。
- 手柄导航尚未接入（键盘/鼠标已完整）。
- 设置页的「跳过片头」只有开关，章节检测尚未实现。
