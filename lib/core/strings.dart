/// UI copy. Plain constants: the interface is Chinese-first, and a single file
/// keeps wording consistent across shelves, sheets and dialogs.
abstract final class S {
  static const String appTitle = 'XnX Player';

  /// Compiled fallback. CI passes the resolved version as `APP_VERSION`
  /// (`--dart-define`) and also writes `version.txt` next to the executable;
  /// `resolveAppVersion()` prefers that file so a copied build reports the
  /// version it was packaged as, not the one in the source tree.
  static String appVersion =
      const String.fromEnvironment('APP_VERSION', defaultValue: '0.00.00');

  // Tabs
  static const String tabHome = '主页';
  static const String tabLibrary = '媒体库';
  static const String tabLive = '直播';
  static const String tabSettings = '设置';

  // Control Center. Every entry here must name a thing the player can actually
  // do: the console reference also has 麦克风 / 周边设备 / 游戏基地, but this
  // app has no microphone, no paired accessories and no games, and a dock
  // button that only forwards somewhere else is worse than no button.
  static const String ccHome = '主页';
  static const String ccRecent = '最近';
  static const String ccNotifications = '通知';
  static const String ccSearch = '搜索';
  static const String ccLibrary = '媒体库';
  static const String ccSources = '来源';
  static const String ccSound = '声音';
  static const String ccSubtitle = '字幕';
  static const String ccPicture = '画面';
  static const String ccProfile = '个人资料';
  static const String ccPower = '电源';

  // Shelves
  static const String continueWatching = '继续观看';
  static const String recentlyAdded = '最近添加';
  static const String liveChannels = '直播频道';
  static const String allMedia = '全部媒体';

  // TMDB portal shelves and the genre navigation strip.
  static const String nowPlaying = '正在上映';
  static const String hotMovies = '热门电影';
  static const String hotSeries = '热门剧集';
  static const String airing = '正在播出';
  static const String upcoming = '即将上映';
  static const String trending = '本周趋势';
  static const String recommended = '关联推荐';
  static const String browseByGenre = '浏览电影和剧集';
  static const String genre = '类型';
  static const String allGenres = '全部';
  static const String viewAll = '查看全部';
  static const String moreInfo = '更多信息';
  static const String liveNow = '正在直播';
  static const String seriesRecommend = '剧集推荐';
  static const String forYou = '为你推荐';
  static const String live = '直播';

  // Actions
  static const String play = '播放';
  static const String resume = '继续播放';
  static const String favorite = '收藏';
  static const String favorited = '已收藏';
  static const String openFile = '打开文件';
  static const String refresh = '刷新';
  static const String retry = '重试';
  static const String back = '返回';
  static const String minimize = '最小化';
  static const String maximize = '最大化';
  static const String restoreDown = '向下还原';
  static const String close = '关闭';
  static const String sourcesTitle = '媒体源';
  static const String allSources = '全部来源';
  static const String favoritesShelf = '我的收藏';
  static const String watchingShelf = '正在追剧';
  static const String historyShelf = '观看历史';

  // Library
  static const String sources = '媒体来源';
  static const String addSource = '添加来源';
  static const String editSource = '编辑来源';
  static const String sourceName = '名称';
  static const String sourceUrl = '服务器地址';
  static const String sourceUser = '账号';
  static const String sourcePassword = '密码';
  static const String sourcePath = '文件夹';
  static const String connect = '连接';
  static const String remove = '移除';
  static const String search = '搜索';
  static const String connectHint = '地址以 http:// 或 https:// 开头';
  static const String connecting = '正在连接…';

  // Empty & loading
  static const String loading = '正在载入…';
  static const String emptyTitle = '还没有任何媒体';
  static const String emptyBody = '接入 Emby / Jellyfin、IPTV 订阅、OpenList 或 WebDAV，\n也可以直接打开本地视频文件。';
  static const String noResults = '没有匹配的内容';
  static const String noChannels = '还没有频道';
  static const String noChannelsBody = '添加一个 m3u 订阅，频道会出现在这里。';

  // Errors
  static const String playerError = '无法播放此文件';
  static const String noFile = '还没有选择任何媒体';
  static const String sourceFailed = '连接失败';

  // Settings
  static const String settingsPlayback = '播放';
  static const String settingsPicture = '画面';
  static const String settingsAudio = '音频';
  static const String settingsSystem = '系统';
  static const String quality = '画质档位';
  static const String qualityHint = '高质量档开启 gpu-hq 与更强的缩放算法';
  static const String passthrough = '音频直通';
  static const String passthroughHint = '直接输出原始码流给功放，避免二次解码';
  static const String hdrPassthrough = 'HDR 直通';
  static const String hdrHint = '按显示设备能力输出 HDR，而不是先色调映射到 SDR';
  static const String smoothMotion = '平滑运动';
  static const String smoothMotionHint = '插帧补偿 24p 的抖动';
  static const String deband = '去色带';
  static const String debandHint = '渐变色块上消除阶梯状条纹';
  static const String hardwareDecoding = '硬件解码';
  static const String hardwareHint = '失败时自动回退到软件解码';
  static const String volume = '起始音量';
  static const String subtitleSize = '字幕大小';
  static const String reduceMotion = '减少动效';
  static const String reduceMotionHint = '关闭背景漂移与入场位移';
  static const String skipIntro = '跳过片头';
  static const String runTour = '播放器信息';

  // Metadata service (TMDB). Kept here with the other UI copy so the settings
  // page and the home portal never drift apart in wording.
  static const String settingsMetadata = '元数据服务';
  static const String tmdbApiKey = 'TMDB API Key';
  static const String tmdbConfigured = '已配置';
  static const String tmdbNotConfigured = '未配置';
  static const String tmdbModify = '修改';
  static const String tmdbSetUp = '去设置';
  static const String tmdbSave = '保存';
  static const String tmdbClear = '清除';
  static const String tmdbCancel = '取消';
  static const String tmdbEmptyHint = '请填写 TMDB API Key（v3 Key 或 v4 Read Access Token）';
  static const String tmdbKeyHint = 'v3 API Key 或 v4 Read Access Token';
  static const String tmdbGuide =
      '在 TMDB 官网注册账号，进入「设置 → API」申请 v3 API Key 或 v4 Read Access Token。\n'
      'https://www.themoviedb.org/settings/api';

  // Hints
  static const String hintNavigate = '方向键 移动';
  static const String hintSelect = '回车 选择';
  static const String hintMenu = '右键 选项';
  static const String hintDock = 'Tab 控制中心';
  static const String hintBack = 'Esc 返回';

  static String minutes(int value) => '$value 分钟';

  static String episodes(int value) => '$value 集';
}
