import 'dart:io';

import 'package:flutter/widgets.dart';

/// Renders a media artwork that can be either a network URL (Emby) or a local
/// file path (a scraped `poster.jpg` sitting next to the video file).
///
/// `Image.network` cannot load a file path, and every library surface
/// (home tiles, hero, hub) used to render the network variant only, which is
/// why locally carried artwork was ignored and cards fell back to the first
/// character of the title.
Widget posterImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  Alignment alignment = Alignment.center,
  ImageErrorWidgetBuilder? errorBuilder,
  bool gapless = false,
  double? width,
  double? height,
}) {
  final bool remote = url.startsWith('http://') || url.startsWith('https://');
  if (remote) {
    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: gapless,
      errorBuilder: errorBuilder,
      width: width,
      height: height,
    );
  }
  return Image.file(
    File(url),
    fit: fit,
    alignment: alignment,
    gaplessPlayback: gapless,
    errorBuilder: errorBuilder,
    width: width,
    height: height,
  );
}
