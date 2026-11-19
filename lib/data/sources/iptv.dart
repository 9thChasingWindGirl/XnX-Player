import '../models/media_item.dart';
import '../net.dart';
import 'media_source.dart';

/// One EPG entry.
class Programme {
  const Programme({
    required this.channelId,
    required this.title,
    required this.start,
    required this.stop,
    this.description,
  });

  final String channelId;
  final String title;
  final DateTime start;
  final DateTime stop;
  final String? description;

  bool covers(DateTime when) => !when.isBefore(start) && when.isBefore(stop);

  String get clock {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(start.hour)}:${two(start.minute)}';
  }
}

/// IPTV: an m3u playlist plus an optional XMLTV guide.
class IptvSource extends MediaSource {
  IptvSource(super.config);

  Map<String, String> get _headers => const <String, String>{'Accept': '*/*'};

  @override
  Future<List<MediaItem>> browse() async {
    if (config.url.isEmpty) {
      throw const SourceException('请填写 m3u 订阅地址');
    }
    final HttpResult result = await Http.get(Uri.parse(config.url), headers: _headers);
    if (!result.ok) {
      throw SourceException('订阅拉取失败（HTTP ${result.status}）');
    }
    return parseM3u(result.body, config.id);
  }

  /// XMLTV guide. Optional: a playlist without a guide still plays.
  Future<List<Programme>> guide() async {
    final String url = config.token;
    if (url.isEmpty) {
      return const <Programme>[];
    }
    final HttpResult result = await Http.get(Uri.parse(url), headers: _headers);
    if (!result.ok) {
      return const <Programme>[];
    }
    return parseXmltv(result.body);
  }
}

/// Parses the subset of m3u that IPTV providers actually emit.
///
/// Accepts both `#EXTINF:-1 tvg-id="..." group-title="...",Name` and the older
/// `#EXTINF:0,Name` form, plus `#EXTGRP:` group overrides.
List<MediaItem> parseM3u(String text, String sourceId) {
  final List<String> lines = text.split(RegExp(r'\r?\n'));
  final List<MediaItem> items = <MediaItem>[];
  String? pendingName;
  String? pendingLogo;
  String? pendingGroup;
  String? pendingId;
  String? pendingGroupOverride;

  final RegExp attribute = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

  for (final String rawLine in lines) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('#EXTINF')) {
      final int comma = line.lastIndexOf(',');
      pendingName = comma >= 0 && comma < line.length - 1
          ? line.substring(comma + 1).trim()
          : '未命名频道';
      pendingLogo = null;
      pendingGroup = null;
      pendingId = null;
      for (final RegExpMatch match in attribute.allMatches(line)) {
        final String key = match.group(1)!.toLowerCase();
        final String value = match.group(2)!;
        switch (key) {
          case 'tvg-logo':
            pendingLogo = value;
            break;
          case 'group-title':
            pendingGroup = value;
            break;
          case 'tvg-id':
            pendingId = value;
            break;
        }
      }
      continue;
    }
    if (line.startsWith('#EXTGRP')) {
      final int colon = line.indexOf(':');
      if (colon >= 0) {
        pendingGroupOverride = line.substring(colon + 1).trim();
      }
      continue;
    }
    if (line.startsWith('#')) {
      continue;
    }
    if (pendingName == null) {
      continue;
    }

    final String group = pendingGroupOverride?.isNotEmpty == true
        ? pendingGroupOverride!
        : (pendingGroup ?? '未分组');
    items.add(
      MediaItem(
        id: '$sourceId::${pendingId?.isNotEmpty == true ? pendingId : line.hashCode}',
        sourceId: sourceId,
        sourceKind: SourceKind.iptv,
        kind: MediaKind.channel,
        title: pendingName,
        group: group,
        path: line,
        posterUrl: pendingLogo,
        badge: 'LIVE',
        meta: group,
      ),
    );
    pendingName = null;
    pendingGroupOverride = null;
  }

  return items;
}

/// Parses XMLTV `programme` elements. Only the fields a channel list needs.
List<Programme> parseXmltv(String xml) {
  final XmlNode root = parseXml(xml);
  final List<Programme> out = <Programme>[];
  for (final XmlNode node in root.descendants('programme')) {
    final String channel = node.attr('channel');
    final String title = node.textOf('title') ?? '';
    if (channel.isEmpty || title.isEmpty) {
      continue;
    }
    final DateTime start = parseXmltvTime(node.attr('start'));
    DateTime stop = parseXmltvTime(node.attr('stop'));
    if (!stop.isAfter(start)) {
      stop = start.add(const Duration(minutes: 30));
    }
    out.add(
      Programme(
        channelId: channel,
        title: title,
        start: start,
        stop: stop,
        description: node.textOf('desc'),
      ),
    );
  }
  out.sort((Programme a, Programme b) => a.start.compareTo(b.start));
  return out;
}

/// `20261119203000 +0800` -> local [DateTime].
DateTime parseXmltvTime(String raw) {
  final String value = raw.trim();
  if (value.length < 14) {
    return DateTime.now();
  }
  final int? year = int.tryParse(value.substring(0, 4));
  final int? month = int.tryParse(value.substring(4, 6));
  final int? day = int.tryParse(value.substring(6, 8));
  final int? hour = int.tryParse(value.substring(8, 10));
  final int? minute = int.tryParse(value.substring(10, 12));
  final int? second = int.tryParse(value.substring(12, 14));
  if (year == null || month == null || day == null || hour == null || minute == null) {
    return DateTime.now();
  }
  final DateTime local = DateTime.utc(year, month, day, hour, minute, second ?? 0);
  final String zone = value.length > 14 ? value.substring(14).replaceAll(':', '').trim() : '';
  if (zone.length < 5) {
    return local;
  }
  final int sign = zone.startsWith('-') ? -1 : 1;
  final int offsetHours = int.tryParse(zone.substring(1, 3)) ?? 0;
  final int offsetMinutes = int.tryParse(zone.substring(3, 5)) ?? 0;
  final Duration offset = Duration(hours: offsetHours, minutes: offsetMinutes) * sign;
  return local.subtract(offset).toLocal();
}

/// Picks what is on now, falling back to what is next.
Programme? programmeAt(List<Programme> guide, String channelId, DateTime when) {
  Programme? next;
  for (final Programme entry in guide) {
    if (entry.channelId != channelId) {
      continue;
    }
    if (entry.covers(when)) {
      return entry;
    }
    if (entry.start.isAfter(when) && (next == null || entry.start.isBefore(next.start))) {
      next = entry;
    }
  }
  return next;
}
