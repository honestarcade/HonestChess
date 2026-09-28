@Tags(['guard'])
library;

// No workflow can print a secret. Secrets reach a step only through that
// step's own `env:` (or an action's `with:`), never workflow- or job-wide and
// never pasted into a script, and nothing turns on shell tracing, which echoes
// every expanded command into the log. Tracing is refused in a `run:` body, a
// `shell:` (step, job or workflow default), a SHELLOPTS variable, and in the
// scripts under tools/ that workflows call.

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'repo_files.dart';
import 'workflows.dart';

final _secretExpr = RegExp(r'\$\{\{[^}]*\bsecrets\b');

/// True when [args], the words after `set` or a shell's name, turn on xtrace
/// or verbose.
bool _argsTrace(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i].replaceAll(RegExp('''["']'''), '');
    if (a == '--xtrace' || a == '--verbose') return true;
    if (RegExp(r'^-[A-Za-z]*o$').hasMatch(a) &&
        i + 1 < args.length &&
        RegExp(r'^["\x27]?(xtrace|verbose)').hasMatch(args[i + 1])) {
      return true;
    }
    if (RegExp(r'^-[A-Za-z]*[xv][A-Za-z]*$').hasMatch(a)) return true;
  }
  return false;
}

/// Lines of shell [script] that turn on tracing.
List<String> tracingLines(String script) {
  final found = <String>[];
  for (final raw in script.split('\n')) {
    final line = raw.replaceFirst(RegExp(r'(^|\s)#.*$'), '');
    for (final m in RegExp(
      r'(?:^|[;&|(\s])set((?:\s+[^\s;&|)]+)+)',
    ).allMatches(line)) {
      if (_argsTrace(m.group(1)!.trim().split(RegExp(r'\s+')))) {
        found.add(raw.trim());
      }
    }
    for (final m in RegExp(
      r'''(?:^|[;&|(\s/"'])(?:ba|z|k|da)?sh((?:\s+-[^\s;&|)]*(?:\s+(?:xtrace|verbose))?)+)''',
    ).allMatches(line)) {
      if (_argsTrace(m.group(1)!.trim().split(RegExp(r'\s+')))) {
        found.add(raw.trim());
      }
    }
    if (RegExp(r'SHELLOPTS\s*=.*\b(xtrace|verbose)\b').hasMatch(line)) {
      found.add(raw.trim());
    }
  }
  return found.toSet().toList();
}

/// True when a `shell:` value such as `bash -x {0}` traces.
bool shellTraces(Object? shell) =>
    shell is String &&
    _argsTrace(shell.trim().split(RegExp(r'\s+')).skip(1).toList());

bool _envTraces(Object? env) =>
    env is YamlMap &&
    RegExp(r'\b(xtrace|verbose)\b').hasMatch('${env['SHELLOPTS'] ?? ''}');

/// Every way [workflow] could expose a secret, one line per finding.
List<String> secretExposures(YamlMap workflow) {
  final findings = <String>[];
  bool mentionsSecret(Object? node) => _secretExpr.hasMatch('$node');
  Object? defaultShell(YamlMap node) =>
      ((node['defaults'] as YamlMap?)?['run'] as YamlMap?)?['shell'];

  if (mentionsSecret(workflow['env'])) findings.add('workflow-level env');
  if (_envTraces(workflow['env'])) findings.add('workflow-level SHELLOPTS');
  if (shellTraces(defaultShell(workflow))) {
    findings.add('workflow default shell traces');
  }
  for (final MapEntry(key: name, value: job) in jobsOf(workflow).entries) {
    if (job is! YamlMap) continue;
    if (mentionsSecret(job['env'])) findings.add('$name: job-level env');
    if (_envTraces(job['env'])) findings.add('$name: job-level SHELLOPTS');
    if (shellTraces(defaultShell(job))) {
      findings.add('$name: default shell traces');
    }
    for (final step in stepsOf(job)) {
      final id = '$name/${stepLabel(step)}';
      final run = step['run'];
      if (run is String) {
        if (_secretExpr.hasMatch(run)) findings.add('$id: secret in run');
        if (tracingLines(run).isNotEmpty) findings.add('$id: shell tracing');
      }
      if (shellTraces(step['shell'])) findings.add('$id: shell traces');
      if (_envTraces(step['env'])) findings.add('$id: SHELLOPTS');
    }
  }
  return findings;
}

