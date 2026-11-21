import 'package:flutter/foundation.dart';

/// How loud a notice is. Drives the icon and colour in the panel.
enum NoticeKind { info, success, warning, error }

/// One entry in the notification centre.
///
/// A one-shot notice ("source connected") and a live activity ("downloading
/// update 42 %") share the same type because the user reads them in one place.
/// [progress] is what tells them apart: null means finished.
class Notice {
  Notice({
    required this.id,
    required this.title,
    this.body = '',
    this.kind = NoticeKind.info,
    this.progress,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  String title;
  String body;
  NoticeKind kind;

  /// 0..1 while the task runs; null once it finished or failed.
  double? progress;

  DateTime createdAt;
  bool read;

  bool get active => progress != null;
}

/// The app's single notification centre.
///
/// Everything the user would otherwise have to infer from a silent screen goes
/// here: background refreshes, download progress, source failures. Activities
/// keep their id, so a download reports progress into one row instead of
/// stacking a row per tick.
class NoticeCenter extends ChangeNotifier {
  NoticeCenter._();

  static final NoticeCenter instance = NoticeCenter._();

  /// Enough history to be useful, few enough to stay scannable.
  static const int _limit = 60;

  final List<Notice> _items = <Notice>[];

  List<Notice> get notices => List<Notice>.unmodifiable(_items);

  int get unread => _items.where((Notice notice) => !notice.read).length;
  int get activeCount => _items.where((Notice notice) => notice.active).length;

  /// Whether the top-bar button has anything to say.
  bool get hasAttention => unread > 0 || activeCount > 0;

  Notice? find(String id) {
    for (final Notice notice in _items) {
      if (notice.id == id) {
        return notice;
      }
    }
    return null;
  }

  /// Publishes a one-shot notice, or refreshes the entry with the same [id].
  ///
  /// Re-publishing is how a repeated event (a source failing twice) updates its
  /// row instead of flooding the list.
  Notice publish(
    String id,
    String title, {
    String body = '',
    NoticeKind kind = NoticeKind.info,
    bool unread = true,
  }) {
    final Notice? existing = find(id);
    if (existing != null) {
      existing
        ..title = title
        ..body = body
        ..kind = kind
        ..createdAt = DateTime.now();
      if (unread) {
        existing.read = false;
      }
      _raise(existing);
      notifyListeners();
      return existing;
    }
    final Notice notice = Notice(
      id: id,
      title: title,
      body: body,
      kind: kind,
      createdAt: DateTime.now(),
      read: !unread,
    );
    _items.insert(0, notice);
    _trim();
    notifyListeners();
    return notice;
  }

  /// Starts or updates a live activity.
  ///
  /// Repeat calls mutate one row rather than adding one per progress tick, and
  /// the row stays "read" while it runs: an activity is something to watch, not
  /// something to acknowledge.
  void activity(String id, String title, {double? progress, String body = ''}) {
    final Notice? existing = find(id);
    if (existing != null) {
      existing
        ..title = title
        ..body = body
        ..progress = progress ?? existing.progress ?? 0
        ..read = true;
      _raise(existing);
    } else {
      _items.insert(
        0,
        Notice(
          id: id,
          title: title,
          body: body,
          progress: progress ?? 0,
          createdAt: DateTime.now(),
          read: true,
        ),
      );
      _trim();
    }
    notifyListeners();
  }

  /// Ends an activity and leaves an unread result behind.
  void finish(
    String id, {
    String? title,
    String? body,
    NoticeKind kind = NoticeKind.success,
  }) {
    final Notice? notice = find(id);
    if (notice == null) {
      if (title != null) {
        publish(id, title, body: body ?? '', kind: kind);
      }
      return;
    }
    notice
      ..progress = null
      ..kind = kind
      ..read = false
      ..createdAt = DateTime.now();
    if (title != null) {
      notice.title = title;
    }
    if (body != null) {
      notice.body = body;
    }
    _raise(notice);
    notifyListeners();
  }

  void markAllRead() {
    bool changed = false;
    for (final Notice notice in _items) {
      if (!notice.read) {
        notice.read = true;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void clear() {
    if (_items.isEmpty) {
      return;
    }
    _items.clear();
    notifyListeners();
  }

  /// Moves a touched notice to the top: the list reads newest-first and an
  /// activity that just advanced is the newest thing in it.
  void _raise(Notice notice) {
    if (_items.isNotEmpty && _items.first == notice) {
      return;
    }
    _items.remove(notice);
    _items.insert(0, notice);
  }

  void _trim() {
    if (_items.length > _limit) {
      _items.removeRange(_limit, _items.length);
    }
  }
}
