@Tags(['guard'])
library;

// tools/gate.sh must stop at the first failing step and exit with its code.
// The ci.yml guard proves CI honours the gate's exit code; this proves the gate
// produces one. The real script runs in a scratch tree whose flutter, dart and
// check_aab.sh are stubs that record each call and fail on request.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const _stub = r'''#!/bin/sh
cmd="$(basename "$0") $*"
echo "$cmd" >> "$STUB_LOG"
if [ -n "${FAIL_ON:-}" ]; then
  case "$cmd" in "$FAIL_ON"*) echo "stub: failing $cmd" >&2; exit 7 ;; esac
fi
case "$cmd" in
  "flutter build appbundle"*)
    mkdir -p build/app/outputs/bundle/release
    : > build/app/outputs/bundle/release/app-release.aab
    echo debug > "$HS_SIGNING_VERDICT"
    ;;
esac
exit 0
''';

class GateRun {
  GateRun(this.exitCode, this.output, this.calls);
  final int exitCode;
  final String output;
  final List<String> calls;
}

GateRun runGate({String? failOn}) {
  final dir = Directory.systemTemp.createTempSync('gate');
  try {
    Directory('${dir.path}/tools').createSync();
    Directory('${dir.path}/bin').createSync();
    File('${repoRoot.path}/tools/gate.sh')
        .copySync('${dir.path}/tools/gate.sh');
    for (final path in ['bin/flutter', 'bin/dart', 'tools/check_aab.sh']) {
      File('${dir.path}/$path').writeAsStringSync(_stub);
      Process.runSync('chmod', ['+x', '${dir.path}/$path']);
    }
    final log = '${dir.path}/calls.log';
    File(log).writeAsStringSync('');
    final r = Process.runSync(
      'bash',
      ['${dir.path}/tools/gate.sh'],
      workingDirectory: dir.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': '${dir.path}/bin:/usr/bin:/bin',
        'HOME': dir.path,
        'STUB_LOG': log,
        'FAIL_ON': ?failOn,
      },
    );
    final calls = File(log)
        .readAsLinesSync()
        .where((l) => l.isNotEmpty)
        .toList();
    return GateRun(r.exitCode, '${r.stdout}${r.stderr}', calls);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  test('positive control: all six steps green prints GATE PASSED', () {
    final r = runGate();
    expect(r.exitCode, 0, reason: r.output);
    expect(r.output, contains('GATE PASSED'));
    expect(r.calls, hasLength(6), reason: r.calls.join('\n'));
  });

  test('a failing step stops the gate with its exit code', () {
    final r = runGate(failOn: 'dart analyze');
    expect(
      [r.exitCode, r.output.contains('GATE PASSED')],
      [7, false],
      reason:
          'gate-failure-path: a failing step did not fail the gate\n'
          '${r.output}',
    );
    expect(r.output, contains('GATE FAILED at analyze (exit 7)'));
    expect(
      r.calls.where((c) => c.startsWith('dart format')),
      isEmpty,
      reason: 'gate-failure-path: steps after the failure still ran',
    );
  });

  test('a failing test step never builds the bundle', () {
    final r = runGate(failOn: 'flutter test');
    expect(r.exitCode, 7, reason: r.output);
    expect(r.calls.where((c) => c.startsWith('flutter build')), isEmpty);
  });

  // The build step runs through `tee`, so its status is read from PIPESTATUS
  // rather than `$?`; this is the path where the two differ.
  test('a failing build stops the gate before the scan', () {
    final r = runGate(failOn: 'flutter build');
    expect(
      [r.exitCode, r.output.contains('GATE FAILED at build release bundle')],
      [7, true],
      reason:
          'gate-build-failure: a failing build did not fail the gate\n'
          '${r.output}',
    );
    expect(r.calls.where((c) => c.startsWith('check_aab')), isEmpty);
  });
}
