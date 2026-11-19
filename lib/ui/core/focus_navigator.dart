import 'package:flutter/widgets.dart';

import '../../design/ps_tokens.dart';
import 'focus_zone.dart';

enum NavDir { up, down, left, right }

/// Geometric focus navigation for a ten-foot UI.
///
/// Score = axial gap + perpendicular offset * (overlap ? 0.1 : 2.5), plus a
/// small bonus for candidates inside the current zone. This is the same formula
/// the reference 10-foot clients converged on: gap dominates, and elements that
/// line up with the current one are strongly preferred over diagonal ones.
class FocusNavigator {
  const FocusNavigator._();

  static const double _overlapTolerance = 24;
  static const double _crossWeightAligned = 0.1;
  static const double _crossWeightOffset = 2.5;
  static const double _sameZoneBonus = 12;

  static bool move(NavDir dir) {
    final FocusRegistry registry = FocusRegistry.instance;
    registry.prune();

    final List<FocusEntry> candidates = registry.entries
        .where((FocusEntry entry) => entry.node.canRequestFocus)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return false;
    }

    final FocusEntry? from = registry.entryFor(FocusManager.instance.primaryFocus);
    if (from == null) {
      focusFirst();
      return true;
    }

    final Rect? fromRect = from.rect;
    if (fromRect == null) {
      return false;
    }

    FocusEntry? best;
    double bestScore = double.infinity;

    for (final FocusEntry entry in candidates) {
      if (identical(entry.node, from.node)) {
        continue;
      }
      final Rect? rect = entry.rect;
      if (rect == null) {
        continue;
      }
      final double? score = _score(
        fromRect,
        rect,
        dir,
        sameZone: entry.zoneId != null && entry.zoneId == from.zoneId,
      );
      if (score == null || score >= bestScore) {
        continue;
      }
      bestScore = score;
      best = entry;
    }

    if (best == null) {
      return false;
    }
    best.node.requestFocus();
    reveal(best);
    return true;
  }

  static bool focusFirst() {
    final FocusRegistry registry = FocusRegistry.instance;
    registry.prune();
    for (final FocusEntry entry in registry.entries) {
      if (entry.node.canRequestFocus) {
        entry.node.requestFocus();
        reveal(entry);
        return true;
      }
    }
    return false;
  }

  /// Requests focus for [entry] and scrolls it into view.
  static void reveal(FocusEntry entry) {
    if (!entry.context.mounted) {
      return;
    }
    Scrollable.ensureVisible(
      entry.context,
      duration: PsMotion.reveal,
      curve: PsMotion.out,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      alignment: 0.5,
    );
  }

  static double? _score(
    Rect from,
    Rect to,
    NavDir dir, {
    required bool sameZone,
  }) {
    double primary;
    double cross;
    bool overlapping;

    switch (dir) {
      case NavDir.left:
        if (to.center.dx >= from.center.dx - 1) {
          return null;
        }
        primary = from.left - to.right;
        cross = (to.center.dy - from.center.dy).abs();
        overlapping = to.top < from.bottom && to.bottom > from.top;
        break;
      case NavDir.right:
        if (to.center.dx <= from.center.dx + 1) {
          return null;
        }
        primary = to.left - from.right;
        cross = (to.center.dy - from.center.dy).abs();
        overlapping = to.top < from.bottom && to.bottom > from.top;
        break;
      case NavDir.up:
        if (to.center.dy >= from.center.dy - 1) {
          return null;
        }
        primary = from.top - to.bottom;
        cross = (to.center.dx - from.center.dx).abs();
        overlapping = to.left < from.right && to.right > from.left;
        break;
      case NavDir.down:
        if (to.center.dy <= from.center.dy + 1) {
          return null;
        }
        primary = to.top - from.bottom;
        cross = (to.center.dx - from.center.dx).abs();
        overlapping = to.left < from.right && to.right > from.left;
        break;
    }

    if (primary < -_overlapTolerance) {
      return null;
    }

    final double gap = primary < 0 ? 0 : primary;
    final double crossWeight = overlapping ? _crossWeightAligned : _crossWeightOffset;
    return gap + cross * crossWeight + (sameZone ? 0 : _sameZoneBonus);
  }
}
