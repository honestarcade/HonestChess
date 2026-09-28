@Tags(['guard'])
library;

// The release path's scripted refusals, exercised: ci_version.sh refuses a ref
// or run identity it cannot turn into exactly one version, and
// attach_release_asset.sh skips only when the tag has no release, failing on
// any other gh error and on an asset that does not match what was built.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'stubs.dart';

const _gh = r'''#!/bin/bash
echo "$*" >> "$RUNNER_TEMP/gh.log"
case "$1 $2" in
  "release view")
    case "${GH_VIEW:-ok}" in
      ok) exit 0 ;;
      notfound) echo "release not found" >&2; exit 1 ;;
      *) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
    esac ;;
  "release upload")
    [ "${GH_UPLOAD:-ok}" = ok ] || { echo "HTTP 403: upload refused" >&2; exit 1; }
    mkdir -p "$RUNNER_TEMP/remote"
    cp "$4" "$5" "$RUNNER_TEMP/remote/" ;;
  "release download")
    mkdir -p "$7"
    cp "$RUNNER_TEMP/remote/$5" "$7/"
    if [ "${GH_CORRUPT:-}" = 1 ]; then echo corrupt >> "$7/$5"; fi ;;
esac
''';

class AttachRun {
  AttachRun(this.run, this.ghCalls, this.note);
  final ScriptRun run;
  final List<String> ghCalls;
  final String? note;
}

AttachRun attach(Map<String, String> env, {bool withChecksum = true}) {
  var calls = <String>[];
  String? note;
  final run = runWithStubs(
    [tool('attach_release_asset.sh'), 'v1.2.3', 'app.aab'],
    stubs: {'gh': _gh},
    env: env,
    files: {'app.aab': 'bundle bytes', if (withChecksum) 'app.aab.sha256': 'x'},
    inspect: (dir) {
      final log = File('${dir.path}/gh.log');
      calls = log.existsSync() ? log.readAsLinesSync() : [];
      final n = File('${dir.path}/no-release-note');
      note = n.existsSync() ? n.readAsStringSync() : null;
    },
  );
  return AttachRun(run, calls, note);
}

bool _uploaded(AttachRun r) =>
    r.ghCalls.any((c) => c.startsWith('release upload'));

void main() {
  group('ci_version.sh', () {
    ScriptRun version(List<String> args) =>
        runWithStubs([tool('ci_version.sh'), ...args]);

    test('positive control: a release tag yields its name and code', () {
      final r = version(['v0.1.0', '12', '1']);
      expect(r.exitCode, 0, reason: r.stderr);
      expect(r.stdout, 'name=0.1.0\ncode=1121\n');
      expect(version(['v1.2.3-rc.1', '7', '2']).stdout, contains('1.2.3-rc.1'));
    });

    for (final bad in [
      ['main', '12', '1'],
      ['v1.2', '12', '1'],
      ['v01.2.3', '12', '1'],
      ['v1.2.3-rc.01', '12', '1'],
      ['v1.2.3-', '12', '1'],
      ['v1.2.3\nv9.9.9', '12', '1'],
      ['v1.2.3', '0', '1'],
      ['v1.2.3', '123456789', '1'],
      ['v1.2.3', '12', '10'],
      ['v1.2.3', '12', '0'],
      ['v1.2.3', '12'],
    ]) {
      test('refuses ${bad.join(' ').replaceAll('\n', r'\n')}', () {
        final r = version(bad);
        expect(
          [r.exitCode, r.stdout],
          [2, ''],
          reason:
              'release-scripts: ci_version.sh accepted '
              '${bad.join(' ')}\n${r.output}',
        );
      });
    }
  });

  group('attach_release_asset.sh', () {
    test('positive control: the asset is attached and verified', () {
      final r = attach({});
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect(r.run.stdout, contains('asset attached and its hash re-verified'));
      expect(_uploaded(r), isTrue);
    });

    test('a tag with no release is skipped, with a note', () {
      final r = attach({'GH_VIEW': 'notfound'});
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect(_uploaded(r), isFalse);
      expect(r.note, contains('run artifact only'));
    });

    test('any other gh failure fails, and uploads nothing', () {
      final r = attach({'GH_VIEW': 'error'});
      expect(
        [r.run.exitCode, _uploaded(r), r.note],
        [1, false, null],
        reason:
            'release-scripts: a gh failure was treated as no release\n'
            '${r.run.output}',
      );
      expect(r.run.stderr, contains('HTTP 502'));
    });

    test('an asset that does not match what was built fails', () {
      final r = attach({'GH_CORRUPT': '1'});
      expect(
        r.run.exitCode,
        1,
        reason:
            'release-scripts: a corrupted asset passed verification\n'
            '${r.run.output}',
      );
      expect(r.run.stderr, contains('does not match'));
    });

    test('a refused upload fails', () {
      final r = attach({'GH_UPLOAD': 'fail'});
      expect(r.run.exitCode, isNot(0), reason: r.run.output);
    });

    test('a missing checksum sidecar is refused before gh runs', () {
      final r = attach({}, withChecksum: false);
      expect([r.run.exitCode, r.ghCalls], [2, isEmpty], reason: r.run.output);
    });
  });
}