void main() {
  group('the rule, proven both ways', () {
    const clean = r'''
defaults:
  run:
    shell: bash
jobs:
  ship:
    steps:
      - id: keystore
        env:
          PASS: ${{ secrets.PASS }}
        run: |
          set -euo pipefail
          sha256sum app.aab
          gh secret set NAME --body -
          tools/verify_upload_cert.sh -v
      - uses: some/action@v1
        with:
          key: ${{ secrets.KEY }}
''';

    test('secrets in step env and with:, and no tracing, pass', () {
      expect(secretExposures(parseWorkflow(clean)), isEmpty);
    });

    test('every exposure shape is caught', () {
      const dirty = r'''
env:
  A: ${{ secrets.A }}
jobs:
  ship:
    env:
      B: ${{ secrets['B'] }}
    steps:
      - id: one
        run: echo "${{ secrets.C }}"
      - id: two
        run: |
          set -x
      - id: three
        run: set -euxo pipefail
      - id: four
        run: bash -x tools/thing.sh
      - id: five
        run: |
          true
          set -o xtrace
      - id: six
        run: set -e -x
      - id: seven
        run: /bin/sh -v tools/thing.sh
      - id: eight
        run: tools/thing.sh
        shell: bash --noprofile -x {0}
      - id: nine
        run: tools/thing.sh
        env:
          SHELLOPTS: xtrace
      - id: ten
        run: export SHELLOPTS=braceexpand:xtrace
''';
      expect(secretExposures(parseWorkflow(dirty)), [
        'workflow-level env',
        'ship: job-level env',
        'ship/one: secret in run',
        'ship/two: shell tracing',
        'ship/three: shell tracing',
        'ship/four: shell tracing',
        'ship/five: shell tracing',
        'ship/six: shell tracing',
        'ship/seven: shell tracing',
        'ship/eight: shell traces',
        'ship/nine: SHELLOPTS',
        'ship/ten: shell tracing',
      ]);
    });

    test('a tracing default shell is caught at workflow and job level', () {
      const dirty = r'''
defaults:
  run:
    shell: bash -x {0}
jobs:
  ship:
    defaults:
      run:
        shell: bash -eo xtrace {0}
    steps: []
''';
      expect(secretExposures(parseWorkflow(dirty)), [
        'workflow default shell traces',
        'ship: default shell traces',
      ]);
    });

    test('turning tracing off, and a commented set -x, pass', () {
      expect(tracingLines('set +x\n# set -x\necho done # set -x'), isEmpty);
    });
  });

  group('the real repository', () {
    test('no workflow can print a secret', () {
      final workflows = workflowFiles();
      expect(
        workflows,
        contains('.github/workflows/release.yml'),
        reason: 'workflow-reader: release.yml was not found',
      );
      final findings = [
        for (final path in workflows)
          for (final f in secretExposures(readWorkflow(path))) '$path: $f',
      ];
      expect(
        findings,
        isEmpty,
        reason: describeOffenders('workflow-secret-exposure', findings),
      );
    });

    test('no script under tools/ turns on tracing', () {
      final scripts = trackedFilesUnder('tools')
          .where((p) => p.endsWith('.sh'))
          .toList();
      expect(scripts, contains('tools/gate.sh'));
      final findings = [
        for (final path in scripts)
          for (final line in tracingLines(readFile(path))) '$path: $line',
      ];
      expect(
        findings,
        isEmpty,
        reason: describeOffenders('script-tracing', findings),
      );
    });
  });
}
