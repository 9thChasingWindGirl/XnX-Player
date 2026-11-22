import 'dart:ui';

/// Window sizing policy, kept pure so the numbers can be tested headlessly.
///
/// A player whose chrome is laid out in a 16:9 design space must not be freely
/// resizable into a 3:1 strip: the bottom band collapses and the seek bar
/// lands under the pointer only by accident. We therefore constrain the ratio
/// in the window manager and pick a sensible starting size from a small table
/// of common resolutions.
abstract final class WindowSizing {
  /// 16:9 — the OSD design space, and the shape of virtually every video.
  static const double aspect = 16 / 9;

  /// Below this the chrome has no room for title, badges, seek and transport.
  static const Size minimum = Size(960, 540);

  /// Preferred windowed sizes, largest first. Each is a 16:9 step that maps to
  /// a real display resolution; the app picks the largest that fits the work
  /// area with margin to spare.
  static const List<Size> preferred = <Size>[
    Size(1920, 1080),
    Size(1600, 900),
    Size(1440, 810),
    Size(1280, 720),
    Size(1152, 648),
    Size(960, 540),
  ];

  /// Pixels kept clear around the window so the taskbar/dock stays usable.
  static const double margin = 96;

  /// Largest preferred size that fits [workArea], or [minimum] when even the
  /// smallest step does not fit (a small laptop screen).
  static Size fit(Size workArea) {
    final double availableW = workArea.width - margin * 2;
    final double availableH = workArea.height - margin * 2;
    for (final Size candidate in preferred) {
      if (candidate.width <= availableW && candidate.height <= availableH) {
        return candidate;
      }
    }
    // Keep the aspect ratio even when the screen is genuinely tiny: shrink
    // the minimum until it fits rather than returning an out-of-bounds size.
    final double scale = availableW > 0 && availableH > 0
        ? (availableW / minimum.width).clamp(0.0, 1.0) <
                (availableH / minimum.height).clamp(0.0, 1.0)
            ? (availableW / minimum.width).clamp(0.0, 1.0)
            : (availableH / minimum.height).clamp(0.0, 1.0)
        : 1.0;
    return Size(minimum.width * scale, minimum.height * scale);
  }

  /// Clamps an arbitrary size back to [aspect], preserving the larger edge.
  ///
  /// The window manager applies the ratio itself; this is the fallback for
  /// platforms where it is unavailable, and for tests.
  static Size clampAspect(Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return minimum;
    }
    final double byWidth = size.width / aspect;
    final Size fromWidth = Size(size.width, byWidth);
    final Size fromHeight = Size(size.height * aspect, size.height);
    final Size pick = byWidth >= size.height ? fromWidth : fromHeight;
    return Size(
      pick.width < minimum.width ? minimum.width : pick.width,
      pick.height < minimum.height ? minimum.height : pick.height,
    );
  }
}
