# 设计令牌：从 ps5-homebrew-ui 提取、为媒体中心延伸

> 上游源码：`C:\Users\132\WorkBuddy\xnx播放器参考资料\ps5-homebrew-ui`（BlackBearReloaded，GPL-3.0-or-later）
> 产品规范：`docs/spec/ps5_media_entertainment_center/`
> 本文回答一个问题：**这套设计语言怎么落到 Flutter 里，规范没覆盖的部分怎么延伸。**

---

## 1. 许可边界（先写清楚，因为它决定什么能抄）

上游是 **GPL-3.0-or-later**。本项目的 Dart 代码是独立实现，不是移植，也不需要跟着 GPL 走。具体到三类东西：

| 类别 | 能否使用 | 说明 |
|---|---|---|
| 数值、几何、时序、规则 | 可以 | 96px 安全边、弹簧频率 18..22、停留 350ms 后重复……这些是**设计事实**，不构成受版权保护的表达。CRAFT.md 通篇就是这些。 |
| C++ 源码 | 不复制 | 我们读它来理解算法（例如弹簧的精确解），但写的是 Dart。`ps_motion.dart` 是重新推导的实现，注释也是自己的。 |
| 素材（67 个 wav、6 套 SDF 字体、shader、截图） | **不随包分发** | 这些是上游作者的资产，GPL 传染范围明确包含它们。要做 UI 音效必须是我们自己录或生成的文件。 |

结论：**拿规则，不拿文件。**

---

## 2. 上游的 token 模型

`src/ui/theme.hpp:53-114` 是一个 60 行的结构体，「一套设计语言 = 填这个结构体」。分四组：

```text
page/palette   page, surface, surface_high, text, text_muted, primary, on_primary,
               secondary, on_secondary, accent, outline, focus, shadow, light,
               danger, success, warning
shape          style(11 种表面), corner(圆/切角/像素), radius, radius_card,
               border, button_border, shadow_offset, shadow_blur,
               focus_width, focus_gap
type           heading, label, caps, tracking
motion/sound   omega, damping, sounds(声音集), dark
```

其中 `SurfaceStyle` 有 11 种（flat/soft/hard/neumorphic/bevel/gloss/glass/outline/glow/pixel/sketch），`Corner` 有 3 种。**这是给 30 套主题用的**，我们只需要其中一种语言：

> 深色底 + 内容图片当主角 + `glass` 表面 + 白色焦点环 + 蓝色强调。
> 对应上游 `theme.cpp` 的 `acrylic()`（frosted glass），以及 `concepts/aurora.cpp` 的首页。

---

## 3. 已经对齐的部分

`lib/design/ps_tokens.dart` 与 `ps_motion.dart` 其实**已经是这套语言的转录**，不是巧合——里面的数值和 `concepts/aurora.cpp:41-47` 逐字对应：

| 上游 | 我们 | 值 |
|---|---|---|
| `kMargin` | `PsSpace.safeX` | 96 |
| `kCard` | `PsSpace.tileSize` | 196 |
| `kCardGap` | `PsSpace.cardGap` | 26 |
| `kCardGrow` | `PsSpace.cardGrow` | 1.2 |
| `kShelfY` | `PsSpace.shelfY` | 730 |
| `kShelfPitch` | `PsSpace.shelfPitch` | 304 |
| 安全区约 60 | `PsSpace.safeY` | 60 |
| `tween::Spring` | `Spring` | 半隐式欧拉，omega/damping |
| `ui::SpringRect` | `SpringRect` | 四条弹簧驱动矩形 |
| `ui::SpringColor` | `SpringColor` | 通道级颜色弹簧 |
| `Pulse` / `shake` / `breathe` / `stagger` | 同名 | 拒绝、呼吸、入场错峰 |
| `Ease.cubic_out/quint_out/back_out` | `Ease.*` | 曲线 |
| 焦点环 4px 描边、5px 外扩 | `PsFocus.ringWidth/ringGap` | 一致（第二轮修正，见 §10） |

所以「ps5-homebrew-ui 能不能适配 Flutter」已经不是假设题：**它已经适配了一半**，剩下的是媒体中心独有的部分。

---

## 4. 本轮补齐的 token

### 4.1 状态色与材质色（`ps_tokens.dart`）

