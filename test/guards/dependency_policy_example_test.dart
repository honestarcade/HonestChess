@Tags(['guard'])
library;

// The dependency policy: no blocked package as a direct dependency, and every
// direct dependency justified by a `# why:` comment on its own line.
//
// pubspec.yaml is read with package:yaml, so a shape that is valid YAML but
// unusual — a comment on the section header, deeper indentation, a quoted
// key, CRLF line endings — cannot hide a package. The blocklist is Honest
// Chess's (CLAUDE.md invariants 1 and 2, widened to network clients by the
// owner at /n8-plan M0, 2026-09-27, #16).

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'repo_files.dart';

/// Package-name globs this project refuses as direct dependencies, by family.
///
/// `*_ads` is anchored on an underscore rather than written `*ads*`, which
/// would also block `gamepads`, `threads` and `downloads_path_provider`; the
/// network clients are named exactly, since `*http*` would also block
/// `http_parser`.
const blockedFamilies = {
  'ads': ['*_ads', '*admob*'],
  'analytics': ['*analytics*'],
  'attribution': ['appsflyer*', 'adjust_sdk', 'flutter_branch_sdk'],
  'crash reporting': ['*crashlytics*', 'sentry*', 'bugsnag*'],
  'push and remote config': [
    'firebase_messaging',
    '*remote_config*',
    'onesignal*',
  ],
  'network clients': [
    'http',
    'dio',
    'web_socket_channel',
    'grpc',
    'connectivity_plus',
    '*_http_client',
  ],
};

final blockedNameGlobs = [for (final g in blockedFamilies.values) ...g];

/// Direct dependencies exempt from the justification rule: the SDK and the
/// lint set.
const justificationExempt = {
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_lints',
};

bool _matchesGlob(String name, String glob) =>
    RegExp('^${glob.split('*').map(RegExp.escape).join('.*')}\$')
        .hasMatch(name);

/// The names of [directDependencyNames] that match a blocked glob.
List<String> blockedDependencies(Iterable<String> directDependencyNames) => [
  for (final name in directDependencyNames)
    for (final glob
        in blockedNameGlobs.where((g) => _matchesGlob(name, g)).take(1))
      '$name (matches $glob)',
];

/// Every direct dependency named in [pubspec], read structurally.
List<String> directDependencies(String pubspec) {
  final doc = loadYaml(pubspec);
  if (doc is! YamlMap) return const [];
  return [
    for (final section in const [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ])
      if (doc[section] is YamlMap)
        for (final key in (doc[section] as YamlMap).keys) '$key',
  ];
}

/// Direct dependencies in [pubspec] whose key line carries no `# why: <reason>`
/// comment. The parser drops comments, so each key's own line is found in the
/// text — quoted or not, at any indentation — and a key whose line cannot be
/// found counts as unjustified.
List<String> unjustifiedDependencies(String pubspec) {
  final text = pubspec.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final offenders = <String>[];
  for (final name in directDependencies(text)) {
    if (justificationExempt.contains(name)) continue;
    final line = RegExp(
      '^[ \\t]+["\']?${RegExp.escape(name)}["\']?[ \\t]*:(.*)\$',
      multiLine: true,
    ).firstMatch(text);
    if (line == null || !RegExp(r'#\s*why:\s*\S').hasMatch(line.group(1)!)) {
      offenders.add(name);
    }
  }
  return offenders;
}

/// pubspec shapes that are valid YAML and that a line scan misreads.
const bypassShapes = {
  'a comment on the header': '''
dependencies: # runtime
  google_mobile_ads: ^5.0.0
''',
  'four-space indentation': '''
dependencies:
    google_mobile_ads: ^5.0.0
''',
  'a quoted key': '''
dependencies:
  "google_mobile_ads": ^5.0.0
''',
  'CRLF line endings': 'dependencies:\r\n  google_mobile_ads: ^5.0.0\r\n',
  'an override': '''
dependency_overrides:
  google_mobile_ads: ^5.0.0
''',
};

void main() {
  group('the blocklist, proven both ways', () {
    test('an ordinary package is allowed', () {
      expect(
        blockedDependencies(['path', 'shared_preferences', 'collection']),
        isEmpty,
      );
    });

    test('an ads/analytics-shaped package is caught', () {
      expect(
        blockedDependencies([
          'path',
          'google_mobile_ads',
          'firebase_analytics',
        ]),
        [
          'google_mobile_ads (matches *_ads)',
          'firebase_analytics (matches *analytics*)',
        ],
      );
      expect(blockedDependencies(['firebase_crashlytics']), hasLength(1));
    });

    test('an unrelated word containing "ads" is not caught', () {
      expect(
        blockedDependencies(['gamepads', 'threads', 'downloads_path_provider']),
        isEmpty,
      );
    });

    const caughtByFamily = {
      'ads': ['google_mobile_ads', 'admob_flutter'],
      'analytics': ['firebase_analytics'],
      'attribution': ['appsflyer_sdk', 'adjust_sdk', 'flutter_branch_sdk'],
      'crash reporting': [
        'firebase_crashlytics',
        'sentry_flutter',
        'bugsnag_flutter',
      ],
      'push and remote config': [
        'firebase_messaging',
        'firebase_remote_config',
        'onesignal_flutter',
      ],
      'network clients': [
        'http',
        'dio',
        'web_socket_channel',
        'grpc',
        'connectivity_plus',
        'cronet_http_client',
      ],
    };
    const notCaughtByFamily = {
      'ads': ['gamepads', 'threads'],
      'analytics': ['analyzer'],
      'attribution': ['adjustable_text', 'branching'],
      'crash reporting': ['crash_course', 'sentence'],
      'push and remote config': ['push_button', 'remote'],
      'network clients': ['http_parser', 'diorama', 'grpc_tools'],
    };

    for (final family in blockedFamilies.keys) {
      test('the $family family is caught, and its look-alikes are not', () {
        final caught = caughtByFamily[family]!;
        expect(blockedDependencies(caught), hasLength(caught.length));
        expect(blockedDependencies(notCaughtByFamily[family]!), isEmpty);
      });
    }

    for (final shape in bypassShapes.entries) {
      test('${shape.key} does not hide a blocked package', () {
        expect(
          blockedDependencies(directDependencies(shape.value)),
          hasLength(1),
        );
        expect(unjustifiedDependencies(shape.value), ['google_mobile_ads']);
      });
    }
  });

  group('the justification rule, proven both ways', () {
    test('a package with a reason passes, the SDK needs none', () {
      const pubspec = '''
dependencies:
  flutter:
    sdk: flutter
  collection: ^1.19.0 # why: the engine needs ListEquality

dev_dependencies:
  flutter_lints: ^6.0.0
''';
      expect(unjustifiedDependencies(pubspec), isEmpty);
    });

    test('a package without a reason is caught', () {
      const pubspec = '''
dependencies:
  collection: ^1.19.0
  path: ^1.9.0 # why:
''';
      expect(unjustifiedDependencies(pubspec), ['collection', 'path']);
    });
  });

  group('the real pubspec.yaml', () {
    late String pubspec;

    setUpAll(() => pubspec = readFile('pubspec.yaml'));

    test('declares no blocked dependency', () {
      final names = directDependencies(pubspec);
      expect(
        names,
        contains('yaml'),
        reason: 'dependency-reader: found no dependencies at all',
      );
      final offenders = blockedDependencies(names);
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('dependency-policy', offenders),
      );
    });

    test('justifies every dependency', () {
      final offenders = unjustifiedDependencies(pubspec);
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('missing-why', offenders),
      );
    });
  });
}
