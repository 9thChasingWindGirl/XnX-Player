/// UI copy. Plain constants: the interface is Chinese-first, and a single file
/// keeps wording consistent across shelves, sheets and dialogs.
abstract final class S {
  static const String appTitle = 'XnX Player';

  /// 与 CI 的 `APP_VERSION` 保持一致（第一位=大型迭代，第二位=轻版本迭代，
  /// 第三位=hotfix）。0.00.00 表示核心工作尚未完成、只有 Actions 产物。
  static const String appVersion = '0.00.00';

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

  // Actions
  static const String play = '播放';
  static const String resume = '继续播放';
  static const String favorite = '收藏';
  static const String favorited = '已收藏';
  static const String openFile = '打开文件';
  static const String refresh = '刷新';
  static const String retry = '重试';
  static const String back = '返回';

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

  // Hints
  static const String hintNavigate = '方向键 移动';
  static const String hintSelect = '回车 选择';
  static const String hintMenu = '右键 选项';
  static const String hintDock = 'Tab 控制中心';
  static const String hintBack = 'Esc 返回';

  static String minutes(int value) => '$value 分钟';

  static String episodes(int value) => '$value 集';
}
