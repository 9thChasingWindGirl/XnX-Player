import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Lays the whole app out on a fixed 1920x1080 design canvas and scales it to
/// whatever the window size is. Ten-foot UIs are far easier to keep consistent
/// this way than with breakpoints: every page can assume 1920x1080 coordinates.
class TvScale extends StatelessWidget {
  const TvScale({super.key, required this.child});

  final Widget child;

  static const double designWidth = 1920;
  static const double designHeight = 1080;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : designWidth;
        final double height = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : designHeight;

        final double scale = math.min(width / designWidth, height / designHeight);
        final Size logical = Size(width / scale, height / scale);

        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: logical.width,
            height: logical.height,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: logical),
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// Design-space width for the current window.
  static double widthOf(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return size.width;
  }

  static double heightOf(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return size.height;
  }
}