上游 `theme.hpp:84-86` 有 `danger/success/warning`，`theme.hpp:81` 有 `light`（玻璃的高光边）。我们只有 `danger`，其余是页面里临时调的颜色。新增：

| Token | 值 | 来源 |
|---|---|---|
| `PsColor.success` | `#30A46C` | `theme.hpp:85` 原值 |
| `PsColor.warning` | `#F5A524` | `theme.hpp:86` 原值 |
| `PsColor.onAccent` | `#FFFFFF` | `on_primary` 语义（深色主题下白字） |
| `PsColor.glassEdge` | `#38FFFFFF`（白 22%） | `aurora.cpp:521` 的 `kWhite.with_alpha(0.22)` 玻璃边线 |

> 注意：`danger` 我们用的是 `#FF5D6C`，上游是 `#E5484D`。**保留我们的**——它是为这个深色底调的，改了会让「删除/退出」按钮在玻璃面板上偏暗。这类有意偏离记在这一节，不要私自「对齐」。

### 4.2 焦点环几何（`PsFocus`）

`theme.hpp:99-100` 把焦点环拆成 `focus_width` 与 `focus_gap` 两个值。我们的环原本是固化的魔数（`tv_focusable.dart` 里 2.5 / 8 / `-4`）。新增：

| Token | 值 | 说明 |
|---|---|---|
| `PsFocus.ringWidth` | 4 | 环的描边（两个 painter 共用） |
| `PsFocus.ringGap` | 5 | 与 aurora 的 `inset(-5)` 一致 |
| `PsFocus.glowWidth` | 8 | 卡片自己兜底环的发光宽度 |
| `PsFocus.glowBlur` | 8 | 同上 |
| `PsFocus.glideGlowWidth` | 14 | 舞台上那个滑动环更粗，要能被一眼追上 |
| `PsFocus.glideGlowBlur` | 16 | 同上 |

已落地：`tv_focusable.dart` 与 `focus_highlight.dart` 的六个魔数全部改为引用。

> 值在第二轮核对时改过：最初 2.5 / 4 是照 `Theme` 结构体默认值（`focus_width 3`）
> 推的，而 aurora 首页实际画的是 `bordered_rect(ring.inset(-5), 30, …, 4, kWhite)`
> ——4 px 描边、5 px 外扩。见 §10.1。

### 4.3 阴影层级（`PsElevation`）

`CRAFT.md:112-126` 规定「聚焦卡片的阴影下移 10..26、柔化 30..46；静止卡片没有或极淡」。我们页面里是散的（`home_tile.dart:35/225`、`home_hero.dart:195`）。新增三档，值取自**现有代码**（保证不改观感），并补一档上游的浮层：

| Token | 值 | 来源 |
|---|---|---|
| `PsElevation.cardResting` | **无投影** | `card.cpp:256`：静止卡不画影；第四轮删掉了原来 0,10/20/35 % 的折中，见 §12.1 |
| `PsElevation.cardLifted(focus)` | 4,10+8f / blur 22+16f / 黑 34% | `card.cpp:258-261`：集合内聚焦卡 |
| `PsElevation.cardFocused` | 0,18 / blur 34 / 黑 60% | `aurora.cpp:500`：`shadow(…, 26, 34, black 0.6)`，26 是圆角、34 才是柔化 |
| `PsElevation.sheet` | 0,20 / blur 60 / 黑 50% | `aurora.cpp:519` 详情抽屉 |
| `PsElevation.heroGlow(accent)` | accent 30% / blur 60 / spread 6 + 0,26 / blur 36 | `home_hero.dart:195-206` |

### 4.4 材质与模糊（`PsBlur`）

规范 §3 要求 `blur.subtle / blur.panel`，上游按面板定值。我们的实际用法：

| Token | 值 | 用在哪 |
|---|---|---|
| `PsBlur.subtle` | 12 | 预留（提示条、toast） |
| `PsBlur.panel` | 24 | 控制中心 `control_center.dart:76` |
| `PsBlur.dialog` | 28 | 来源弹窗 `source_dialog.dart:156`、搜索 `search_page.dart:147` |
| `PsGlass.tint` | 0.55 | 玻璃面板的 tint（`draw_overlay_panel` 默认），见 §12 |
| `PsGlass.sheetTint` | 0.62 | 首页详情抽屉（`aurora.cpp:520`）；原来的 `PsBlur.glassTint` 已并进这里 |
| `PsGlass.dockTintTop/Bottom` | 0.62 / 0.78 | 控制中心 dock（§12.2 说明了为什么用页面色） |

