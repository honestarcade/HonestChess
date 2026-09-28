@Tags(['guard'])
library;

// Every file the repository names must exist. A comment or document that cites
// a guard, a script or a workflow is a claim that the thing is there; this
// guard is what re-reads those claims. It looks at two shapes: a path under
// one of the repository's own top-level directories, and a bare `.dart` file
// name. In Dart sources only comments are read, so a fixture string that
// names a made-up path is not a claim.

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

/// Paths a fresh clone legitimately lacks, and what creates each one.
const createdLater = {
  '.n8/memory/play-console.md': 'the Play Console runbook',
  '.github/workflows/template-smoke.yml':
      'nothing in an app: tools/rename_app.py deletes it',
};

final _repoPath = RegExp(
  r'(?<![\w./$-])(?:tools|test|lib|android|\.github|\.n8)/[\w./-]*\w(?![\w\\])',
);
final _dartName = RegExp(r'(?<![\w./:$-])[a-z0-9_]+\.dart\b');

/// Text whose file references are claims: all of it, except in Dart, where
/// only comments count and package imports are skipped.
String claimText(String path, String text) {
  if (!path.endsWith('.dart')) return text;
  return [
    for (final line in text.split('\n'))
      if (RegExp(r'^\s*//').hasMatch(line)) line,
  ].join('\n');
}

/// The references in [text] that name nothing in [existing]. A bare `.dart`
/// name matches any existing file with that base name.
List<String> danglingReferences(String text, Set<String> existing) {
  final baseNames = {for (final p in existing) p.split('/').last};
  final dirs = {
    for (final p in existing)
      for (var i = p.indexOf('/'); i > 0; i = p.indexOf('/', i + 1))
        p.substring(0, i),
  };
  final dangling = <String>{};
  for (final m in _repoPath.allMatches(text)) {
    final ref = m.group(0)!.replaceFirst(RegExp(r'[./]+$'), '');
    if (!existing.contains(ref) &&
        !dirs.contains(ref) &&
        !createdLater.containsKey(ref)) {
      dangling.add(ref);
    }
  }
  for (final m in _dartName.allMatches(text)) {
    if (!baseNames.contains(m.group(0))) dangling.add(m.group(0)!);
  }
  return dangling.toList()..sort();
}

void main() {
  group('the rule, proven both ways', () {
    const existing = {
      'tools/gate.sh',
      'test/guards/signing_guard_test.dart',
      'lib/main.dart',
      'android/signing/upload_certificate.pem',
    };

    test('references to files that exist pass', () {
      const text = '''
Run tools/gate.sh; test/guards/signing_guard_test.dart proves it, as does
signing_guard_test.dart. The test/guards/ directory, and
android/signing/upload_certificate.pem once make_upload_key.sh writes it.
''';
      expect(danglingReferences(text, existing), isEmpty);
    });

    test('a reference to a missing file is caught, in either shape', () {
      const text =
          'See tools/missing.sh and workflow_guard_test.dart, '
          'and .github/workflows/gone.yml, but not a regex: tools/gate\\.sh.';
      expect(danglingReferences(text, existing), [
        '.github/workflows/gone.yml',
        'tools/missing.sh',
        'workflow_guard_test.dart',
      ]);
    });

    test('in Dart, only comments are claims, and imports are not', () {
      const source =
          '''
import 'package:flutter_test/flutter_test.dart';
const fixture = 'tools/thing.sh';
'''
          // Split so this line of the guard is not itself a comment.
          '// Proven by gone_test.dart.\n';
      expect(danglingReferences(claimText('x.dart', source), existing), [
        'gone_test.dart',
      ]);
    });
  });

  test('every file the repository names exists', () {
    final tracked = trackedFilesUnder('.');
    final existing = {...tracked.where(pathExists)};
    final offenders = <String>[];
    for (final path in tracked) {
      if (RegExp(r'\.(png|jar|lock|jks|keystore|pem)$').hasMatch(path)) {
        continue;
      }
      final text = claimText(path, readFile(path));
      for (final ref in danglingReferences(text, existing)) {
        offenders.add('$path names $ref');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('dangling-reference', offenders),
    );
  });
}
