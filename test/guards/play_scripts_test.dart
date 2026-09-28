@Tags(['guard'])
library;

// Everything that talks to the Play Developer API, run against a stub API:
// play-api-check.yml's two steps (their `run:` bodies taken from the parsed
// workflow), play_promote.sh, and the release-code parser it relies on. Each
// refusal is seen to fire, and each has a positive control beside it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'stubs.dart';
import 'workflows.dart';

// A stateful stand-in for the Play API. A track PUT is stored and served back
// on the next GET, so a promotion's read-back sees what was written.
const _curl = r'''#!/bin/bash
echo "$*" >> "$RUNNER_TEMP/curl.log"
out=/dev/null; method=GET; url=""; body=""; wfmt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -w) wfmt="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -d) body="$2"; shift 2 ;;
    -H|--connect-timeout|--max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
say() { printf '%s' "$2" > "$out"; [ -n "$wfmt" ] && printf '%s' "$1"; exit 0; }
track="${url##*/tracks/}"
case "$method $url" in
  "POST "*/edits) say "${EDIT_STATUS:-200}" '{"id":"e1"}' ;;
  "POST "*:commit) say 200 '{}' ;;
  "DELETE "*) say 204 '' ;;
  "GET "*/tracks)
    say "${TRACKS_STATUS:-200}" '{"tracks":[{"track":"internal"}]}' ;;
  "PUT "*)
    if [ "${DRAFT_APP:-}" = 1 ] && [ "${body#*completed}" != "$body" ]; then
      say 400 '{"error":{"message":"Only releases with status draft may be created on draft app."}}'
    fi
    [ "${PUT_STATUS:-200}" = 200 ] || say "$PUT_STATUS" '{"error":{"message":"denied"}}'
    printf '%s' "$body" > "$RUNNER_TEMP/track-$track.json"
    say 200 "$body" ;;
  "GET "*)
    if [ -f "$RUNNER_TEMP/track-$track.json" ]; then
      say 200 "$(cat "$RUNNER_TEMP/track-$track.json")"
    fi
    default='{"releases":[{"versionCodes":["101"],"status":"completed"}]}'
    say 200 "${SOURCE_TRACK:-$default}" ;;
esac
say 404 '{}'
''';

const _gcloud = r'''#!/bin/sh
case "$*" in *print-access-token*) echo stub-token ;; esac
exit 0
''';

const _keytool = r'''#!/bin/sh
case "$*" in
  *-list*) printf 'Alias name: upload\nSHA256: %s\n' "${SECRET_FP:-AA:BB}" ;;
  *-printcert*) printf 'SHA256: %s\n' "${PEM_FP:-AA:BB}" ;;
esac
exit 0
''';

/// The real python3, reachable from the stub PATH.
String _python3Stub() {
  final which = Process.runSync('which', ['python3']);
  return '#!/bin/sh\nexec ${(which.stdout as String).trim()} "\$@"\n';
}

Map<String, String> get _stubs => {
  'curl': _curl,
  'gcloud': _gcloud,
  'keytool': _keytool,
  'python3': _python3Stub(),
};

String _stepBody(String id) =>
    stepsOf(
          jobsOf(readWorkflow('.github/workflows/play-api-check.yml'))['check'],
        ).firstWhere((s) => s['id'] == id)['run']
        as String;

({ScriptRun run, String summary, List<String> curl}) _step(
  String id,
  Map<String, String> env,
) {
  var summary = '';
  var curl = <String>[];
  final run = runWithStubs(
    ['-c', _stepBody(id)],
    stubs: _stubs,
    files: {'summary.md': ''},
    env: {'GITHUB_STEP_SUMMARY': '{dir}/summary.md', ...env},
    inspect: (dir) {
      summary = File('${dir.path}/summary.md').readAsStringSync();
      final log = File('${dir.path}/curl.log');
      curl = log.existsSync() ? log.readAsLinesSync() : [];
    },
  );
  return (run: run, summary: summary, curl: curl);
}

const _play = {
  'PLAY_SERVICE_ACCOUNT_JSON': '{"type":"service_account"}',
  'PACKAGE': 'com.acme.app',
};

const _keys = {
  'HS_KEYSTORE_B64': 'eA==',
  'HS_KEYSTORE_PASS': 'same-pass',
  'HS_KEY_ALIAS': 'upload',
  'HS_KEY_PASS': 'same-pass',
};

({ScriptRun run, List<String> curl}) _promote(
  List<String> args, [
  Map<String, String> env = const {},
]) {
  var curl = <String>[];
  final run = runWithStubs(
    [tool('play_promote.sh'), ...args],
    stubs: _stubs,
    env: {'PLAY_TOKEN': 'stub-token', ...env},
    inspect: (dir) {
      final log = File('${dir.path}/curl.log');
      curl = log.existsSync() ? log.readAsLinesSync() : [];
    },
  );
  return (run: run, curl: curl);
}

ScriptRun _codes(String json, [List<String> args = const []]) => runWithStubs(
  [
    '-c',
    r'printf %s "$JSON" | python3 "$0" "$@"',
    tool('play_release_codes.py'),
    ...args,
  ],
  stubs: _stubs,
  env: {'JSON': json},
);