### 4.5 弹簧预设与时长（`PsMotion` 增量）

`CRAFT.md:49-54` 给了频率与时长区间。原来只有零散的 `Spring(frequency: 20)`，现在给名字：

| Token | 值 | 场景 |
|---|---|---|
| `PsMotion.springFocus` | 20 | 焦点移动（区间 18..22） |
| `PsMotion.springPanel` | 13 | 面板/抽屉（12..14） |
| `PsMotion.springPalette` | 5 | 背景取色（4..6） |
| `PsMotion.springSoft` | 10 | 播放器大位移（`player.cpp` 的 `kSoft`） |
| `PsMotion.staggerStep` | 0.04 | 入场错峰步长（`tween.hpp:90` 默认，区间 30..90ms） |
| `PsMotion.arrive` | 0.35 | 入场时长 |
| `PsMotion.depart` | 0.22 | 离场，**必须短于入场** |

---

## 5. 媒体中心延伸（上游没有的部分）

规范要的是「媒体中心」，上游是「主机 UI 工具箱 + 音乐播放器」。以下数值来自上游 `concepts/player.cpp`（Now Playing 设计）与 `concepts/aurora.cpp`（首页详情抽屉），是**唯一有依据的来源**——不是凭截图猜的。

### 5.1 时间轴（`PsScrubber`）

`player.cpp:1028-1056`：

| 部件 | 静止 | 聚焦 | 拖动 |
|---|---|---|---|
| 轨道厚度 | 8 | 12 | 12 |
| 轨道底色 | 白 16% | 白 22% | — |
| 已播放 | 渐变：`mix(body, accent, .5) → accent` | 同上 | 同上 |
| 光晕 | blur 10 / accent 22% | blur 18 / accent 42% | — |
| 圆点半径 | 9 | 15 | 18 |
| 圆点阴影 | — | 黑 45% / blur 10 / 下移 4 | — |

时间文字：等宽 22，当前时间白 86%、总时长白 60%，基线在轨道下方 46。
拖动气泡：88×36 胶囊、半径 18、位于轨道上方 66、白底 + 深色字、阴影 blur 14。横向钳制在 `[x+44, right-44]`。

**这一条直接可用来替换 OSD 现在 3px 的进度条**（若将来 OSD 迁到 Flutter，或 Lua 侧按此重画）。

### 5.2 播放控件与跳转（`PsTransport` / `PsSeek`）

`player.cpp:67-68、78-80`：

| Token | 值 | 含义 |
|---|---|---|
| `PsTransport.playRadius` | 46 | 主按钮半径 |
| `PsTransport.buttonRadius` | 32 | 次级按钮半径 |
| `PsTransport.iconStroke` | 3.5 | 图标线宽 |
| `PsSeek.step` | 5s | 时间轴上的左右 |
| `PsSeek.jump` | 15s | 任意处的大跳 |
| `PsSeek.restartAfter` | 3s | 「上一段」在这个时长内是重播 |

这三个数字现在 OSD 里的取值与它不同，属于**行为不一致**，应统一。

### 5.3 详情面板（`PsDetail`）

`aurora.cpp:511-533` 的抽屉：宽 1680、高 500、圆角 44、内边距 56；玻璃底 `mix(dark, ink, .5) @ 62%` + 1.5px 白 22% 边线；封面 300 圆角 28；类型标签 20 号加 4 字距、用强调色；标题 display 60；简介 25/36 两行、白 82%；下方三块数据砖。

这套几何正好是规范 Phase 2 的 `Media Detail Hero` 需要的，直接落成 token。

### 5.4 队列玻璃面板（`PsQueue`）

`player.cpp:70-77`：420×856、圆角 36、距离右缘 96（即 `1404 = 1920-96-420`）、表头到首行 104、行高 66。

---

## 6. 落地位置

