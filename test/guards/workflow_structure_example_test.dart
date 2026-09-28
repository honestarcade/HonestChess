@Tags(['guard'])
library;

// ci.yml is the pull-request gate and the first job of every release. Its two
// jobs, `gate` and `mutations`, are the required checks, so each must run the
// exact local command, on every pull request, and be unable to pass without
// running: no `|| true`, no `continue-on-error`, and no `if:` (a skipped
// required check reports success).

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'repo_files.dart';
import 'workflows.dart';

const requiredJobs = {
  'gate': 'tools/gate.sh',
  'mutations': 'tools/mutation_check.py',
};

/// The `run:` lines of [job]'s steps.
List<String> runLines(Object? job) =>
    stepsOf(job).map((s) => s['run']).whereType<String>().toList();

/// Steps or jobs among [requiredJobs] that could pass without running: a job-
/// or step-level `continue-on-error`, or an `if:`. Steps in [conditionalSteps]
/// may carry an `if:`, since they are not the check.
List<String> lenientParts(
  YamlMap workflow, {
  Set<String> conditionalSteps = const {'artifact'},
}) {
  final jobs = jobsOf(workflow);
  return [
    for (final name in requiredJobs.keys) ...[
      if ((jobs[name] as YamlMap?)?['continue-on-error'] != null)
        '$name: continue-on-error',
      if ((jobs[name] as YamlMap?)?['if'] != null) '$name: if',
      for (final step in stepsOf(jobs[name])) ...[
        if (step['continue-on-error'] != null)
          '$name/${stepLabel(step)}: continue-on-error',
        if (step['if'] != null && !conditionalSteps.contains(step['id']))
          '$name/${stepLabel(step)}: if',
      ],
    ],
  ];
}

void main() {
  late YamlMap workflow;

  setUpAll(() => workflow = readWorkflow('.github/workflows/ci.yml'));

  group('the real ci.yml as it stands', () {
    test('the workflow requests read-only contents permission', () {
      final permissions = workflow['permissions'];
      expect(
        permissions,
        isA<YamlMap>(),
        reason: 'workflow-structure: no top-level permissions: block found',
      );
      expect(
        (permissions as YamlMap)['contents'],
        'read',
        reason: 'workflow-structure: contents permission is not exactly "read"',
      );
    });

    test('it runs on pull requests and can be called by release.yml', () {
      final on = triggers(workflow);
      expect(
        on is YamlMap &&
            on.containsKey('pull_request') &&
            on.containsKey('workflow_call'),
        isTrue,
        reason:
            'workflow-structure: ci.yml no longer triggers on '
            'pull_request and workflow_call',
      );
    });

    test('the gate job runs tools/gate.sh, not a paraphrase of it', () {
      expect(
        runLines(jobsOf(workflow)['gate']),
        contains('tools/gate.sh'),
        reason:
            'workflow-structure: no step runs tools/gate.sh exactly — CI and '
            'a local run must execute the identical command',
      );
    });

    test('the mutations job runs the battery, not a paraphrase of it', () {
      expect(
        runLines(jobsOf(workflow)['mutations']),
        contains('tools/mutation_check.py'),
        reason:
            'workflow-structure: no step runs tools/mutation_check.py '
            'exactly, so a surviving mutation could leave the check green',
      );
    });

    test('neither required job can pass without running', () {
      final lenient = lenientParts(workflow);
      expect(
        lenient,
        isEmpty,
        reason: describeOffenders('workflow-lenient-check', lenient),
      );
    });

    test('the PR bundle is named after the PR head, not the merge commit', () {
      final artifact = stepsOf(jobsOf(workflow)['gate'])
          .firstWhere((s) => s['id'] == 'artifact');
      expect(
        '${(artifact['with'] as YamlMap)['name']}',
        allOf(
          contains(r'${{ github.event.pull_request.head.sha }}'),
          isNot(contains('github.sha')),
        ),
        reason:
            'workflow-artifact-name: the PR bundle is not named after the '
            'PR head commit',
      );
    });
  });

  group('the rules, proven both ways', () {
    test('a flow-style permissions block is still read correctly', () {
      // `permissions: {contents: write, other: read}` contains the text
      // "contents: read" nowhere, but a grep for "read" would pass it.
      final parsed = parseWorkflow('''
permissions: {contents: write, other: read}
jobs:
  x:
    steps: []
''');
      expect((parsed['permissions'] as YamlMap)['contents'], isNot('read'));
    });

    test('a lenient or skippable required job is caught', () {
      final parsed = parseWorkflow('''
jobs:
  gate:
    steps:
      - id: gate
        run: tools/gate.sh
        continue-on-error: true
      - id: artifact
        if: github.event_name == 'pull_request'
        uses: actions/upload-artifact@v7
  mutations:
    if: false
    steps:
      - id: mutations
        if: always()
        run: tools/mutation_check.py
''');
      expect(lenientParts(parsed), [
        'gate/gate: continue-on-error',
        'mutations: if',
        'mutations/mutations: if',
      ]);
    });

    test('an advisory command is not the command', () {
      final parsed = parseWorkflow('''
jobs:
  gate:
    steps:
      - run: tools/gate.sh || true
''');
      expect(
        runLines(jobsOf(parsed)['gate']),
        isNot(contains('tools/gate.sh')),
      );
    });
  });
}
