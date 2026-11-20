import 'package:flutter/widgets.dart';

import 'focus_navigator.dart';
import 'focus_zone.dart';

/// A remembered focus position: an address plus the neighbourhood it was in.
class FocusMark {
  const FocusMark._({this.id, this.zoneId});

  /// The item's stable id, when it had one.
  final String? id;

  /// Its zone, which is the fallback when the exact item is gone.
  final String? zoneId;

  bool get isEmpty => id == null && zoneId == null;
}

/// Remembers where focus was, so a surface can come back to the same place.
///
/// Two mechanisms, because they answer different questions:
///
/// * **automatic** — [install] watches the focus owner and keeps the last
///   settled position. Switching tabs and coming back calls [resume] with no
///   arguments, so eleven widgets do not each need a `capture()` call.
/// * **explicit** — [mark] before opening an overlay, [restore] when it
///   closes. An overlay is opened *while* focus is still on the opener, so
///   this is the only moment the position can be read.
///
/// Recovery degrades in three steps rather than failing: exact id → the zone
/// the item lived in → the first focusable. A list that reloaded into a
/// different shape still lands somewhere sensible.
class FocusMemory {
  FocusMemory._();

  static final FocusMemory instance = FocusMemory._();

  FocusMark _last = const FocusMark._();

  bool _installed = false;
  bool _suspended = false;

  /// Starts tracking. Safe to call twice.
  void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    FocusManager.instance.addListener(_record);
  }

  void uninstall() {
    if (!_installed) {
      return;
    }
    _installed = false;
    FocusManager.instance.removeListener(_record);
  }

  /// The most recent position that had a name or a zone.
  FocusMark get last => _last;

  void _record() {
    if (_suspended) {
      return;
    }
    final FocusEntry? entry =
        FocusRegistry.instance.entryFor(FocusManager.instance.primaryFocus);
    if (entry == null) {
      return;
    }
    if (entry.id == null && entry.zoneId == null) {
      return;
    }
    _last = FocusMark._(id: entry.id, zoneId: entry.zoneId);
  }

  /// Snapshots the current position. Call this *before* moving focus away.
  FocusMark mark() {
    _record();
    return _last;
  }

  /// Returns focus to [mark] (or to the last settled position when omitted).
  ///
  /// Returns false only when nothing could be focused at all, which means the
  /// caller's surface is gone rather than merely rearranged.
  bool restore([FocusMark? mark]) {
    final FocusMark target = mark ?? _last;
    // Writing focus would otherwise feed straight back into _record and lose
    // the mark we are trying to return to.
    _suspended = true;
    try {
      final String? id = target.id;
      if (id != null && FocusNavigator.focusById(id)) {
        return true;
      }
      final String? zoneId = target.zoneId;
      if (zoneId != null && FocusNavigator.focusIn(zoneId)) {
        return true;
      }
      return FocusNavigator.focusFirst();
    } finally {
      _suspended = false;
    }
  }

  /// Convenience for tab switches: come back to where the user was, falling
  /// back to [fallbackZone] when that item no longer exists.
  bool resume({String? fallbackZone}) {
    final FocusMark target = _last;
    _suspended = true;
    try {
      final String? id = target.id;
      if (id != null && FocusNavigator.focusById(id)) {
        return true;
      }
      final String? zoneId = fallbackZone ?? target.zoneId;
      if (zoneId != null && FocusNavigator.focusIn(zoneId)) {
        return true;
      }
      return FocusNavigator.focusFirst();
    } finally {
      _suspended = false;
    }
  }

  @visibleForTesting
  void clear() {
    _last = const FocusMark._();
  }
}
