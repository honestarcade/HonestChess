@Tags(['guard'])
library;

// No trace of the template's placeholder app survives in this repository
// (#35; #14's criterion, previously a one-off grep). The placeholder names
// may appear only where they are fixtures or examples: the guards' own test
// data, the rename tool that replaces them, the mutation battery's defects,
// and the runbook's example table. `com.example.*` is held separately, in the
// files that carry the identity, by android_identity_test.dart.

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

/// Names only the template's placeholder app uses.
final leftoverPattern = RegExp(
  r'your_app|yourapp|<Your App Name>|Flutter Demo|A new Flutter project|\bMyApp\b',
);

/// Tracked paths (or path prefixes) where the placeholder names are fixtures
/// or examples, with why.
const allowedLeftovers = {
  'test/guards/': 'guard fixtures that must name the placeholder to refuse it',
  'tools/rename_app.py': 'the tool that replaces the placeholder names',
  'tools/mutation_check.py': "the battery's reintroduced defects",
  '.n8/memory/play-console-runbook.md': "the runbook's example table",
};

/// `path:line: text` for every line of [files] (path → contents) that names
/// the placeholder outside [allowedLeftovers].
List<String> leftovers(Map<String, String> files) => [
  for (final e in files.entries)
    if (!allowedLeftovers.keys.any(e.key.startsWith))
      for (final (i, line) in e.value.split('\n').indexed)
        if (leftoverPattern.hasMatch(line)) '${e.key}:${i + 1}: ${line.trim()}',
];

void main() {
  group('the rule, proven both ways', () {
    test('a placeholder name outside the allowlist is caught', () {
      expect(
        leftovers({
          'README.md': 'Welcome to <Your App Name>\nfine line\n',
          'lib/app.dart': 'class MyApp {}\n',
        }),
        [
          'README.md:1: Welcome to <Your App Name>',
          'lib/app.dart:1: class MyApp {}',
        ],
      );
    });

    test('allowlisted fixtures and look-alike words pass', () {
      expect(
        leftovers({
          'test/guards/x_test.dart': "const id = 'com.example.your_app';\n",
          'tools/rename_app.py': 'OLD = "yourapp"\n',
          'lib/main.dart': 'class HonestChessApp {} // not MyAppBar\n',
        }),
        isEmpty,
      );
    });
  });

  test('no placeholder name survives in the repository', () {
    final paths = trackedFilesUnder('.');
    expect(
      paths,
      contains('lib/main.dart'),
      reason: 'template-leftovers: git ls-files returned nothing useful',
    );
    final files = {
      for (final p in paths)
        if (!RegExp(r'\.(png|jar|ttf|wav)$').hasMatch(p) && pathExists(p))
          p: readFile(p),
    };
    final offenders = leftovers(files);
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('template-leftovers', offenders),
    );
  });
}
