@Tags(['guard'])
library;

// The engine must run in a plain Dart isolate, away from the UI thread
// (CLAUDE.md invariant 4), so nothing under lib/engine/ may reach Flutter,
// dart:ui or dart:io. This reads every directive of every engine file —
// import, export and part, conditional URIs included — and allows only the
// listed dart: libraries and URIs that stay inside the engine.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const engineDir = 'lib/engine';

/// The only `dart:` libraries an engine file may use.
const allowedDartLibraries = {
  'dart:core',
  'dart:math',
  'dart:collection',
  'dart:typed_data',
  'dart:convert',
  'dart:isolate',
  'dart:async',
};

// A directive runs from its keyword to its semicolon; comments are removed
// first so a commented-out import neither hides nor adds a URI.
final _directive = RegExp(
  r'^\s*(?:import|export|part)\b(?!\s+of\b)([^;]*);',
  multiLine: true,
);
final _uri = RegExp(r'''(?:'([^']*)'|"([^"]*)")''');
final _comment = RegExp(r'//[^\n]*|/\*[\s\S]*?\*/');

/// Every URI named by an import, export or part directive in [source].
List<String> directiveUris(String source) => [
  for (final d in _directive.allMatches(source.replaceAll(_comment, '')))
    for (final u in _uri.allMatches(d.group(1)!)) u.group(1) ?? u.group(2)!,
];

/// Why [uri], used by the engine file at repository path [from], is not
/// allowed — or null when it is.
String? refusal(String from, String uri) {
  if (uri.startsWith('dart:')) {
    return allowedDartLibraries.contains(uri)
        ? null
        : '$uri is not an allowed dart: library';
  }
  if (uri.startsWith('package:')) {
    return uri.startsWith('package:honest_chess/engine/')
        ? null
        : '$uri is a package outside the engine';
  }
  if (uri.contains(':')) return '$uri is not a relative engine file';
  final segments = from.split('/')..removeLast();
  for (final part in uri.split('/')) {
    if (part == '..') {
      if (segments.isEmpty) return '$uri leaves the repository';
      segments.removeLast();
    } else if (part != '.') {
      segments.add(part);
    }
  }
  final resolved = segments.join('/');
  return resolved.startsWith('$engineDir/')
      ? null
      : '$uri resolves to $resolved, outside $engineDir/';
}

void main() {
  group('directive scanning', () {
    test('finds every URI, conditional ones included', () {
      expect(
        directiveUris('''
import 'a.dart';
export "b.dart" show X;
part 'c.dart';
part of 'engine.dart';
import 'd.dart'
    if (dart.library.io) 'e.dart'
    if (dart.library.js_interop) "f.dart";
// import 'package:flutter/material.dart';
/* import 'dart:io'; */
'''),
        ['a.dart', 'b.dart', 'c.dart', 'd.dart', 'e.dart', 'f.dart'],
      );
    });

    test('refuses Flutter, dart:ui, dart:io and escapes from the engine', () {
      const from = 'lib/engine/position.dart';
      for (final bad in [
        'package:flutter/foundation.dart',
        'package:honest_chess/main.dart',
        'dart:ui',
        'dart:io',
        'dart:ffi',
        '../main.dart',
        '../../lib/engine/../main.dart',
        'file:///tmp/x.dart',
      ]) {
        expect(refusal(from, bad), isNotNull, reason: bad);
      }
      for (final good in [
        'dart:math',
        'dart:typed_data',
        'square.dart',
        './piece.dart',
        'package:honest_chess/engine/fen.dart',
      ]) {
        expect(refusal(from, good), isNull, reason: good);
      }
      expect(refusal('lib/engine/search/tt.dart', '../square.dart'), isNull);
    });
  });

  test('every engine file imports only pure Dart and engine files', () {
    expect(
      pathExists('$engineDir/position.dart'),
      isTrue,
      reason:
          'engine-purity: $engineDir/position.dart is missing, so this guard '
          'would pass over an empty engine',
    );
    final files = [
      for (final entity in Directory(
        '${repoRoot.path}/$engineDir',
      ).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.path.substring(repoRoot.path.length + 1),
    ]..sort();
    final offenders = [
      for (final path in files)
        for (final uri in directiveUris(readFile(path)))
          if (refusal(path, uri) case final why?) '$path: $why',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'engine-purity: ${offenders.length} offender(s); the engine must '
          'import only ${allowedDartLibraries.join(', ')} and engine files, '
          'so it runs in a plain Dart isolate:\n${offenders.join('\n')}',
    );
  });
}
