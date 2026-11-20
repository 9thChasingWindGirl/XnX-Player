# Phase 0 架构审计：现有实现 vs PS5 媒体中心规范

> 基准文档：`docs/spec/ps5_media_entertainment_center/`（规范包已随仓库归档，原路径在 `\\DESKTOP-M254VBJ\VM Output\`，不可长期依赖）
> 代码基线：`lib/` 55 个 Dart 文件、13,226 行；播放层另有 `assets/mpv/player_osd.lua` 2,536 行
> 方法：只写能在代码里指出行号的结论。规范里属于「建议」、但按当前体量不划算的，单列一节说明不做的理由，不假装已满足。

---

## 一、总览

规范要求的 Global Interaction Layer 有五件事。现状是 **2 件做好了、1 件做了一半、2 件没有**：

| 能力 | 状态 | 证据 |
|---|---|---|
| Focus Manager | 完成 | `lib/ui/core/focus_navigator.dart` 几何寻路 + `focus_zone.dart` 区域 + `focus_highlight.dart` 单环滑动 |
| Animation Engine | 完成 | `lib/ui/core/motion_clock.dart` 全局单 ticker；`lib/design/ps_motion.dart` 弹簧积分器 |
| Overlay Manager | 一半 → P1 已收口 | 退栈改成 `_overlays` 列表（dock → panel → search），Back 永远只弹一层（`shell_page.dart` 的 `_onBack`）。仍只有控制中心一类浮层 |
| Input Manager | **缺失 → P1 已补** | `lib/core/input/`：25 个动作、表驱动键位、分层栈、XInput 手柄、三套设备规则。见 `docs/INPUT_MODEL.md` |
| Sound Manager | **缺失** | 全仓无音效实现（`S.ccSound` 只是控制中心的面板标题） |

播放层另有一处结构性偏差，影响比上面两项加起来都大：**播放界面不在 Flutter 里**，在 mpv 的 Lua 脚本里（详见 §三.3）。

---

## 二、逐条对照

### 2.1 分层与目录（FLUTTER_ARCHITECTURE.md）

| 规范 | 现状 | 判定 |
|---|---|---|
| `design_system/` 只做视觉，不碰媒体 API | `lib/design/`（tokens/motion）+ `lib/ui/`（focus/widgets），无反向依赖 | ✅ 形态不同，边界正确 |
| `core/focus`、`core/input`、`core/navigation`、`core/overlay`、`core/animation` | 只有 `ui/core/`，含 focus 四项 + motion_clock；**没有 input、overlay、navigation** | ◐ |
| `features/{home,library,details,player,settings}` | `pages/` 平铺，缺 `details` 独立页（`media_page.dart` 是海报网格，没有剧集/演职员/合集详情） | ◐ |
| `domain/` + `data/` 四层（entities/repositories/use_cases） | `data/models/media_item.dart` 直接做领域模型，`data/sources/*` 直接产出它 | ◐ 见 §四：不建议补 |
| `playback/{contracts,adapters,models}` | `playback/mpv/*` 全是实现，UI 直接 `new MpvPlayer()` | ✗ 见 §三.4 |
| Widget 不直接调服务端 API | 成立：`EmbySource`/`LocalSource` 实现 `MediaSource` 接口，页面只收 `MediaItem` | ✅ |
| Token 不散落为硬编码 | `ps_tokens.dart` 覆盖颜色/间距/尺寸；`cc_panels.dart` 里仍有零散数值 | ◐ 轻微 |

### 2.2 状态与焦点（STATE_AND_FOCUS.md）

| 规范 | 现状 | 判定 |
|---|---|---|
| 状态按生命周期拆分，不塞一个全局 Store | `AppStore` 只管配置/列表/继续观看；播放态、焦点态各自独立 | ✅ |
| 焦点 ID 语义化且稳定（`home.hero.play`） | `FocusEntry` 只有 `node / zoneId / order`（`focus_zone.dart:32-41`），**没有 ID**；`zoneId` 是 `'dock-icons'` 这类区域名 | ✗ 见 §三.5 |
| 不用列表 index 作焦点标识 | 靠 `FocusNode` 实例身份，索引变化不会错位；但无法按 ID 找回 | ✅ 结果对，机制不同 |
| 空间导航：Shelf 左右、Grid 几何、Dialog 限制 | 几何评分器统一处理，含同区加分；Dialog 未做焦点陷阱 | ◐ |
| 页面恢复：路由/滚动/焦点/筛选/展开态 | 只有 Tab 保活（`shell_page.dart:507-515` Offstage+TickerMode+ExcludeFocus）；**焦点与筛选不恢复** | ◐ 见 §三.6 |

### 2.3 交互（UX_INTERACTION.md）

| 规范 | 现状 | 判定 |
|---|---|---|
| 多设备映射到统一动作（NavigateUp/Confirm/Back/…） | 无动作枚举；`TvFocusable` 内部认 `enter/space/select`，`shell_page` 认方向键，播放页认另一套 | ✗ 见 §三.1 |
| 手柄/XInput 支持 | `mpv_options.dart:122` 明确 `input-gamepad: no`，Flutter 侧无任何手柄代码 | ✗ |
| 焦点系统管理「输入模式切换」 | 无输入模式概念 | ✗ |
| Overlay 契约（记录→移焦→限域→Back 关闭→恢复） | 控制中心用 `_ccOpen`/`_ccPanel` 两个字段 + 手写 Esc 阶梯（`shell_page.dart:105-118`），恢复靠 `focusFirst()` | ◐ 见 §三.2 |
| 鼠标 hover 不改变手柄焦点，除非进入鼠标模式 | `TvFocusable` 的 `onEnter` 直接 `requestFocus()`（`tv_focusable.dart:234-239`） | ✗ 与规范相反，但符合电视盒子习惯，见 §三.1 |

### 2.4 播放体验（MEDIA_PLAYBACK.md）

| 规范 | 现状 | 判定 |
|---|---|---|
| OSD 默认隐藏、操作后显示、操作中不隐藏 | Lua 侧已实现（含拖动期间禁止自动隐藏） | ✅ |
| 顶部标题 / 底部时间轴 / 音轨字幕入口 | Lua 侧一行标题 + 3px 时间轴 + 胶囊徽章 + 右侧菜单 | ◐ 没有音轨/字幕选择菜单的常驻入口 |
| 时间轴：缓冲、章节、预览图 | 只有已播放/总时长；无缓冲段、无章节、无预览 | ◐ |
| 播放信息面板区分「文件元数据」与「管线状态」 | 徽章三档 `fact/lit/dim`，判断依据 `video-out-params` / `audio-out-params` | ✅ 这条是规范里最容易做错的，已经做对 |
| 统一 `PlaybackState`（idle/opening/buffering/playing/paused） | **不存在**。状态散在 Lua 拿 mpv 属性、Dart 侧零散 `getProperty` | ✗ 见 §三.4 |
| UI 不直接依赖具体引擎 | `player_page.dart:242` 直接 `MpvPlayer()` | ✗ |

### 2.5 可访问性（ACCESSIBILITY_AND_INPUT.md）

| 规范 | 现状 | 判定 |
|---|---|---|
| 焦点指示不只靠颜色 | 白色环 + 8px 发光 + 缩放（`localRing` + gliding highlight） | ✅ |
| 减少动态效果 | `MotionClock.reduceMotion` 已接 | ✅ |
| UI 音效可关闭 | 无音效 | ✗（无音效则无从关闭，可接受） |
| 快捷键提示常驻 | 无提示，符合「不要常驻」 | ✅ |

### 2.6 组件目录（COMPONENT_CATALOG.md）

已具备：Surface/Glass（`ps_backdrop`、`control_center` 材质）、Focus Indicator、Hero Panel（`home_hero.dart`）、Media Shelf（`home_rail.dart`）、Poster Card（`home_tile.dart`）、Control Center（`control_center.dart` + 8 个面板）、Settings、Notification 面板。

缺失：Media Detail Hero、Season Selector、Episode List、Episode Card、Person Card、Credits Carousel、Collection Card、Timeline Scrubber（Flutter 版）、Audio/Subtitle Menu（Flutter 版）、Chapter Navigator、Next Episode Card、Playback Queue UI。

---

## 三、真正的缺口（按影响排序）

### 3.1 输入层不存在，键盘逻辑散落五处

规范要的是「设备 → 抽象动作 → 页面消费」，现状是每个消费者自己认物理按键：

| 位置 | 认什么 |
|---|---|
| `shell_page.dart:92` `_onKey` | 方向键、Esc、Tab、`/`、Ctrl+F、F1、F11 |
| `pages/hub/hub_page.dart:62` | Esc |
| `pages/media/source_dialog.dart:79` | Esc |
| `pages/search/search_page.dart:75` | Esc、方向下 |
| `player/player_page.dart:92` + `osd_keys.dart` | 全套按键 → 转成 mpv 键名 |

后果已经在发生：**同一个键在「大厅」和「播放页」行为不同**，Esc 在控制中心要按两次（先退面板再退 dock），而播放页的 Esc 直接退出播放。没有统一动作表，这种不一致只能靠逐个打补丁，且每加一个页面就多一处。

修复路径（成本可控，不动现有焦点系统）：新增 `lib/core/input/`，
1. `InputAction` 枚举（NavigateUp/Down/Left/Right、Confirm、Back、ContextMenu、Home、PlayPause、Seek±、Volume±、ToggleControlCenter）；
2. `InputBindings`：物理键/鼠标键/手柄键 → 动作的默认表 + 用户覆盖；
3. 一个 `InputManager`（`WidgetsBinding` 级单一 handler）把动作分发到「当前输入作用域」——作用域就是现有的 `FocusZone` + 一个页面声明；
4. 页面只实现 `onAction(InputAction)`，不再直接认键。

这一步同时把手柄变成「再添一个映射源」，而不是再造一套导航。

### 3.2 Overlay 契约用布尔量代替

`_ccOpen` + `_ccPanel` 两个字段能表达控制中心，但表达不了「三层浮层 + 各自恢复焦点」。规范要求的 `record → focus → trap → back → restore` 目前是手写的，每加一种浮层就要再抄一遍 Esc 阶梯和 `focusFirst()`。

修复路径：`lib/core/overlay/overlay_stack.dart`，一个 `OverlayRoute`（`focusFallback`、`onBack`、是否限域），统一入栈/出栈与焦点恢复。控制中心、搜索、来源弹窗、音轨/字幕菜单都登记进去。

### 3.3 播放界面不在 Flutter 里（结构性偏差）

现状：mpv 的子窗口盖在 Flutter 之上，OSD 由 Lua 用 `create_osd_overlay('ass-events')` 直接画进视频帧。所以播放页的控件**用不到** `TvFocusable`、`FocusNavigator`、`MotionClock`、`ps_tokens`——它们是一套独立的实现（几何 hitbox + ASS 图形 + 自己的淡入淡出）。

代价已经被两轮 bug 证明：
- 鼠标必须由 Flutter 转发（mpv 子窗口抢不到/收不到），于是**坐标要换算两次**，`to_design` 里的 scale 分歧就是「进度条要点上面一点」；
- 键盘同理，`osd_keys.dart` 是一张只为转发存在的键名表；
- 任何视觉调整都要在 Lua 里重画一遍，且无法复用设计 token。

三条路，成本递增、收益递增：

| 方案 | 做法 | 代价 | 收益 |
|---|---|---|---|
| A 维持现状并固化契约 | Lua 继续拥有 OSD，Dart 只负责转发与退出 | 已付 | 无新增 |
| B Lua 降级为纯渲染器 | Flutter 持有 OSD 状态与焦点，把 `{visible, hoverId, time, badges…}` 推给 Lua 画 | 中等：要设计状态 JSON 协议，Lua 侧删除全部交互逻辑 | 交互模型唯一，hitbox 与高亮天然一致；视觉仍可用 ASS 低成本渲染 |
| C OSD 迁到 Flutter | 播放页叠一层 Flutter 控件 | 高：mpv 是盖在 Flutter 之上的子 HWND，需要透明置顶窗口或改变嵌入方式 | 全套复用；但工程量与稳定性风险最大 |

建议先 B 再决定是否 C。B 能消掉「双份交互模型」这个 bug 源头，又不碰窗口堆叠。

### 3.4 没有 PlaybackEngine 契约，也没有 PlaybackState

`player_page.dart` 里 `_player` 是 `MpvPlayer?`，直接调 `togglePause`/`seekTo`/`getProperty('paused')`。规范要求 UI 只订阅统一状态。当前状态真实来源在 Lua（它才知道 OSD 认为的进度、可见性、徽章），Dart 只能靠 `script-message` 反推。

修复路径：`lib/playback/contracts/playback_engine.dart`（`open/play/pause/seek/setVolume/tracks` + `Stream<PlaybackState>`），`MpvPlayer` 作为第一个 adapter；`PlayerPage` 只依赖接口。这一步单独做的收益主要是可测试性和换引擎的可能性，**但它和 §3.3 的 B 方案天然合并**——状态在 Dart 侧之后，才有东西可推给 Lua。

### 3.5 焦点没有稳定 ID

`FocusEntry` 只有 `FocusNode` 身份。后果：无法实现「返回详情页时把焦点放回刚才那张卡」，也无法写「`player.controls.pause` 这种跨层寻址」。`FocusZone.id` 是唯一语义标识，粒度太粗。

修复路径：`TvFocusable` 加可选 `focusId`（如 `home.shelf.continue.item.123`），注册表建 `Map<String, FocusEntry>`；`FocusNavigator.focusById()`。无需迁移现有卡片——未提供 ID 的沿用几何寻路。

### 3.6 页面恢复只覆盖了「Tab 保活」

`_visited` + `Offstage` + `TickerMode` 能让切 Tab 时滚动位置和图片不丢，这是对的。但：
- 焦点不恢复（回到 Home 时 `focusFirst()`，不是刚才那张卡）；
- 筛选/排序状态在页面 State 里，页面销毁即丢；
- 没有「从播放页返回详情页」这条路径（因为还没有详情页）。

依赖 §3.5 先有 ID。

---

## 四、不建议照做的部分

规范是按「完整媒体中心」写的，直接照抄会付出与收益不成比例的代价：

1. **`domain/` + `use_cases/` 四层**。当前 55 个文件、13k 行，`MediaSource` 接口 + `MediaItem` 归一化已经解决了「换源不改页面」这个真实问题。再加一层 use case 只是把一次函数调用拆成三个文件。**等出现第二个消费方（比如手机端/CLI）再抽。**
2. **引入 Riverpod/Bloc**。`AppStore extends ChangeNotifier` + 局部 `setState` 在这个体量下没有失控迹象；换状态库会牵动 55 个文件，收益是「更规范」。**不做。**
3. **按 `features/` 重排目录**。`pages/` 已经很清楚了。目录重排会产生一个巨大的、纯移动的 diff，让后续 review 无从下手。**只在新增模块时用规范命名，存量不动。**
4. **`core/navigation` 独立路由层**。现在是 shell + Tab + 两种浮层，没有深层路由栈。等有了详情页再抽。

---

## 五、建议的推进顺序

| 阶段 | 内容 | 可验证的验收点 |
|---|---|---|
| P1 | §3.1 输入动作层 + §3.2 Overlay 栈 | 同一份动作表覆盖大厅/播放页，页面里不再出现 `LogicalKeyboardKey`；新增第三种浮层时不写新的 Esc 阶梯和 `focusFirst()`；手柄插上即可导航（XInput → 动作） |
| P2 | §3.5 焦点 ID + §3.6 恢复 | 切 Tab 回来焦点落在原卡片；浮层关闭后焦点回原处 |
| P3 | §3.3 方案 B + §3.4 PlaybackState | Lua 不再有 hitbox；Dart 侧可断言 `PlaybackState` 序列 |
| P4 | 详情页 / 剧集 / 音轨字幕菜单（Flutter 侧） | 见规范 Phase 2/3 |
| P5 | 音效、减少动态效果的完整覆盖 | 音效开关生效；`reduceMotion` 下所有装饰动画停止 |

---

## 六、验证条件（诚实说明）

本机无 Dart/Flutter SDK（`flutter`、`dart` 均不在 PATH，也没有 `.dart_tool`），所有 Dart 改动的编译与测试只能靠 GitHub Actions。Lua 与资产侧有本地探针：`tool/osd_probe.py`（真点进度条）、`tool/logo_probe.py`（徽章资源完整性）、`tool/osd_render.py`（离线预览 ASS 输出）。

因此 P1 及之后的每一步都以「一次 CI 全绿」为交付单位，不做跨多阶段的批量重构。


---

## 五、P1 落地（2026-11-20）

审计里标为「最大实际缺口」的输入层已经补上，**但刻意没有照搬规范里的一刀切做法**：

- `lib/core/input/input_action.dart` — 25 个动作 + `InputDevice`。动作是共享词汇，设备的产生方式不是。
- `lib/core/input/input_router.dart` — 唯一的键盘入口 + 分层栈。五个文件各自的 `HardwareKeyboard.addHandler` 收敛成一处，`dispose` 时取消订阅即退栈。
- `lib/core/input/keymap.dart` — 物理键 → 动作的唯一定义处。
- `lib/core/input/held_repeat.dart` + `gamepad.dart` — 手柄方向重复（350/110/50ms）与摇杆死区 0.16。手柄不重复用键盘的 OS 重复，键盘也不套用手柄的合成节奏。
- 退栈：`_onBack` 依据 `_overlays` 弹一层，替代原来嵌套的 `if (_ccPanel)` / `if (_ccOpen)` 阶梯。

**仍未做**：手柄设置项（`swapConfirm` 是常量）、震动、掉线提示、音效、`Sound Manager`。**仍未验证**：本机没有任何手柄（XInput 四个槽位全部 1167 未连接），所以「按下 A 激活焦点」只是静态推理；出包后需实机确认。
