@Tags(['guard'])
library;

// The scheduled test jobs (#37, #38): the `weekly` tier and the device tests
// on an emulator run outside the pull-request gate, through
// tools/counted_tests.sh, which must refuse to pass having run no test; and
// the gate must run neither.

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'repo_files.dart';
import 'stubs.dart';
import 'workflows.dart';

/// A `flutter` stub that prints [events] (JSON reporter lines) and exits
/// with [exit].
String _flutter(List<String> events, {int exit = 0}) =>
    '#!/usr/bin/env bash\ncat <<\'JSON\'\n${events.join('\n')}\nJSON\nexit $exit\n';

String _done(int id, String result, {bool hidden = false}) =>
    '{"testID":$id,"result":"$result","skipped":false,"hidden":$hidden,"type":"testDone","time":1}';

ScriptRun _run(String script, String flutterStub) =>
    runWithStubs([tool(script)], stubs: {'flutter': flutterStub});

/// Every `run:` body and every `with.script` of [path]'s steps, trimmed.
List<String> _commands(String path) => [
  for (final job in jobsOf(readWorkflow(path)).values)
    for (final step in stepsOf(job)) ...[
      if (step['run'] is String) (step['run'] as String).trim(),
      if (step['with'] is YamlMap &&
          (step['with'] as YamlMap)['script'] is String)
        ((step['with'] as YamlMap)['script'] as String).trim(),
    ],
];

void main() {
  group('counted_tests.sh, proven both ways', () {
    for (final script in ['weekly_tests.sh', 'device_tests.sh']) {
      test('$script: a passing test passes', () {
        final r = _run(
          script,
          _flutter([_done(1, 'success', hidden: true), _done(2, 'success')]),
        );
        expect(r.exitCode, 0, reason: r.output);
        expect(r.output, contains('1 passed, 0 failed'));
      });

      test('$script: no test at all is refused, whatever flutter exits', () {
        for (final exit in [0, 79]) {
          final r = _run(
            script,
            _flutter([_done(1, 'success', hidden: true)], exit: exit),
          );
          expect(
            r.exitCode,
            3,
            reason:
                'scheduled-tests: an empty run was not refused\n${r.output}',
          );
          expect(r.output, contains('refusing to pass empty'));
        }
      });

      test('$script: a failing test fails', () {
        final r = _run(
          script,
          _flutter([_done(1, 'success'), _done(2, 'failure')], exit: 1),
        );
        expect(r.exitCode, 1, reason: r.output);
      });
    }
  });

  group('the repository', () {
    test('the gate excludes the weekly tier and dart_test.yaml declares it', () {
      final gate = readFile('tools/gate.sh');
      expect(
        gate,
        contains('"flutter test --no-pub --exclude-tags weekly"'),
        reason:
            'weekly-gate: tools/gate.sh would run the weekly tests on every PR',
      );
      final tags = (loadYaml(readFile('dart_test.yaml')) as YamlMap)['tags'];
      expect(
        (tags as YamlMap).keys,
        contains('weekly'),
        reason: 'weekly-gate: dart_test.yaml does not declare the weekly tag',
      );
    });

    test('the gate never runs the device tests', () {
      expect(
        readFile('tools/gate.sh'),
        isNot(contains('integration_test')),
        reason: 'device-gate: tools/gate.sh would need a device',
      );
    });

    test('release builds regenerate the plugin registrant (no --no-pub)', () {
      final builds = [
        for (final line in readFile('tools/gate.sh').split('\n'))
          if (line.contains('flutter build appbundle')) line,
        for (final job in jobsOf(
          readWorkflow('.github/workflows/release.yml'),
        ).values)
          for (final step in stepsOf(job))
            if ('${step['run']}'.contains('flutter build appbundle'))
              '${step['run']}',
      ];
      expect(
        builds,
        hasLength(2),
        reason: 'release-build: the build commands were not found',
      );
      expect(
        builds.where((b) => b.contains('--no-pub')),
        isEmpty,
        reason: 'release-build: a release build with --no-pub compiles the dev-only integration_test plugin into the registrant',
      );
    });

    test('weekly.yml runs the refusing script, on dispatch', () {
      const path = '.github/workflows/weekly.yml';
      final commands = _commands(path);
      expect(
        commands,
        contains('tools/weekly_tests.sh'),
        reason: 'weekly-workflow: the job does not run tools/weekly_tests.sh',
      );
      expect(
        commands.where((c) => c.contains('flutter test')),
        isEmpty,
        reason:
            'weekly-workflow: the job runs tests without the empty-run refusal',
      );
      expect(
        (triggers(readWorkflow(path)) as YamlMap).keys,
        contains('workflow_dispatch'),
      );
    });

    test('device.yml runs the refusing script on a pinned emulator, nightly and on dispatch', () {
      const path = '.github/workflows/device.yml';
      final commands = _commands(path);
      expect(
        commands,
        contains('tools/device_tests.sh'),
        reason:
            'device-workflow: the emulator does not run tools/device_tests.sh',
      );
      expect(
        commands.where((c) => c.contains('flutter test')),
        isEmpty,
        reason:
            'device-workflow: the job runs tests without the empty-run refusal',
      );
      final emulator = [
        for (final job in jobsOf(readWorkflow(path)).values)
          for (final step in stepsOf(job))
            if ('${step['uses']}'.startsWith(
              'ReactiveCircus/android-emulator-runner@',
            ))
              step,
      ];
      expect(
        emulator,
        hasLength(1),
        reason: 'device-workflow: no emulator step',
      );
      final build = (emulator.single['with'] as YamlMap)['emulator-build'];
      expect(
        '${build ?? ''}',
        matches(RegExp(r'^\d+$')),
        reason: 'device-workflow: the emulator binary is not pinned to a build',
      );
      expect(
        (triggers(readWorkflow(path)) as YamlMap).keys,
        containsAll(['schedule', 'workflow_dispatch']),
      );
    });
  });
}
