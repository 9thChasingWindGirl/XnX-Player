# 第三方素材与许可

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