| 文件 | 内容 |
|---|---|
| `lib/design/ps_tokens.dart` | 增量：`success/warning/onAccent/glassEdge`、`PsFocus`、`PsElevation`、`PsBlur`、`PsMotion` 预设 |
| `lib/design/ps_media.dart` | 新增：`PsScrubber`、`PsTransport`、`PsSeek`、`PsDetail`、`PsQueue` |

`ps_media.dart` 全是编译期常量，没有依赖、没有行为——它是给 Phase 2/3 的组件消费的**契约**，不是死代码。

---

## 7. 有意偏离上游的地方（记录，不是遗漏）

| 项 | 上游 | 我们 | 理由 |
|---|---|---|---|
| `danger` | `#E5484D` | `#FF5D6C` | 深色玻璃面板上更醒目；上游那套偏 Web 语义 |
| 主题数量 | 30 套 | 1 套 | 媒体中心不需要换肤；多套主题会稀释「一种语言」 |

---

## 8. 迁移记录

已迁移（渲染结果不变，只是换成引用）：

| 原位置 | 现引用 |
|---|---|
| `home_tile.dart` 两处 `BoxShadow` | `PsElevation.cardFocused` / `cardResting` |
| `home_hero.dart` 光晕 + 投影 | `PsElevation.heroGlow(art[2])` |
| `control_center.dart` `sigma 24` | `PsBlur.panel` |
| `source_dialog.dart`、`search_page.dart` `sigma 28` | `PsBlur.dialog` |
| `tv_focusable.dart`、`focus_highlight.dart` 环与发光 | `PsFocus.*` |

有意留在页面里的（属于布局，不是设计语言）：各页的间距与坐标、`focus_highlight.dart` 里呼吸振幅 `0.72 + 0.28*breathe`、hero 交叉淡入的透明度曲线。这些数值只在一个组件内有意义，提出来反而让人以为可以全局改。

---

## 9. 不从上游拿的东西

- **67 个 wav 音效**：GPL 素材，且是作者录制的。要做音效得自己生成。规范 §7 的 cue 词表（focus/select/back/error/open/close/complete/welcome）可以照抄**语义**，声音不行。
- **6 套 SDF 字体**：许可同上。我们用系统字体栈（`PsType.fontFallback`）。
- **SDF shader 与渲染器**：Flutter 用 Skia/Impeller，没有对应物，也不需要。
- **30 套主题**：见 §7。

---

## 10. 第二轮核对：源码到手后逐项验数（2026-11-21）

第一轮提取令牌时，控件已经写完了。令牌是照着 `theme.hpp` 的**结构体默认值**抄的，
而首页真正的样子写在 `concepts/aurora.cpp` 的**绘制调用**里。两者不一样，于是有
几处「文档说对齐了、实际没对齐」。

### 10.1 本轮修正（数值错，已改）

| 项 | 参考实际绘制 | 修正前 | 现在 |
|---|---|---|---|
| 焦点环描边 | `bordered_rect(ring.inset(-5), 30, …, **4**, kWhite)` `aurora.cpp:503` | 2.5 | **4** |
| 焦点环外扩 | 同上，`inset(-5)` | 4 | **5** |
| 焦点卡投影 | `shadow({x, y+18, w, h}, 26, **34**, black 0.6)` `aurora.cpp:500` | blur 26 / 0.55 | **34 / 0.60** |
| 光晕强度 | `glow(ring, 26, 26, accent.with_alpha(**0.4 + 0.15*breathe**))` `aurora.cpp:501` | 固定 0.26×pulse | **0.40–0.55** |
| 呼吸周期 | `ui::breathe()` 默认 **2.4 s**（`motion.hpp:135`） | 4.65 s（speed 1.35） | **2.4 s** |
| 放大后的圆角 | 静止 22 → 聚焦 26 | 只有 22 | 已引用，见 §11 |

`§7` 里原来那行「焦点环宽 上游 3 / 我们 2.5，缩小后更锐利」是错的：3 是
`Theme` 结构体的默认值，aurora 首页实际画的是 4。已删除。

### 10.2 仍是源码前版本（未改，涉及布局或需目视）

> 本节写成后，`§11` 已把下表全部处理完。保留原文是为了记住「哪些是没验过的判断」——
> 其中「聚焦卡片放大」「邻居让位」「eyebrow 染色」三条**当时就是错的**：功能早就在
> `home_rail.dart` 与 `home_hero.dart` 里，只是没有对照源码确认，凭印象记成了缺失。

