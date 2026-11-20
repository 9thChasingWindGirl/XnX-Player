# 第三方素材与许可

## 界面音效 — `assets/audio/sfx/glass/`

来源：[ps5-homebrew-ui](https://github.com/leolobato/ps5-homebrew-ui) 的
`assets/audio/sfx/glass/*.wav`（20 个文件）。

- 版权：Copyright (C) 2026 BlackBearReloaded
- 许可：GPL-3.0-or-later（随该项目整体许可分发）
- 生成方式：原项目用 ElevenLabs Sound Effects v2 生成，经其 `tools/process-sfx.py`
  修剪、淡入淡出、响度归一。原项目声明「本仓库没有生成任何音效」，即素材是为
  其 ProsperoEden 项目制作的。

**分发义务**：这些音频文件受 GPL-3.0-or-later 约束。本仓库目前**没有自己的
LICENSE 文件**，因此在公开发布前必须二选一：

1. 整个项目采用 GPL 兼容许可；或
2. 用自有素材替换本目录（推荐，见下）。

替换成本很低，因为代码与文件是解耦的：`lib/core/sound/sound_cue.dart` 只定义
语义（`focus` / `select` / `back` …）与文件名规则 `<cue>_NN.wav`，换一套同命名
的录音即可，不需要改任何 Dart 代码。

## 没有复制的东西

`lib/core/sound/*.dart` 是独立实现：`SoundCue` 枚举沿用了参考项目的语义命名
（这是接口词汇，不是可版权表达），播放后端是自写的 `winmm` waveOut voice 池，
不使用其 C++ 混音器（`src/audio/`）。因此本仓库不包含任何 GPL 代码。
