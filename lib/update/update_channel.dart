/// Update channels and the decisions around them — pure functions so CI can
/// unit-test them headlessly.
///
/// Three channels, mirroring how the project actually ships:
/// - **stable** — release 产物 off `main`（GitHub Release，非 prerelease）。
/// - **beta** — 未来 beta 分支的 Release 产物（prerelease）。beta 分支尚未
///   开出，但通道从第一天就预留。
/// - **dev** — beta 分支的 GitHub Actions 产物，未经人工验证、未发布为
///   Release，只能作为"尝鲜"入口。
///
/// Rollback is a first-class operation: every version that has been applied
/// keeps its extracted build, so applying an older copy is the same code path
/// as installing a newer one.
library;

enum UpdateChannel { stable, beta, dev }

/// One installable candidate, whatever its source.
///
/// `assetUrl` points at a zip that contains the application payload; for
/// [UpdateChannel.dev] it is a GitHub Actions artifact download.
class UpdateCandidate {
  const UpdateCandidate({
    required this.version,
    this.name = '',
    this.assetUrl = '',
    this.notes = '',
    this.publishedAt = '',
    this.isPrerelease = false,
  });

  factory UpdateCandidate.fromJson(Map<String, dynamic> json) => UpdateCandidate(
        version: json['version'] as String? ?? '',
        name: json['name'] as String? ?? '',
        assetUrl: json['assetUrl'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        publishedAt: json['publishedAt'] as String? ?? '',
        isPrerelease: json['isPrerelease'] as bool? ?? false,
      );

  final String version;
  final String name;
  final String assetUrl;
  final String notes;
  final String publishedAt;
  final bool isPrerelease;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'name': name,
        'assetUrl': assetUrl,
        'notes': notes,
        'publishedAt': publishedAt,
        'isPrerelease': isPrerelease,
      };
}

/// Picks the release that a channel offers.
///
/// stable 只认正式发布；beta 认 prerelease。Dev 走 Actions 产物，由服务层
/// 单独取，这里返回 null 表示"该通道不用 Release 列表"。
UpdateCandidate? pickRelease(List<UpdateCandidate> releases, UpdateChannel channel) {
  if (channel == UpdateChannel.dev) {
    return null;
  }
  UpdateCandidate? best;
  for (final UpdateCandidate release in releases) {
    if (channel == UpdateChannel.stable && release.isPrerelease) {
      continue;
    }
    if (channel == UpdateChannel.beta && !release.isPrerelease) {
      continue;
    }
    if (best == null || compareVersions(release.version, best.version) > 0) {
      best = release;
    }
  }
  return best;
}

/// Compares dotted numeric versions ('1.2.10' vs '1.2.9'), tolerating a `v`
/// prefix and non-numeric tails ('1.2.0-beta.2' compares by its numbers only
/// — good enough to order our own releases, which is all it is for).
///
/// Returns a positive number when `a` is newer, negative when `b` is.
int compareVersions(String a, String b) {
  final List<int> pa = _parts(a);
  final List<int> pb = _parts(b);
  final int length = pa.length > pb.length ? pa.length : pb.length;
  for (int i = 0; i < length; i++) {
    final int va = i < pa.length ? pa[i] : 0;
    final int vb = i < pb.length ? pb[i] : 0;
    if (va != vb) {
      return va.compareTo(vb);
    }
  }
  return 0;
}

List<int> _parts(String version) {
  final String cleaned = version.trim().replaceFirst(RegExp('^v'), '');
  return RegExp(r'\d+')
      .allMatches(cleaned)
      .map((Match m) => int.tryParse(m.group(0)!) ?? 0)
      .toList(growable: false);
}

/// Whether `candidate` is a different build than `current` and worth offering.
///
/// Both newer (upgrade) and older (rollback) versions qualify; only an exact
/// same-version match is filtered out, and even that is bypassed when the
/// candidate came from a different channel kind (prerelease vs stable).
bool isInstallable(UpdateCandidate candidate, String currentVersion) {
  if (candidate.version.isEmpty) {
    return false;
  }
  return compareVersions(candidate.version, currentVersion) != 0;
}
