@Tags(['guard'])
library;

// play-promote.yml's own barriers (#44). The workflow's header says either of
// two barriers alone keeps production out of reach: this file's refusal
// step, and tools/play_promote.sh's (play_scripts_test.dart). This holds the
// first: the workflow runs only when a person dispatches it, never offers
// production as a choice, refuses it (and anything that is not a testing
// track) before any other step, and then promotes only through the script.
// It does not cover the Play Console's permission set (#21, owner-held).

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'stubs.dart';
import 'workflows.dart';

const _path = '.github/workflows/play-promote.yml';

List<YamlMap> _steps() => stepsOf(jobsOf(readWorkflow(_path))['promote']);

ScriptRun _refuse(String from, String to) {
  final body = _steps().firstWhere((s) => s['id'] == 'refuse')['run'] as String;
  return runWithStubs(['-c', body], env: {'FROM_TRACK': from, 'TO_TRACK': to});
}

void main() {
  test('only a person dispatching it runs the workflow', () {
    final on = triggers(readWorkflow(_path));
    expect(
      on is YamlMap ? on.keys.toList() : [on],
      ['workflow_dispatch'],
      reason: 'promote-trigger: play-promote.yml runs on more than workflow_dispatch',
    );
  });

  test('production is never offered as a track', () {
    final inputs =
        ((triggers(readWorkflow(_path)) as YamlMap)['workflow_dispatch']
                as YamlMap)['inputs']
            as YamlMap;
    final offered = [
      for (final input in inputs.values)
        ...(((input as YamlMap)['options'] as YamlList?) ?? const []),
    ];
    expect(offered, isNotEmpty);
    expect(
      offered,
      isNot(contains('production')),
      reason: 'promote-options: production is offered as a track',
    );
  });

  test('the refusal is the first step and cannot be skipped', () {
    final first = _steps().first;
    expect(
      [first['id'], first['if'], first['continue-on-error']],
      ['refuse', null, null],
      reason: 'promote-refuse: the refusal is not an unconditional first step',
    );
  });

  group('the refusal, run from the workflow', () {
    test('a testing-track promotion is accepted', () {
      final r = _refuse('internal', 'alpha');
      expect(r.exitCode, 0, reason: r.output);
    });

    for (final (from, to) in [
      ('internal', 'production'),
      ('production', 'alpha'),
      ('internal', 'staging'),
      ('alpha', 'alpha'),
    ]) {
      test('$from -> $to is refused', () {
        final r = _refuse(from, to);
        expect(
          r.exitCode,
          1,
          reason: 'promote-refuse: $from -> $to was accepted\n${r.output}',
        );
      });
    }
  });

  test('promotion goes through tools/play_promote.sh, unconditionally', () {
    final promote = _steps().firstWhere((s) => s['id'] == 'promote');
    expect(
      '${promote['run']}',
      contains('tools/play_promote.sh "\$PACKAGE" "\$FROM_TRACK" "\$TO_TRACK"'),
      reason: 'promote-script: the promote step does not call tools/play_promote.sh',
    );
    expect(
      [promote['if'], promote['continue-on-error']],
      [null, null],
      reason: 'promote-script: the promote step can be skipped',
    );
  });
}
