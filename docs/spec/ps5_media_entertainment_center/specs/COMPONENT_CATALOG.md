# 组件目录与扩展清单

状态说明：
- **Reuse**：优先复用参考项目已有设计/组件概念，Flutter 端按实际代码移植或重写。
- **Extend**：在现有视觉模式上扩展媒体语义。
- **New**：媒体中心需要新增的专用组件。

| 组件 | 状态 | 所属域 | 职责 |
|---|---|---|---|
| Surface / Glass Panel | Reuse | Primitives | 面板材质、层级 |
| Focus Indicator | Reuse | Primitives | 统一焦点反馈 |
| Animated Container | Reuse | Primitives | 统一状态动画 |
| Hero Panel | Extend | Discovery | 电影/剧集主视觉 |
| Media Shelf | Extend | Discovery | 横向内容架 |
| Poster Card | New/Extend | Media | 电影海报卡片 |
| Episode Card | New | Media | 剧集卡片 |
| Person Card | New | People | 演职员卡片 |
| Collection Card | New | Collections | 合集卡片 |
| Media Detail Hero | New | Details | 背景、Logo、信息和操作 |
| Season Selector | New | Series | 季切换 |
| Episode List | New | Series | 集列表 |
| Credits Carousel | New | Details | 演职员横向列表 |
| Related Media Shelf | Extend | Details | 关联作品 |
| Continue Watching Shelf | Extend | Home | 继续观看 |
| Playback OSD | New | Player | 播放控制层 |
| Timeline Scrubber | New | Player | 时间轴和预览 |
| Audio Track Menu | New | Player | 音轨选择 |
| Subtitle Menu | New | Player | 字幕选择与设置 |
| Chapter Navigator | New | Player | 章节导航 |
| Playback Info Panel | New | Player | 技术播放信息 |
| Next Episode Card | New | Player | 下一集提示 |
| Playback Queue | Extend | Player | 播放队列 |
| Control Center | Reuse/Extend | Shell | 全局快捷控制 |
| Notification Toast | Reuse/Extend | Shell | 系统反馈 |
| Settings Panel | Reuse/Extend | Settings | 设置与偏好 |

## 组件契约

每个组件至少定义：
- 语义职责
- 数据输入模型
- 焦点行为
- 鼠标行为
- loading / empty / error 状态
- 动画状态
- 最小尺寸与响应式行为
- 图片比例与裁切策略
- 可访问性标签
- 是否可被主题覆盖

## 组件优先级

P0：
- Focus Indicator、Surface、Media Shelf、Poster Card、Media Detail Hero、Playback OSD、Timeline Scrubber

P1：
- Episode Card、Season Selector、Credits Carousel、Audio/Subtitle Menu、Control Center 媒体扩展

P2：
- Person Detail、Collections、推荐、预告片、章节缩略图、媒体技术诊断
