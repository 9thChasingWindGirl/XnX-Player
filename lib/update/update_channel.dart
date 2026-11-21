/// Update channels and the decisions around them — pure functions so CI can
/// unit-test them headlessly.
///
/// Three channels, mirroring how the project actually ships:
/// - **stable** — `main` 晋升出的正式 Release：便携版 zip + 安装包。
/// - **beta** — beta 分支晋升出的 prerelease：便携版 zip + 安装包。
/// - **dev** — beta 分支每次 push 自动发布的 `nightly-*` prerelease，携带
///   便携版 zip。用 Release 资产而非 Actions 产物是因为后者的下载端点即使
///   公开仓库也要认证，无 token 的客户端永远 401。
///
/// 应用内更新只消费便携版 zip；安装包只用于首次安装与手动重装。
///
/// Rollback is a first-class operation: every version that has been applied
/// keeps its extracted build, so applying an older copy is the same code path
/// as installing a newer one.
library;

enum UpdateChannel { stable, beta, dev }

/// One installable candidate, whatever its source.
///
/// `assetUrl` points at the portable zip; [installerUrl] at the Inno setup exe
/// when the release carries one. An installed copy updates only through the
/// installer (so the uninstall entry stays correct); a portable copy defaults
/// to the zip and may opt into the installer.
class UpdateCandidate {
  const UpdateCandidate({
    required this.version,
    this.name = '',
    this.assetUrl = '',
    this.installerUrl = '',
    this.notes = '',
    this.publishedAt = '',
    this.isPrerelease = false,
  });

  factory UpdateCandidate.fromJson(Map<String, dynamic> json) => UpdateCandidate(
        version: json['version'] as String? ?? '',
        name: json['name'] as String? ?? '',
        assetUrl: json['assetUrl'] as String? ?? '',
        installerUrl: json['installerUrl'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        publishedAt: json['publishedAt'] as String? ?? '',
        isPrerelease: json['isPrerelease'] as bool? ?? false,
      );

  final String version;
  final String name;
  final String assetUrl;

  /// Setup.exe for the same version; empty for channels that ship no installer
  /// (dev nightlies are portable-only).
  final String installerUrl;
  final String notes;
  final String publishedAt;
  final bool isPrerelease;

  bool get hasInstaller => installerUrl.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'name': name,
        'assetUrl': assetUrl,
        'installerUrl': installerUrl,
        'notes': notes,
        'publishedAt': publishedAt,
        'isPrerelease': isPrerelease,
      };
}

/// Picks the release that a channel offers.
///
/// GitHub only has two states — Latest and Pre-release — but this project ships
/// three channels, and **both beta and dev are pre-releases**. The tag shape is
/// therefore the real discriminator:
///
/// ```
/// v0.01.00              stable   (not a pre-release)
/// v0.01.00.Beta         beta
/// nightly-0.00.05.Dev   dev
/// ```
///
/// Relying on `isPrerelease` alone let a beta check pick up a dev nightly.
/// Dev's `nightly-*` list is fetched by the service layer; null here means
/// "not this layer's decision".
UpdateCandidate? pickRelease(List<UpdateCandidate> releases, UpdateChannel channel) {
  if (channel == UpdateChannel.dev) {
    return null;
  }
  UpdateCandidate? best;
  for (final UpdateCandidate release in releases) {
    if (!belongsToChannel(release.version, release.isPrerelease, channel)) {
      continue;
    }
    if (best == null || compareVersions(release.version, best.version) > 0) {
      best = release;
    }
  }
  return best;
}

/// Whether a tag belongs to [channel], judged by its shape.
///
/// `nightly-` wins over `.beta` on purpose: a tag can only be one of them, and
/// checking the negative first is what keeps a dev nightly out of the beta row.
bool belongsToChannel(
  String tag,
  bool isPrerelease,
  UpdateChannel channel,
) {
  final String value = tag.trim().toLowerCase();
  final bool nightly = value.startsWith('nightly-');
  // Both spellings ship in the wild: this project writes `v0.01.00.Beta`, and
  // semver-style `v1.3.0-beta.2` is what the tests (and other tools) use.
  final bool beta = value.contains('beta');
  switch (channel) {
    case UpdateChannel.dev:
      return nightly;
    case UpdateChannel.beta:
      return beta && !nightly;
    case UpdateChannel.stable:
      return !isPrerelease && !nightly && !beta;
  }
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
