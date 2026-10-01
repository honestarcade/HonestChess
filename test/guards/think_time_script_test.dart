@Tags(['guard'])
library;

// tools/think_time.sh (#112) installs a build that replaces the app and
// erases the player's games and statistics. On a phone it must refuse
// unless told --allow-wipe and then shown a typed `wipe`; driven here with a
// stub adb that lists a phone, and a stub flutter that records being run.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'stubs.dart';

const _adb = r'''#!/bin/bash
echo "$*" >> "$STUB_LOG"
if [ "$1" = devices ]; then
  printf 'List of devices attached\nR5CY1234567\tdevice\n'
fi
''';

const _flutter = r'''#!/bin/bash
echo "flutter $*" >> "$STUB_LOG"
exit 1
''';

ScriptRun _run(List<String> args, void Function(String log) check) =>
    runWithStubs(
      [tool('think_time.sh'), ...args],
      stubs: {'adb': _adb, 'flutter': _flutter},
      env: {'STUB_LOG': '{dir}/stub.log'},
      inspect: (dir) {
        final log = File('${dir.path}/stub.log');
        check(log.existsSync() ? log.readAsStringSync() : '');
      },
    );

void main() {
  test('a phone without --allow-wipe is refused before anything runs', () {
    late String log;
    final r = _run(['-d', 'R5CY1234567'], (l) => log = l);
    expect(
      (r.exitCode, r.output.contains('Run with --allow-wipe'), log),
      (2, true, 'devices\n'),
      reason:
          'think-time-refuses-phone: without --allow-wipe the script did not '
          'exit 2 naming the flag before touching the phone (exit '
          '${r.exitCode})\n${r.output}\nstub calls:\n$log',
    );
  });

  test('--allow-wipe still needs a typed wipe before anything runs', () {
    late String log;
    final r = _run(['-d', 'R5CY1234567', '--allow-wipe'], (l) => log = l);
    expect(
      (r.exitCode, r.output.contains('not confirmed'), log),
      (2, true, 'devices\n'),
      reason:
          'think-time-confirms-wipe: with --allow-wipe and no typed "wipe" '
          'the script did not stop before building or touching the phone '
          '(exit ${r.exitCode})\n${r.output}\nstub calls:\n$log',
    );
  });
}
