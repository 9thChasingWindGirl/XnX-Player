# OSD 架构：谁拥有状态，谁拥有像素

> 结论先行：**OSD 继续由 ASS 画在 mpv 里，但状态与命中全部搬到 Dart。**
> 不是"再想想"，是三种方案里唯一同时满足「HDR 正确」和「交互模型唯一」的。

---

## 一、现状为什么必须改

现在播放页有两套交互模型并存：

| | Flutter 侧 | Lua 侧 |
|---|---|---|
| 焦点 | `FocusNavigator` 几何寻路 | 自己算 hitbox |
| 高亮 | `focus_highlight` 弹簧滑动 | ASS 矩形直接切 |
| 按键 | `InputRouter` → `InputAction` | 自己的键表 |
| 坐标 | 逻辑像素 | 1920×1080 设计像素，**换算两次** |

已经付过的账：

- `to_design()` 的 x/y 曾共用同一个 scale，导致「进度条要点上面一点」（`player_osd.lua`）。
- 鼠标完全失效：mpv 子 HWND 收不到事件，必须 Flutter 捕获再转发（`mpv_options.dart` 里 `input-cursor: no`、`input-vo-keyboard: no`）。
- `osd_keys.dart` 是一张**只为转发而存在**的键名表：把物理键映射成 mpv 键名，mpv 再解析回命令。

这不是"两套代码"，是**两套真相**。任何一侧改了布局，另一侧的命中就错。

---

## 二、三个方案，两个淘汰

### 方案 C：OSD 搬到 Flutter（淘汰，理由是画不对）

技术上可行：mpv 用 `--vo=gpu-next --gpu-api=d3d11` 渲染到 D3D11 纹理，通过 `FlutterDesktopGpuSurfaceDescriptor` 注册成 Flutter `Texture`，OSD 就是普通 Flutter widget。工程量大但做得到。

**但本项目不能这么做**，原因是物理的，不是工程的：

1. `mpv_options.dart:189` 设了 `target-colorspace-hint: auto`。mpv 在 `vo=gpu-next` 下把 BT.2020/PQ 元数据直接交给 D3D11 swapchain，显示器进 HDR 模式。Flutter Windows 目前只输出 SDR 表面。
2. 一旦 OSD 是 Flutter 图层，它就活在 SDR 空间里。HDR 片源下：白字按 SDR 白（~100 nit）输出，而视频亮部可能到 1000 nit → **控件比画面暗一档，发灰**；反过来如果做亮度补偿，又会在暗场里过曝。
3. Dolby Vision 走 mpv 的 `gpu-next` + libplacebo 动态元数据重映射，任何外挂的 UI 图层都不在这个管线里，无法用同一套 tone-mapping 曲线。
4. 还要放弃 mpv 的截图含 OSD、ASS 字幕与 OSD 同层合成、以及 `sub-font` 这一整套免费能力。

> 判据不是"代码更 Flutter"，而是"像素在正确的色彩空间里"。这一条 P5 客体的核心体验，不能为了让代码好看而牺牲。

### 方案 A：维持现状（淘汰，理由是把 bug 固化）

Lua 同时拥有状态、命中、渲染。每加一个控件都要在 Lua 里重算 hitbox、重写一次键盘分支。上面三笔账会继续记下去。

### 方案 B'：Dart 拥有状态与命中，Lua 只画（采用）

和审计里的方案 B 相比，B' 多做一件关键的事：**把布局从 Lua 里抠出来，变成两边共读的数据文件**。

- Dart 侧：`OsdState`（可见性、悬停项、菜单栈、进度、徽章）+ `OsdLayout`（从 JSON 读出的矩形表）。命中判定 = 在 `OsdLayout` 的矩形上跑，与 `FocusNavigator` 用的是同一套几何。
- Lua 侧：`assets/mpv/osd_layout.json` 只提供**像素**，`osd-state` 消息只提供**状态**。脚本里不再有 `if x > 100 and x < 250` 这种判断。
- 坐标只定义一次。`to_design()` 那种两轴各自缩放的问题从根上消失——因为 Dart 只发设计坐标，Lua 只按 `osd-dimensions` 缩放一次。

---

## 三、契约

### 3.1 布局表（单一真相）

`assets/mpv/osd_layout.json`，1920×1080 设计坐标，Dart 与 Lua 共读：

```json
{
  "design": [1920, 1080],
  "bar":   { "x": 120, "y": 952, "w": 1680, "h": 96 },
  "transport": [
    { "id": "prev",  "x": 120,  "y": 984, "w": 56, "h": 56 },
    { "id": "back10","x": 192,  "y": 984, "w": 56, "h": 56 },
    { "id": "play",  "x": 264,  "y": 976, "w": 72, "h": 72 },
    { "id": "fwd10", "x": 352,  "y": 984, "w": 56, "h": 56 }
  ],
  "seek":  { "x": 440, "y": 1004, "w": 1080, "h": 12, "hit": 32 },
  "menus": [
    { "id": "audio",    "x": 1544, "y": 984, "w": 44, "h": 44 },
    { "id": "subtitle", "x": 1596, "y": 984, "w": 44, "h": 44 }
  ],
  "popup": { "x": 1200, "y": 380, "w": 560, "h": 540, "rowH": 44 }
}
```

