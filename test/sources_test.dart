import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/models/media_item.dart';
import 'package:xnx_player/data/net.dart';
import 'package:xnx_player/data/sources/iptv.dart';
import 'package:xnx_player/data/sources/remote_files.dart';

void main() {
  group('parseM3u', () {
    const String playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="cctv1" tvg-logo="http://logo/1.png" group-title="央视",CCTV-1 综合
http://stream/1.m3u8
#EXTINF:-1 group-title="卫视",湖南卫视
http://stream/2.m3u8
''';

    test('extracts name, group, logo and url', () {
      final List<MediaItem> items = parseM3u(playlist, 'iptv');
      expect(items.length, 2);
      expect(items.first.title, 'CCTV-1 综合');
      expect(items.first.group, '央视');
      expect(items.first.path, 'http://stream/1.m3u8');
      expect(items.first.posterUrl, 'http://logo/1.png');
      expect(items.first.kind, MediaKind.channel);
      expect(items.last.title, '湖南卫视');
    });

    test('ignores comments and keeps ordering', () {
      final List<MediaItem> items = parseM3u(playlist, 'src');
      expect(items.every((MediaItem item) => item.sourceId == 'src'), isTrue);
      expect(items[1].path, 'http://stream/2.m3u8');
    });
  });

  group('XMLTV', () {
    const String guide = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20261119200000 +0800" stop="20261119210000 +0800" channel="cctv1">
    <title>新闻联播</title>
    <desc>每日新闻</desc>
  </programme>
  <programme start="20261119210000 +0800" stop="20261119220000 +0800" channel="cctv1">
    <title>焦点访谈</title>
  </programme>
</tv>
''';

    test('reads programmes with title and duration', () {
      final List<Programme> programmes = parseXmltv(guide);
      expect(programmes.length, 2);
      expect(programmes.first.title, '新闻联播');
      expect(programmes.first.description, '每日新闻');
      expect(
        programmes.first.stop.difference(programmes.first.start),
        const Duration(hours: 1),
      );
    });

    test('parses the XMLTV timestamp with its offset', () {
      final DateTime parsed = parseXmltvTime('20261119203000 +0800');
      expect(parsed.toUtc(), DateTime.utc(2026, 11, 19, 12, 30));
    });

    test('picks the programme covering a moment', () {
      final List<Programme> programmes = parseXmltv(guide);
      final Programme? now = programmeAt(programmes, 'cctv1', programmes.first.start);
      expect(now?.title, '新闻联播');
    });
  });

  group('WebDAV PROPFIND', () {
    const String response = '''
<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/Movies/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/Movies/Blade.Runner.2049.mkv</D:href>
    <D:propstat><D:prop><D:resourcetype/><D:getcontentlength>9000000</D:getcontentlength></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/Movies/notes.txt</D:href>
    <D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat>
  </D:response>
</D:multistatus>
''';

    test('keeps folders and videos, drops the collection itself and junk', () {
      final List<MediaItem> items = parseWebDav(
        response,
        'dav',
        Uri.parse('http://host/dav/'),
        '/dav/',
      );
      expect(items.length, 2);
      expect(items.first.title, 'Movies');
      expect(items.first.kind, MediaKind.folder);
      expect(items.last.title, 'Blade Runner 2049');
      expect(items.last.path, '/dav/Movies/Blade.Runner.2049.mkv');
    });
  });

  group('parseXml', () {
    test('strips namespace prefixes and reads attributes', () {
      final XmlNode root = parseXml('<a:root xmlns:a="x"><a:item id="1">hi</a:item></a:root>');
      final XmlNode? element = root.child('root');
      expect(element, isNotNull);
      expect(element!.name, 'root');
      expect(element.descendants('item').first.attr('id'), '1');
      expect(element.descendants('item').first.trimmed, 'hi');
    });

    test('decodes entities', () {
      final XmlNode root = parseXml('<t>a &amp; b &lt;c&gt;</t>');
      expect(root.child('t')?.trimmed, 'a & b <c>');
    });
  });
}