| 项 | 参考 | 我们（拍摄时） | 影响 |
|---|---|---|---|
| 聚焦卡片放大 | `kCardGrow 1.2`，并上移 `grown - kCard`（`aurora.cpp:238`） | ~~卡片不放大~~ 实为放大：`cardSize * grow`，底边对齐 | 判断有误 |
| 放大时的邻居让位 | 右侧卡片 `x += kCard * (grow - 1)`（`aurora.cpp:487`） | ~~无~~ 实为 `_restLeft()` 已实现 | 判断有误 |
| 非首页的环偏移 | 环始终贴着放大后的卡片 | `highlightScale 1.08` 只放大环，不放大图 | 环浮在卡片外 8 % |
| 卡片投影状态 | 只有聚焦卡有投影 | `home_tile.dart` 恒用 `cardFocused` | 每张卡都像被聚焦 |
| eyebrow 颜色 | 用品名 accent（`aurora.cpp:527`） | ~~写死白色~~ 实为 `copyWith(color: accent)` | 判断有误 |
| 面板材质 | `glass()`：模糊底 + tint 0.62 + 22% 发丝线 | 有模糊，但 tint 近乎不透明（0xCC→0xF2） | 面板是实色，不是玻璃 |

### 10.3 结构缺口：上游是主题系统，我们是一个主题

`Theme` 是数据：11 种 `SurfaceStyle`、3 种 `Corner`、6 个 `FontRole`，外加
`omega/damping/sounds`。我们把它压平成了常量，于是：

- 换一种表面语言（`hard` / `neumorphic` / `pixel`）没有任何入口；
- `PsColor.surface / surfaceHigh / sheetTop / sheetBottom / scrimSoft / plus / star`
  七个令牌**零引用**（`surface` 只被 `ps_theme.dart` 转给 `ThemeData`）。控件各自
  写死填充色，令牌和实现是两套东西。

要真正解决，得把 `Theme` 落成 Dart 值对象 + 一个 `aurora` 实例，控件从
`PsTheme.of(context)` 取色取形。这是重构（约 20 个文件），不是调参——单独立项。

---

## 11. 第三轮：把「聚焦」做成一件事（2026-11-21）

参考里「聚焦」不是一个属性，而是四层叠加：**卡片变大 + 邻居让位 + 环贴着新边缘 +
其余变暗**。第三轮把这四层收到两个地方，页面不再各写一套。

### 11.1 缩放归 `TvFocusable`

`highlightScale` 过去只放大环的矩形，卡片本身不动，于是网格页的环永远浮在卡片外
8 %——「环离卡片有点远」就是这么来的。现在 `TvFocusable` 自己用 `AnimatedScale`
放大内容（160 ms，`PsMotion.grow`，easeOutCubic），环仍然按同一个系数算矩形：

- 测量点在 `MouseRegion`（外层渲染盒，不含变换），拿到的是**静止矩形**；
- 环的矩形 = `grownRect(rest, highlightScale)`，与变换后的视觉边缘一一对应；
- 货架把**盒子**放大（布局必须让邻居动），所以货架传 `highlightScale: 1.0`，不会放大两次。

### 11.2 卡片状态归 `PosterCard`

| 状态 | 静止 | 聚焦 |
|---|---|---|
| 圆角 | 22 | 26（`PsRadius.cardFocused`，对应 `aurora.cpp:503` 的 30 = 26 + 4） |
| 投影 | **无**（§12.1 改的：`card.cpp:256` 只在 focus > 0 时才画） | `cardFocused`（0,18 / blur 34 / 60 %） |
| 图像 | 压暗 18 %（`aurora.cpp:487` 的 0.82 alpha） | 全亮 |

`focused` 传 `null` 时卡片既不压暗也不抬起（不跟踪逐卡焦点的列表沿用这个）。

### 11.3 环形半径随放大后圆角

`TvFocusable.focusedRadius` 默认等于 `radius`，货架与网格传 26。环的半径是 26 + 5 的
外扩 = 31，静止卡是 22 + 5 = 27，聚焦时弹簧把半径推过去——不这样，一张放大的卡片
会顶着一个按小尺寸画的圆角。

