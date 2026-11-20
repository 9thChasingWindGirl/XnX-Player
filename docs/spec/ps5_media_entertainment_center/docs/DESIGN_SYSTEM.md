# 主题与 Design System 规范

## 1. 主题策略

建议建立一个 PS5-inspired 主主题，而不是把 Sony 的具体资产当作主题依赖。

主题由以下层级组成：
- Design Tokens：颜色、间距、圆角、阴影、模糊、字体、动效
- Primitives：Surface、Backdrop、Focus Indicator、Divider、Icon Button
- Components：Card、Shelf、Dialog、Menu、Toast、Hero、Playback Controls
- Patterns：Media Detail、Library Browse、Control Center、Playback OSD
- Screens：Home、Library、Detail、Player、Settings

新增媒体组件必须优先组合现有 Primitives 和 Components。

## 2. 视觉语言

建议保留的特征：
- 深色、低干扰的系统背景
- 以内容图片作为视觉主角
- 层级化 Surface，而非大量硬边框
- 半透明/模糊材质只用于有明确层级意义的面板
- 焦点状态具有清晰轮廓、轻微缩放和层次变化
- 大面积留白与明确的信息层级
- 过渡动画强调空间关系和上下文连续性

避免：
- 每个卡片都使用强烈发光边框
- 所有面板都使用相同程度的模糊
- 过度使用渐变导致文字对比度下降
- 为追求“像主机”而让常用操作隐藏过深
- 将桌面鼠标 hover 与手柄 focus 混为一谈

## 3. Token 类别

请从 ps5-homebrew-ui 的实际源码和设计文档提取准确数值，不要凭截图猜测后直接固化。建议先建立以下 Token：

```text
Color
  background.base
  background.ambient
  surface.primary
  surface.secondary
  surface.overlay
  text.primary
  text.secondary
  text.disabled
  accent.primary
  focus.primary
  feedback.success / warning / error

Spacing
  space.1 ... space.n

Radius
  radius.card
  radius.panel
  radius.pill

Elevation
  shadow.card
  shadow.focus
  shadow.overlay

Material
  blur.subtle
  blur.panel
  opacity.surface
  opacity.scrim

Typography
  display
  title
  heading
  body
  caption
  metadata

Motion
  duration.fast / normal / slow
  curve.standard
  curve.emphasized
  spring.focus
  transition.page
```

## 4. 卡片规范

PosterCard：
- 海报使用固定比例，不因标题长度改变尺寸。
- 标题最多两行，溢出截断。
- 焦点时优先显示完整信息，但不造成列表布局抖动。
- 进度条、已看状态、收藏标识位置统一。
- 焦点缩放应考虑相邻卡片碰撞与裁切。

EpisodeCard：
- 以横向剧照为主，信息层级高于电影卡片。
- 显示 SxxExx、标题、时长和进度。
- 已看、未看、正在观看状态视觉区分明确。

PersonCard：
- 肖像裁切一致。
- 姓名与职业标签层级清楚。
- 不使用与海报卡片相同的图片比例。

## 5. 动效规范

动效分为：
- Focus Motion：焦点进入、离开、连续移动
- Navigation Motion：页面进入/退出、内容区域切换
- Overlay Motion：控制中心、菜单、Dialog、Toast
- Content Motion：背景图、海报、Logo 加载
- Playback Motion：OSD 显隐、时间轴预览

原则：
- 同一类动作使用统一曲线和时长。
- 不在高频操作上使用过长动画。
- 支持减少动态效果设置。
- 动画可中断，连续方向键输入不能排队播放大量过时动画。
- 页面切换应保留空间方向感。

## 6. 材质与性能

Flutter 的 BackdropFilter、模糊和透明叠层需要控制使用范围：
- 避免全屏多层实时模糊。
- 对静态背景优先预处理或使用较轻的遮罩。
- 只对必要面板使用 BackdropFilter。
- 大量海报列表使用合理缓存、裁剪和懒加载。
- 动态背景效果提供低性能模式。
- 在目标 Windows 设备上实测帧时间、内存和 GPU 占用。

## 7. 声音反馈

可建立统一 Interaction Sound Service：
- Focus Move
- Focus Confirm
- Back
- Open / Close Overlay
- Error / Warning
- Notification

声音应短、轻、可关闭，并允许独立调整 UI 音效音量。不要在快速焦点移动时叠加过多音效。
