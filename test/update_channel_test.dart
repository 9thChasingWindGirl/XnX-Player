import 'package:flutter_test/flutter_test.dart';
import 'package:xnx_player/update/update_channel.dart';

void main() {
  test('stable channel picks the newest non-prerelease only', () {
    final List<UpdateCandidate> releases = <UpdateCandidate>[
      const UpdateCandidate(version: 'v1.2.0', name: 'r', assetUrl: 'http://x/1'),
      const UpdateCandidate(
        version: 'v1.3.0-beta.1',
        name: 'b',
        assetUrl: 'http://x/2',
        isPrerelease: true,
      ),
    ];
    final UpdateCandidate? picked = pickRelease(releases, UpdateChannel.stable);
    expect(picked?.version, 'v1.2.0');
  });

  test('beta channel picks the newest prerelease and ignores stable', () {
    final List<UpdateCandidate> releases = <UpdateCandidate>[
      const UpdateCandidate(version: 'v1.2.0', name: 'r', assetUrl: 'http://x/1'),
      const UpdateCandidate(
        version: 'v1.3.0-beta.1',
        name: 'b',
        assetUrl: 'http://x/2',
        isPrerelease: true,
      ),
      const UpdateCandidate(
        version: 'v1.3.0-beta.2',
        name: 'b2',
        assetUrl: 'http://x/3',
        isPrerelease: true,
      ),
    ];
    final UpdateCandidate? picked = pickRelease(releases, UpdateChannel.beta);
    expect(picked?.version, 'v1.3.0-beta.2');
  });

  test('dev channel never resolves from the release list', () {
    expect(pickRelease(<UpdateCandidate>[], UpdateChannel.dev), isNull);
  });

  test('a dev nightly never becomes the beta candidate', () {
    // Both are pre-releases on GitHub; only the tag shape separates them. This
    // is the bug the shape check exists for: a beta check used to be able to
    // install a dev nightly.
    final List<UpdateCandidate> releases = <UpdateCandidate>[
      const UpdateCandidate(
        version: 'v0.01.00.Beta',
        assetUrl: 'http://x/b',
        isPrerelease: true,
      ),
      const UpdateCandidate(
        version: 'nightly-0.00.09.Dev',
        assetUrl: 'http://x/d',
        isPrerelease: true,
      ),
    ];
    expect(pickRelease(releases, UpdateChannel.beta)?.version, 'v0.01.00.Beta');
    expect(pickRelease(releases, UpdateChannel.stable), isNull);
    expect(
      belongsToChannel('nightly-0.00.09.Dev', true, UpdateChannel.dev),
      isTrue,
    );
    expect(
      belongsToChannel('nightly-0.00.09.Dev', true, UpdateChannel.beta),
      isFalse,
    );
  });

  test('dotted versions compare numerically, not lexically', () {
    expect(compareVersions('1.2.10', '1.2.9') > 0, isTrue);
    expect(compareVersions('v1.2.0', '1.2.0'), 0);
    expect(compareVersions('1.10.0', '1.9.0') > 0, isTrue);
    expect(compareVersions('1.2.0-beta.2', '1.2.0-beta.10') < 0, isTrue);
  });

  test('installability accepts both directions and rejects same version', () {
    expect(
      isInstallable(const UpdateCandidate(version: '1.3.0', assetUrl: 'u'), '1.2.0'),
      isTrue,
    );
    // Rollback: older versions are installable on purpose.
    expect(
      isInstallable(const UpdateCandidate(version: '1.1.0', assetUrl: 'u'), '1.2.0'),
      isTrue,
    );
    expect(
      isInstallable(const UpdateCandidate(version: '1.2.0', assetUrl: 'u'), '1.2.0'),
      isFalse,
    );
    expect(
      isInstallable(const UpdateCandidate(version: '', assetUrl: 'u'), '1.2.0'),
      isFalse,
    );
  });

  test('candidate round-trips through JSON', () {
    const UpdateCandidate candidate = UpdateCandidate(
      version: 'v1.3.0-beta.1',
      name: 'beta 1',
      assetUrl: 'http://x/2',
      isPrerelease: true,
    );
    final UpdateCandidate restored = UpdateCandidate.fromJson(candidate.toJson());
    expect(restored.version, candidate.version);
    expect(restored.assetUrl, candidate.assetUrl);
    expect(restored.isPrerelease, candidate.isPrerelease);
  });
}