### 11.4 面板回到玻璃

控制中心原本有 `BackdropFilter`，但上面的渐变从 `0xCC` 到 `0xF2`，几乎不透光，
看起来仍是实色板。改为 62 % → 78 % 的 tint，边框换成 `PsColor.glassEdge`（22 % 白，
`aurora.cpp:521` 的 `light`）。模糊本身没动，仍是 `PsBlur.panel` 24。

---

## 12. 第四轮：控制中心与媒体延伸逐条贴源（2026-11-21）

第三轮结束时，首页与卡片已经按 `aurora.cpp` 的绘制值对齐，但**控制中心**和**媒体
延伸**这两块仍是源码到手前写的样子：dock 的玻璃、面板的底、卡片的副标题、海报的
进度条、播放器的跳转秒数，都是「看着像」而不是「查过」。

这一轮把每一个数都对着源码改了一遍。规则仍然是：**以绘制调用为准，不以结构体默认
值为准**；没有绘制调用可查的，写明是布局约束并给出上游原值。

### 12.1 改掉的偏差

| 项 | 上游依据 | 改前 | 改后 |
|---|---|---|---|
| 集合内卡片聚焦 | `CardLook::focus_scale = 1.06f` `card.h:77` | dock 1.04 / 网格 1.08 / 搜索 1.08 | **1.06**，三处统一到 `PsCard.focusScale` |
| 静止卡片投影 | `draw_card` 只在 `focus > 0.01` 时画 `card.cpp:256` | (0,10) / blur 20 / 35 % | **无**（`PsElevation.cardResting` 为空表） |
| 聚焦卡投影（集合内） | `{x+4, y+10+8f, w-8, h}` / blur `22+16f` / 34 % `card.cpp:258-261` | 只有首页那套 34/60 | 新增 `PsElevation.cardLifted(focus)` |
| 卡片按下 | `press_scale = 0.04f` `card.h:78` | 无 | `TvFocusable.pressScale`，键盘与指针都算 |
| 卡片抬升 | `lift = 6f`，`card_lift = lift * focus` `card.h:79` | 无 | dock 卡片上移 6 px（`AnimatedSlide` 放在 `TvFocusable` **外面**，否则环留在旧基线） |
| 卡片副标题 | `CardLook::subtitle_size = 20` `card.h:56` | 15 / 16 的 micro | **20**（`PsCard.subtitleSize`） |
| 压在图上的文字 | `CardText::over` 先铺 78 % 黑渐变 `card.cpp:305-309` | 直接写白字 | dock 卡片底部铺 `PsCard.artScrim` |
| 海报观看进度条 | 高 6、内缩 `max(10, r*0.45)`、轨道 50 % `card.cpp:300-318` | 高 4、贴边、轨道 16 % | 高 6、内缩 10、轨道 50 % |
| dock 玻璃 | `draw_overlay_panel`：模糊 → surface@tint → 描边 ≥1.5 `overlay.cpp:219-250` | 黑色渐变 + **只有上边**一条 hairline | 页面色 62→78 % + **四边** 1.5（只有上边可见，但边不随布局变） |
| 面板的底 | `PanelStyle::surface = false`「只画标题栏和分隔线」`surface.hpp:113-115` | 自带 95 % 实色卡片 + 边框 | **不画底**，坐在 dock 那块玻璃上 |
| 面板内边距 | `padding_x 24 / padding_y 20` `surface.hpp:100-101` | 26 / 18 / 26 / 20 | 24 / 20 / 24 / 20 |
| 面板副标题 | `subtitle_size = 19` `surface.hpp:106` | 15 的 micro | 19 |
| 面板标题栏 | `header_rule = true` `surface.hpp:118` | 无分隔线 | 标题下一条 hairline |
| 列表行内缩 | `ListViewStyle::padding = 26` `list.hpp:35` | 18 | 26 |
| 空状态 | `EmptyStateStyle`：icon 96 / 30 / 22 / gap 16 `stat.hpp:113-120` | 34 / 21 / 15 / gap 18 | 44 / 24 / 17 / gap 16 |
| 统计块 | `StatTileStyle`：label 20 / value 48 `stat.hpp:21-23` | 14 / 30 | 18 / 40（`PsType.stat`） |
| 电平条 | 与时间轴同一条轨道：高 8、16 % `player.cpp:1028` | 硬编码 8 / 0.16 | `PsControls.trackHeight` |
| 快进秒数 | `kSeekJump = 15` `player.cpp:68` | OSD 里 Shift+方向 **30** | **15**，帮助文本同步 |
| 播放控件几何 | `MediaControlsStyle` `media_controls.hpp:60-104` | 无令牌 | `PsControls`：56/68/12、轨道 8、圆点 24、音量条 110、跳过 10 s、音量 5 % |
| 连按加速 | `seek_growth 1.3` / `seek_max 60` `media_controls.hpp:96-98` | 无 | `PsSeek.growth` / `max` / `repeated(n)` |

