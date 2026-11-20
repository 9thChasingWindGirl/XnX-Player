# 沉浸式元数据与媒体详情体验

这是本产品区别于普通视频播放器的核心能力。媒体详情页应被视为一段内容体验，而不是一个堆满字段的属性窗口。

## 1. 详情页视觉结构

推荐从上到下分为：

1. Cinematic Backdrop：横向背景图，带渐变遮罩；支持低强度动态位移/景深效果，但不能影响文字可读性。
2. Identity Block：作品 Logo（若有）、标题、原名、年份、年龄分级、时长、类型、评分。
3. Primary Actions：播放/继续观看、从头播放、加入收藏、标记已看、更多操作。
4. Synopsis：简介，默认显示适当长度，可展开全文。
5. Progress / Resume：已观看进度、继续观看位置；对剧集显示季/集进度。
6. Seasons & Episodes：剧集季选择器与集列表。
7. Cast & Crew：演员、导演、编剧、摄影、配乐等人物卡片。
8. Related Content：同系列、相似作品、同一人物其他作品。
9. Technical Details：分辨率、HDR、视频编码、音频格式、字幕轨道等；默认折叠或放在次级面板。

## 2. 电影详情

建议信息优先级：
- 标题与作品 Logo
- 年份、片长、类型、分级、评分
- 简介
- 播放/继续观看
- 导演、主要演员
- 制作国家/地区、上映日期
- 预告片（若来源和版权允许）
- 技术媒体信息
- 相似作品与关联合集

不要把所有元数据同时放在首屏。首屏应让用户迅速判断“这是什么、是否想看、如何开始”。

## 3. 剧集与动画详情

剧集详情需体现层级：
- Series：系列总览、背景图、简介、总季数、年份范围
- Season：季选择器、季简介（可选）、集数
- Episode：集标题、集简介、剧照、时长、播出日期、观看进度

Episode Card 建议展示：
- 集数编号（S01E03）
- 标题
- 横向剧照
- 时长
- 简介摘要
- 已观看/正在观看状态
- 下一集或继续播放标识

播放完当前集时提供 Next Episode Card。自动连播应可配置，并提供取消倒计时操作。

## 4. 人物详情

人物页是媒体发现的重要入口：
- 人物肖像（缺失时使用统一占位视觉）
- 姓名、职业标签
- 简介/传记
- 代表作品
- 参与作品列表
- 在当前媒体库中的关联作品

人物卡片的焦点行为应与 PosterCard 一致，但比例、信息密度和图片裁切方式可单独定义。

## 5. 海报与图片类型

应区分图片语义，不能把同一张图随意拉伸到所有位置：
- Poster：竖版海报，用于网格和小卡片
- Backdrop：横版背景，用于 Hero 和详情页
- Logo：透明标题 Logo，用于 Hero 身份区域
- Still：剧照，用于剧集卡片、章节或预览
- Person Portrait：人物肖像
- Thumb：时间轴缩略图

图片加载策略：
- 优先加载当前视口与焦点项
- 焦点项可提高图片清晰度
- 预取横向列表前后相邻项目
- 使用占位骨架和渐进式淡入
- 错误图使用统一 fallback，不显示破碎图标
- 背景图必须有足够暗度/渐变保障文本对比度

## 6. 元数据来源与数据模型

建议将媒体实体与来源适配器解耦：

```dart
class MediaItem {
  final String id;
  final MediaType type;
  final String title;
  final String? originalTitle;
  final int? year;
  final Duration? runtime;
  final String? overview;
  final String? posterUri;
  final String? backdropUri;
  final String? logoUri;
  final double? communityRating;
  final String? contentRating;
  final List<String> genres;
  final List<Credit> credits;
  final PlaybackProgress? progress;
  final TechnicalMetadata? technical;
}
```

这只是概念模型。实际项目应根据媒体服务器 API、文件扫描结果和本地缓存设计 DTO，再映射到领域模型。

元数据策略：
- 来源适配器负责连接 Emby/Jellyfin/Plex 或本地元数据服务。
- Repository 负责合并、缓存、冲突处理和分页。
- Domain Model 不应直接暴露某一家服务端的 JSON 字段。
- 图片 URL、认证信息和临时访问令牌不得散落在 Widget 中。
- 缺失字段应为 nullable，并提供明确的 UI fallback。
- 用户手动修正的元数据应有优先级与来源标记。

## 7. 焦点与详情页行为

- 页面初次进入时，焦点落在主要操作按钮或上次记忆的位置。
- 向下移动进入内容区；向上可回到 Hero 操作区。
- 演职员横向列表应支持左右导航，并能明确回到所属区域。
- 展开简介、技术信息等折叠区后，焦点应进入展开内容。
- 图片背景异步变化不能导致焦点或布局突然跳动。
