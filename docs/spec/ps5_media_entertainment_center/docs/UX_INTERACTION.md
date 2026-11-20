# 交互模型：主机级 Shell

## 1. 输入优先级

主要支持：
1. Xbox / XInput 类游戏手柄
2. 键盘方向键、Enter、Escape、媒体键
3. Windows 遥控器或兼容 HID 输入
4. 鼠标与触控板

不同输入设备应映射到统一的抽象动作，而不是每个页面各自监听原始按键。

建议抽象动作：
- NavigateUp / Down / Left / Right
- Confirm
- Back
- ContextMenu
- Home
- PlayPause
- SeekForward / SeekBackward
- VolumeUp / VolumeDown
- ToggleControlCenter

## 2. 焦点系统

建立 Focus Manager，管理：
- 当前焦点 ID
- 焦点所属区域
- 区域内空间导航关系
- 页面焦点记忆
- Overlay 焦点栈
- 焦点不可用时的 fallback
- 鼠标与手柄输入模式切换

不能只依赖 Tab 顺序。媒体中心的布局常有不规则网格、横向 Shelf 和浮层，需要空间导航策略。

## 3. Overlay 契约

打开 Overlay 时：
1. 记录当前页面、焦点 ID 和滚动位置。
2. 将焦点移动到 Overlay 的默认操作项。
3. 限制方向导航在 Overlay 范围内（除非明确设计为跨层导航）。
4. Back/Escape 关闭当前层。
5. 关闭后恢复原焦点；若原组件已销毁，则选择最近的有效焦点。

Overlay 类型：
- Control Center
- Context Menu
- Audio / Subtitle Selector
- Search Panel
- Confirmation Dialog
- Notification Detail

## 4. 控制中心

建议从屏幕底部或侧边呼出，采用与 PS5 控制中心相近的卡片式快捷入口。媒体场景优先提供：
- 当前播放状态
- 播放/暂停与跳转
- 音轨/字幕快捷入口
- 播放队列
- 播放设备/音频输出
- 媒体信息
- 设置快捷入口

控制中心不能复制完整播放器 OSD；两者职责不同：
- OSD：围绕当前画面进行直接播放控制。
- Control Center：跨页面、跨播放状态的系统快捷控制。

## 5. 鼠标模式

- Hover 不应自动改变手柄焦点，除非进入鼠标输入模式。
- 鼠标点击控件后可同步焦点。
- 鼠标离开后不要无故重置焦点。
- 鼠标与手柄切换时应保留合理的当前上下文。