规则：

- 只有 Dart 写它（生成/校验），Lua 只读。`tool/osd_layout_check.py` 校验矩形不重叠、不越界、`hit` ≥ 视觉高度。
- Lua 用 `mp.utils.parse_json` 读，路径通过 `script-opts/osd-layout-path` 传入（与 `formatLogoDir` 同一套路，见 `mpv_options.dart` 的 `script-opts`）。
- 新增控件 = 加一行 JSON + Dart 侧画法，**不改 Lua 的命中逻辑**（已经没有命中逻辑了）。

### 3.2 状态消息（`script-message osd-state <json>`）

```json
{
  "visible": true,
  "focused": "play",
  "menus": ["audio"],
  "menuIndex": 3,
  "time": 4231.5,
  "duration": 7200,
  "paused": false,
  "dragging": false,
  "hover": null,
  "badges": [{"slug": "hdr10", "tier": "lit"}, {"slug": "dts", "tier": "dim"}],
  "toast": {"text": "音量 75", "until": 4233.0}
}
```

Lua 收到即重建 ASS 事件（**仅状态变化时**，不再每帧重建——顺带把现在的每帧字符串拼接开销砍掉）。

### 3.3 上行事件（`script-message-to` → Dart）

只保留**事实**，不保留决策：

| 消息 | 含义 | Dart 收到后 |
|---|---|---|
| `osd:moved` | 鼠标在设计坐标里移动 | 更新 hover，必要时重发状态 |
| `osd:click` | 设计坐标 + 键 | 命中 → 改状态 / 调 mpv 命令 |
| `osd:wheel` | 设计坐标 + 方向 | 命中进度条 → seek |
| `osd:fact` | `video-out-params`/`audio-out-params` 变化 | 重算徽章档位 |

「点了哪里」是事实，「该 seek 到哪里」是决策——决策留在 Dart。

### 3.4 保留在 Lua 的部分（有意为之）

- ASS 文本测量与排版（`measure`/`text`/`rrect_path`）——只有 Lua 知道 libass 的真实字宽。
- `overlay-add` 的起播徽章位图（BGRA 预渲染，6 级 alpha）。
- 缓存的着色器/图形细节：羽化 scrim、描边、三角。
- **不保留**：hitbox、键盘分支、菜单开合状态、拖动状态、toast 生命周期。

---

## 四、迁移步骤（每步一次 CI）

| 步 | 内容 | 可验证 |
|---|---|---|
| S1 | 抽 `osd_layout.json` + Dart 侧 `OsdLayout` 解析；Lua 读它替换硬编码常量，行为不变 | 探针 `tool/osd_probe.py` 全绿（点击/拖动/滚轮数值与现在一致） |
| S2 | Dart 侧 `OsdState` + `OsdController`（订阅 mpv 属性，维护可见性/toast/拖动） | 单元测试：状态机序列 |
| S3 | 把命中从 Lua 挪到 Dart：`osd:click` 只报坐标，Dart 算命中后发命令 | 探针改为断言「坐标 → 期望命令」 |
| S4 | 删除 Lua 的键表与 mbtn/wheel 分支，`osd_keys.dart` 缩成菜单导航用的少量映射 | 全仓无 `osd_keys` 的物理键直传 |
| S5 | 菜单栈与焦点统一走 `FocusNavigator` 语义（键盘与手柄同一套） | 手柄在 OSD 里可导航（需真手柄） |

S1 不改变任何行为，风险最低，先做。

---

## 五、这套方案换来了什么

1. **坐标只定义一次**。`to_design` 两轴缩放的坑没有复发的可能。
2. **交互只剩一套**。hover、菜单栈、拖动、键盘重复全在 Dart，与首页/详情页共享 `InputRouter` 和 `FocusNavigator`。
3. **HDR 不受影响**。像素仍在 mpv 的 swapchain 里，`target-colorspace-hint` 继续有效。
4. **Lua 从 2536 行降到预计 ~900 行**（只剩绘制原语与 ASS 拼装），维护面缩小一半以上。
5. 未来若要换渲染器（比如迁到 `vo=gpu-next` 的 shader 叠加），只需替换 Lua 那一层，Dart 的 `OsdState`/`OsdLayout` 不动。

---

## 六、已知代价

- 每次状态变化跨一次 IPC（`script-message`）。实测延迟在 1–3 ms 量级，远低于一帧；拖动进度条时按帧合并发送即可。
- 布局表与绘制实现可能脱节（JSON 改了、Lua 没改画法）。靠 `osd_layout_check.py` 只能校验几何，画法仍需目视——所以探针要保留「渲染预览」（`tool/osd_render.py`）。
