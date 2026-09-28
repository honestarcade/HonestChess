@Tags(['guard'])
library;

// The weekly tier (#37): tests too slow for the pull-request gate run on a
// schedule through tools/weekly_tests.sh, which must refuse to pass having
// run none, and the gate must never run them.

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

ScriptRun _weekly(String flutterStub) =>
    runWithStubs([tool('weekly_tests.sh')], stubs: {'flutter': flutterStub});

void main() {
  group('weekly_tests.sh, proven both ways', () {
    test('a passing weekly test passes', () {
      final r = _weekly(
        _flutter([_done(1, 'success', hidden: true), _done(2, 'success')]),
      );
      expect(r.exitCode, 0, reason: r.output);
      expect(r.output, contains('1 passed, 0 failed'));
    });

    test('no weekly test at all is refused, whatever flutter exits', () {
      for (final exit in [0, 79]) {
        final r = _weekly(
          _flutter([_done(1, 'success', hidden: true)], exit: exit),
        );
        expect(
          r.exitCode,
          3,
          reason: 'weekly-tests: an empty run was not refused\n${r.output}',
        );
        expect(r.output, contains('refusing to pass empty'));
      }
    });

    test('a failing weekly test fails', () {
      final r = _weekly(
        _flutter([_done(1, 'success'), _done(2, 'failure')], exit: 1),
      );
      expect(r.exitCode, 1, reason: r.output);
    });
  });

  group('the repository', () {
    test('the gate excludes the weekly tag and dart_test.yaml declares it', () {
      expect(
        readFile('tools/gate.sh'),
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

    test('weekly.yml runs the refusing script, on dispatch', () {
      final wf = readWorkflow('.github/workflows/weekly.yml');
      final runs = [
        for (final job in jobsOf(wf).values)
          for (final step in stepsOf(job))
            if (step['run'] is String) (step['run'] as String).trim(),
      ];
      expect(
        runs,
        contains('tools/weekly_tests.sh'),
        reason: 'weekly-workflow: the job does not run tools/weekly_tests.sh',
      );
      expect(
        runs.where((r) => r.contains('--tags weekly')),
        isEmpty,
        reason: 'weekly-workflow: the job runs the weekly tests without the empty-run refusal',
      );
      expect(
        (triggers(wf) as YamlMap).keys,
        contains('workflow_dispatch'),
        reason: 'weekly-workflow: no manual trigger',
      );
    });
  });
}