void main() {
  group('play-api-check: Play access', () {
    test('positive control: an invited account lists the tracks', () {
      final r = _step('play', _play);
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect(r.summary, contains('Tracks: internal'));
    });

    test('a refused edit fails the check', () {
      final r = _step('play', {..._play, 'EDIT_STATUS': '403'});
      expect(
        [r.run.exitCode, r.run.output.contains('HTTP 403')],
        [1, true],
        reason: 'play-api-check: a 403 did not fail the check\n${r.run.output}',
      );
    });

    test('a failed track listing fails the check, and deletes the edit', () {
      final r = _step('play', {..._play, 'TRACKS_STATUS': '500'});
      expect(r.run.exitCode, 1, reason: r.run.output);
      expect(r.curl.any((c) => c.contains('DELETE')), isTrue);
    });

    test('a missing secret fails before any call', () {
      final r = _step('play', {..._play, 'PLAY_SERVICE_ACCOUNT_JSON': ''});
      expect([r.run.exitCode, r.curl], [1, isEmpty]);
    });
  });

  group('play-api-check: keystore secrets', () {
    test('positive control: matching secrets pass', () {
      final r = _step('keystore', _keys);
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect(r.run.output, contains('matches the committed certificate'));
    });

    test('a key password that differs from the store password fails', () {
      final r = _step('keystore', {..._keys, 'HS_KEY_PASS': 'other'});
      expect([r.run.exitCode, r.run.output], [1, contains('differs')]);
    });

    test('a keystore that is not the committed key fails', () {
      final r = _step('keystore', {..._keys, 'SECRET_FP': 'CC:DD'});
      expect(
        [r.run.exitCode, r.run.output.contains('NOT the one')],
        [1, true],
        reason: 'play-api-check: a foreign keystore passed\n${r.run.output}',
      );
    });

    test('a missing secret fails', () {
      final r = _step('keystore', {..._keys, 'HS_KEY_ALIAS': ''});
      expect(
        [r.run.exitCode, r.run.output],
        [1, contains('HS_KEY_ALIAS is not set')],
      );
    });
  });

  group('play_promote.sh', () {
    test('positive control: a completed build is promoted and read back', () {
      final r = _promote(['com.acme.app', 'internal', 'alpha']);
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect(r.run.stdout, contains('promoted=101'));
    });

    test('a draft app is retried as a draft release', () {
      final r = _promote(
        ['com.acme.app', 'internal', 'alpha'],
        {'DRAFT_APP': '1'},
      );
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect(r.run.stdout, contains('promoted=101'));
    });

    test('production is refused either way, before any API call', () {
      for (final args in [
        ['com.acme.app', 'internal', 'production'],
        ['com.acme.app', 'production', 'alpha'],
      ]) {
        final r = _promote(args);
        expect(
          [r.run.exitCode, r.curl],
          [2, isEmpty],
          reason:
              'play-promote: production was not refused (${args.join(' ')})\n'
              '${r.run.output}',
        );
      }
    });

    test('a malformed request is refused before any API call', () {
      for (final args in [
        ['com.acme.app', 'internal', 'alpha beta'],
        ['com.acme.app', 'internal', 'internal'],
        ['com.acme.app', 'internal', 'gamma'],
        ['', 'internal', 'alpha'],
        ['com.acme.app', 'internal'],
      ]) {
        final r = _promote(args);
        expect(
          [r.run.exitCode, r.run.stdout, r.curl],
          [2, '', isEmpty],
          reason: '${args.join('|')}\n${r.run.output}',
        );
      }
      final noToken = _promote(
        ['com.acme.app', 'internal', 'alpha'],
        {'PLAY_TOKEN': ''},
      );
      expect([noToken.run.exitCode, noToken.curl], [2, isEmpty]);
    });

    test('a refused promotion or an empty source track fails', () {
      final refused = _promote(
        ['com.acme.app', 'internal', 'alpha'],
        {'PUT_STATUS': '403'},
      );
      expect(
        [refused.run.exitCode, refused.run.stdout.contains('promoted=')],
        [5, false],
        reason:
            'play-promote: a refused promotion was reported as done\n'
            '${refused.run.output}',
      );
      final empty = _promote(
        ['com.acme.app', 'internal', 'alpha'],
        {'SOURCE_TRACK': '{"releases":[]}'},
      );
      expect(empty.run.exitCode, 5, reason: empty.run.output);
    });
  });

  group('play_release_codes.py', () {
    test('the newest completed release is chosen, whatever the order', () {
      final r = _codes('''
{"releases": [
  {"status": "completed", "versionCodes": ["101"]},
  {"status": "completed", "versionCodes": ["105", "104"],
   "releaseNotes": [{"language": "en-US", "text": "x"}]},
  {"status": "draft", "versionCodes": ["200"]}
]}''');
      expect(
        [r.exitCode, r.stdout.trim()],
        [0, '104 105'],
        reason:
            'play-codes: the newest completed release was not chosen\n'
            '${r.output}',
      );
      expect(
        _codes('{"releases":[{"status":"draft","versionCodes":["7"]}]}', [
          'draft',
        ]).stdout.trim(),
        '7',
      );
    });

    test('no matching release, or malformed input, is refused', () {
      expect(_codes('{"releases":[]}').exitCode, 1);
      for (final bad in [
        'not json',
        '[]',
        '{"releases": {}}',
        '{"releases":[{"status":"completed","versionCodes":["1x"]}]}',
      ]) {
        final r = _codes(bad);
        expect([r.exitCode, r.stdout], [2, ''], reason: bad);
      }
    });
  });
}
