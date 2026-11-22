import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/data/sources/nfo.dart';

void main() {
  group('NfoFile.parse tvshow', () {
    // The shape tinyMediaManager writes: nested <ratings>, flat <genre> per
    // entry, <actor> with name/role, and a <uniqueid type="tmdb">.
    const String xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<tvshow>
  <title>杀人者的购物中心</title>
  <originaltitle>A Shop for Killers</originaltitle>
  <ratings>
    <rating name="themoviedb" max="10" default="true">
      <value>7.4</value>
      <votes>1200</votes>
    </rating>
  </ratings>
  <plot>叔叔留下的购物中心，成了她活下去的唯一筹码。</plot>
  <tagline>别相信任何人</tagline>
  <year>2024</year>
  <genre>剧情</genre>
  <genre>动作</genre>
  <studio>Disney+</studio>
  <mpaa>TV-MA</mpaa>
  <status>Continuing</status>
  <actor><name>李栋旭</name><role>郑进湾</role></actor>
  <actor><name>金慧埈</name><role>郑智安</role></actor>
  <director>李权</director>
  <writer>池浩镇</writer>
  <uniqueid type="tmdb" default="true">123456</uniqueid>
</tvshow>''';

    test('reads title, plot, rating, genres and people', () {
      final NfoFile? parsed = NfoFile.parse(xml);
      expect(parsed, isNotNull);
      final NfoFile nfo = parsed!;

      expect(nfo.title, '杀人者的购物中心');
      expect(nfo.originalTitle, 'A Shop for Killers');
      expect(nfo.plot, '叔叔留下的购物中心，成了她活下去的唯一筹码。');
      expect(nfo.tagline, '别相信任何人');
      expect(nfo.year, 2024);
      expect(nfo.rating, 7.4);
      expect(nfo.genres, <String>['剧情', '动作']);
      expect(nfo.studio, 'Disney+');
      expect(nfo.mpaa, 'TV-MA');
      expect(nfo.status, 'Continuing');
      expect(nfo.tmdbId, 123456);
      expect(nfo.isEmpty, isFalse);
    });

    test('keeps cast roles and crew jobs apart', () {
      final NfoFile nfo = NfoFile.parse(xml)!;

      expect(nfo.people.length, 4);
      expect(nfo.people[0].name, '李栋旭');
      expect(nfo.people[0].role, '郑进湾');
      expect(nfo.people[0].isCast, isTrue);
      expect(nfo.people[2].name, '李权');
      expect(nfo.people[2].job, '导演');
      expect(nfo.people[2].isCast, isFalse);
      expect(nfo.people[3].job, '编剧');
    });
  });

  group('NfoFile.parse episode', () {
    test('reads the per-episode record, including runtime', () {
      const String xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<episodedetails>
  <title>如梦似幻</title>
  <showtitle>赛博朋克：边缘行者</showtitle>
  <season>2</season>
  <episode>5</episode>
  <plot>露西做了一个很长的梦。</plot>
  <runtime>62</runtime>
  <aired>2024-01-17</aired>
  <rating>8.1</rating>
</episodedetails>''';

      final NfoFile nfo = NfoFile.parse(xml)!;
      expect(nfo.title, '如梦似幻');
      expect(nfo.showTitle, '赛博朋克：边缘行者');
      expect(nfo.season, 2);
      expect(nfo.episode, 5);
      expect(nfo.plot, '露西做了一个很长的梦。');
      expect(nfo.duration, const Duration(minutes: 62));
      expect(nfo.airDate, '2024-01-17');
      // A bare <rating> is the pre-<ratings> layout and still has to work.
      expect(nfo.rating, 8.1);
    });

    test('falls back to the premiered year and outline for the plot', () {
      const String xml = '''<episodedetails>
  <title>第 1 集</title>
  <outline>开场</outline>
  <premiered>2023-11-02</premiered>
</episodedetails>''';

      final NfoFile nfo = NfoFile.parse(xml)!;
      expect(nfo.plot, '开场');
      expect(nfo.year, 2023);
    });
  });

  group('NfoFile.parse rejects non-metadata', () {
    test('a file without a known root element is null', () {
      expect(NfoFile.parse('<html><body>404</body></html>'), isNull);
    });

    test('an empty tvshow is null rather than an empty record', () {
      expect(NfoFile.parse('<tvshow></tvshow>'), isNull);
      expect(NfoFile.parse('not xml at all'), isNull);
    });
  });

  group('NfoFile.pathFor', () {
    test('replaces only the media extension', () {
      expect(NfoFile.pathFor(r'C:\剧集\Show.S01E01.mkv'),
          r'C:\剧集\Show.S01E01.nfo');
      expect(NfoFile.pathFor('/media/Show.2160p.HEVC.mkv'),
          '/media/Show.2160p.HEVC.nfo');
      expect(NfoFile.pathFor(r'C:\media\movie.mp4'), r'C:\media\movie.nfo');
    });

    test('a dot in a folder name is not an extension', () {
      expect(NfoFile.pathFor(r'C:\a.b\video'), r'C:\a.b\video.nfo');
    });

    test('candidate paths include the Kodi/TMM sidecar fallbacks', () {
      final List<String> paths =
          NfoFile.candidatePaths(r'C:\剧集\Show.S01E02.mkv');
      expect(paths.first, r'C:\剧集\Show.S01E02.nfo');
      expect(paths, contains(r'C:\剧集\movie.nfo'));
      expect(paths, contains(r'C:\剧集\S01E02.nfo'));
    });
  });

  group('NfoFile.parse Kodi rules', () {
    test('premiered wins over aired, and a 5-point rating is normalised', () {
      final NfoFile? nfo = NfoFile.parse('''
<episodedetails>
  <title>第五集</title>
  <year>2020</year>
  <premiered>2024-03-15</premiered>
  <aired>2020-01-01</aired>
  <outline>短简介</outline>
  <plot>完整剧情</plot>
  <ratings><rating max="5"><value>4.5</value></rating></ratings>
  <country>日本</country>
  <thumb>https://example.com/poster.jpg</thumb>
  <namedseason number="2">第二季特别篇</namedseason>
</episodedetails>''');
      expect(nfo, isNotNull);
      expect(nfo!.year, 2024);
      expect(nfo.outline, '短简介');
      expect(nfo.plot, '完整剧情');
      expect(nfo.rating, closeTo(9, 0.0001));
      expect(nfo.countries, contains('日本'));
      expect(nfo.thumbUrls, isNotEmpty);
      expect(nfo.namedSeasons[2], '第二季特别篇');
    });

    test('default=true rating outranks an earlier one', () {
      final NfoFile? nfo = NfoFile.parse('''
<movie>
  <title>Movie</title>
  <ratings>
    <rating max="10"><value>5</value></rating>
    <rating max="10" default="true"><value>8</value></rating>
  </ratings>
</movie>''');
      expect(nfo?.rating, closeTo(8, 0.0001));
    });
  });
}
