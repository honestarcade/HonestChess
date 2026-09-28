@Tags(['guard'])
library;

// Least privilege for every workflow (#20): each declares a top-level
// `permissions:` mapping that grants nothing beyond read, and a write scope
// appears only on a job this file names. The default GITHUB_TOKEN is broader
// than any job here needs, so a workflow without the block is not neutral —
// it is the widest grant available. The shorthands `read-all`/`write-all`
// are refused because they grant every scope at once.

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'workflows.dart';

/// The only write scopes any job may hold: workflow file → job → scopes.
const writeAllowlist = {
  '.github/workflows/release.yml': {
    'ship': {'contents'}, // attaches the bundle to the GitHub release
  },
};

/// Why [block] is not a least-privilege grant, where [allowedWrites] are the
/// scopes this block may hold at `write`.
List<String> grantProblems(
  Object? block,
  String where, {
  Set<String> allowedWrites = const {},
}) {
  if (block is! YamlMap && block is! Map) {
    return ['$where: permissions is ${block ?? 'missing'}, not a mapping'];
  }
  return [
    for (final e in (block as Map).entries)
      if (e.value == 'write' && !allowedWrites.contains('${e.key}'))
        '$where: ${e.key}: write is not allowlisted'
      else if (!const {'read', 'write', 'none'}.contains(e.value))
        '$where: ${e.key}: ${e.value} is not read, write or none',
  ];
}

/// Every least-privilege problem in the workflow [doc] at [path].
List<String> workflowGrantProblems(YamlMap doc, String path) {
  final allow = writeAllowlist[path] ?? const {};
  return [
    ...grantProblems(doc['permissions'], path),
    for (final job in jobsOf(doc).entries)
      if ((job.value as YamlMap).containsKey('permissions'))
        ...grantProblems(
          (job.value as YamlMap)['permissions'],
          '$path jobs.${job.key}',
          allowedWrites: allow['${job.key}'] ?? const {},
        ),
  ];
}

YamlMap _wf(String text) => parseWorkflow(text);

void main() {
  group('the rule, proven both ways', () {
    const base = 'on: push\njobs:\n  a:\n    runs-on: x\n    steps: []\n';

    test('a read-only workflow passes', () {
      expect(
        workflowGrantProblems(
          _wf('permissions:\n  contents: read\n$base'),
          'x.yml',
        ),
        isEmpty,
      );
    });

    test('a missing block, a shorthand and a top-level write are refused', () {
      expect(
        workflowGrantProblems(_wf(base), 'x.yml').single,
        contains('missing'),
      );
      expect(
        workflowGrantProblems(
          _wf('permissions: write-all\n$base'),
          'x.yml',
        ).single,
        contains('not a mapping'),
      );
      expect(
        workflowGrantProblems(
          _wf('permissions:\n  contents: write\n$base'),
          'x.yml',
        ).single,
        contains('contents: write is not allowlisted'),
      );
    });

    test('a job-level write passes only where the allowlist names it', () {
      const job = '''
permissions:
  contents: read
on: push
jobs:
  ship:
    runs-on: x
    permissions:
      contents: write
    steps: []
''';
      expect(
        workflowGrantProblems(_wf(job), '.github/workflows/release.yml'),
        isEmpty,
      );
      expect(
        workflowGrantProblems(_wf(job), '.github/workflows/ci.yml').single,
        contains('jobs.ship: contents: write is not allowlisted'),
      );
    });
  });

  test('every workflow grants least privilege', () {
    final files = workflowFiles();
    expect(
      files,
      contains('.github/workflows/ci.yml'),
      reason: 'workflow-permissions: the workflows were not found',
    );
    final problems = [
      for (final path in files)
        ...workflowGrantProblems(readWorkflow(path), path),
    ];
    expect(
      problems,
      isEmpty,
      reason:
          'workflow-permissions: ${problems.length} offender(s)\n  ${problems.join('\n  ')}',
    );
  });
}