### 12.2 保留的偏离（每条都有约束，不是漏）

| 项 | 上游 | 我们 | 为什么 |
|---|---|---|---|
| 面板行高 | 76 | 68 + 8 = 76 的同一间距 | 面板固定 420 高，`padding 40 + 标题栏 60` 之后只剩 320；76 只能放 4 行，68 能放 4 行且不贴边。间距总和仍是 76 |
| dock 的 tint 用页面色 | `surface` 上色 | 页面底色 | 上游的 `list.glass` 在抓屏时**同时模糊并压暗**；Flutter 的 `BackdropFilter` 只模糊。用 surface 色 55 % 盖上去会发灰，所以压暗由 tint 自己承担 |
| 空状态图标 | 96 | 44 | 420 高的面板里 96 + 标题 + 两行正文放不下；比例、间距与顺序不变 |
| 首页货架卡片压暗 18 % | `CardLook::dim = 0` | 18 % | 首页用的是 `aurora.cpp:487` 的 `kWhite.with_alpha(0.82f)`——那是「未聚焦的封面」，与组件的 `dim` 是两个开关。组件默认 0 已经写进 `PsCard.dim` |

### 12.3 新令牌

| 令牌 | 值 | 出处 |
|---|---|---|
| `PsGlass.tint` | 0.55 | `draw_overlay_panel` 默认 tint |
| `PsGlass.sheetTint` | 0.62 | `aurora.cpp:519` 抽屉 |
| `PsGlass.scrim` | 0.50 | `SheetStyle::scrim` |
| `PsGlass.edgeWidth` | 1.5 | `max(theme.border, 1.5)` |
| `PsGlass.dockTintTop/Bottom` | 0.62 / 0.78 | 原 `control_center.dart` 里的两个十六进制色，收进令牌 |
| `PsCard.focusScale` | 1.06 | `CardLook::focus_scale` |
| `PsCard.lift` | 6 | `CardLook::lift` |
| `PsCard.pressScale` | 0.04 | `CardLook::press_scale` |
| `PsCard.artScrim` | 0.78 | `CardLook::scrim` |
| `PsCard.titleSize/subtitleSize` | 24 / 20 | `CardLook` |
| `PsCard.progressHeight/progressInset` | 6 / 10 | `draw_card` 的进度条 |
| `PsPanel.*` | 24 / 20 / 24 / 19 / 52 / 26 | `PanelStyle` / `ListViewStyle` |
| `PsControls.*` | 22 / 56 / 68 / 12 / 8 / 24 / 110 / 24 / 28 / 21 / 21 / 10 / 0.05 | `MediaControlsStyle` |
| `PsSeek.growth/max/repeated()` | 1.3 / 60 | `MediaControlsStyle::seek_growth/seek_max` |

`test/design_tokens_test.dart` 把这些数字钉住了：改任何一个，测试会指出它在跟哪一行
源码对不上。

### 12.4 这一轮没做的

- **`Panel` 的 `well` 变体**（下沉区）与 `SectionHeader` 的计数徽章：控制中心没有用武
  之地，不为了「用上」而加。
- **`MediaControls` 的自动隐藏**（`auto_hide`）：播放器的 OSD 由 Lua 拥有，Dart 侧没有
  绘制权，时机没到（见 `docs/OSD_ARCHITECTURE.md` 的方案 B'）。
- **`PsDetail` / `PsQueue`**：仍只有契约没有消费方。它们是详情抽屉与队列面板的几何，
  等详情页从整页改成抽屉、队列从 Lua 搬回来时才会被读。
