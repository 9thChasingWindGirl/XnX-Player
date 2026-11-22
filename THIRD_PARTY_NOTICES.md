# 第三方素材与许可

本程序按 GNU General Public License v3.0 or later 分发（见仓库根目录 `LICENSE`）。
下面分开列出**随包分发的第三方二进制**与**随包分发的第三方素材**：前者是许可义务
最重的一类，因为用户拿到了别人的编译产物。

## 播放内核 — `libmpv-2.dll`

播放由 mpv 内核完成。`libmpv-2.dll` 放在程序目录，由 `lib/playback/mpv/mpv_dll.dart`
经 `LoadLibrary` 动态加载，不静态链接，也未修改其源码或二进制。

- **构建来源**：[zhongfly/mpv-winbuild](https://github.com/zhongfly/mpv-winbuild) 的
  GitHub Actions 产物，由 `tool/fetch_libmpv.dart` 在构建时下载。
- **选取的资产**：`mpv-dev-lgpl-x86_64-<日期>-git-<提交>.7z`，即该仓库的 LGPL 变体。
  它按 `-Dgpl=false` 构建、禁用 LGPL 不兼容组件，并把 FFmpeg 以 LGPLv3 静态链接进
  同一个 DLL —— 该仓库 README 的原话是：
  > `mpv-dev-lgpl-xxxx.7z` is libmpv under LGPLv2.1+ license, which disables
  > LGPLv2.1+ incompatible packages and statically links to ffmpeg under LGPLv3.
- **因此随包 DLL 的许可**：libmpv **LGPL-2.1-or-later**，FFmpeg **LGPL-3.0-or-later**。
- **另一种可能**：同一 release 里的 `mpv-dev-x86_64-…`（名字不带 `lgpl`）是
  **GPL-2.0-or-later**（mpv 与 FFmpeg 均为 GPL）。本项目优先选 LGPL 变体，但若上游
  某天只保留 GPL 变体，脚本会回退到它，并把**实际**许可写进 `libmpv-SOURCE.txt`
  （仓库内为 `third_party/mpv/SOURCE.txt`，构建时生成，随包分发）。要判断某个发行版
  用的是哪一个，看包里这份文件，不要只看本文。
- **`-v3` 变体一律不用**：它为 AVX2 编译，在较老 CPU 上会于 `mpv_create` 阶段失败，
  用户无法把它和安装损坏区分开。脚本宁可让构建失败，也不静默选它。

**分发义务**：

- 许可副本随包提供：`licenses/LGPL-2.1.txt`、`licenses/LGPL-3.0.txt`
  （若某次构建回退到 GPL 变体，则对应 `licenses/GPL-2.0.txt`）。这三份文本都随
  安装包与便携版一起分发。
- 可替换性（LGPL 的核心要求）：程序不校验 DLL 签名、不做自校验，把
  `libmpv-2.dll` 换成你自己编译的版本即可生效。
- 对应源码：[mpv](https://github.com/mpv-player/mpv)、
  [FFmpeg](https://ffmpeg.org/download.html)、
  [构建脚本](https://github.com/zhongfly/mpv-winbuild)。每个 release 的 tag 形如
  `2026-11-22-09cf7a11f2`，末段即 mpv 的提交哈希，可据此重建同一版本。
- 该 DLL 内各静态依赖的完整清单与许可，以上游 release 内附文件为准。本项目只分发
  构建产物、不分发这些库的源码；需要与某个发行版完全对应的源码快照时，按上面给出
  的仓库与 tag 自行取用，或在本项目仓库提 issue 索取。

## 界面音效 — `assets/audio/sfx/glass/`

来源：[ps5-homebrew-ui](https://github.com/leolobato/ps5-homebrew-ui) 的
`assets/audio/sfx/glass/*.wav`（20 个文件）。

- 版权：Copyright (C) 2026 BlackBearReloaded
- 许可：GPL-3.0-or-later（随该项目整体许可分发）
- 生成方式：原项目用 ElevenLabs Sound Effects v2 生成，经其 `tools/process-sfx.py`
  修剪、淡入淡出、响度归一。原项目声明「本仓库没有生成任何音效」，即素材是为
  其 ProsperoEden 项目制作的。

**分发义务**：这些音频文件受 GPL-3.0-or-later 约束。本项目整体按
GNU General Public License v3.0 or later 分发（见仓库根目录的 `LICENSE`），
因此与上述素材的许可兼容；安装包在安装向导中展示同一份许可文本。

若要改用自有素材，成本也很低：代码与文件是解耦的，`lib/core/sound/sound_cue.dart`
只定义语义（`focus` / `select` / `back` …）与文件名规则 `<cue>_NN.wav`，换一套
同命名的录音即可，不需要改任何 Dart 代码。

## TMDB 元数据与图片

门户数据（海报、剧照、简介、评分、题材、演职员）来自 [TMDB](https://www.themoviedb.org/)，图片来自 `image.tmdb.org`。

> This product uses the TMDB API but is not endorsed or certified by TMDB.
> 本产品使用 TMDB API，但未获得 TMDB 的认可或认证。

本仓库不包含 TMDB 的代码或媒体文件；运行时按用户自己配置的 API Key 请求数据。

## 没有复制的东西

`lib/core/sound/*.dart` 是独立实现：`SoundCue` 枚举沿用了参考项目的语义命名
（这是接口词汇，不是可版权表达），播放后端是自写的 `winmm` waveOut voice 池，
不使用其 C++ 混音器（`src/audio/`）。因此本仓库不包含任何 GPL 代码。
