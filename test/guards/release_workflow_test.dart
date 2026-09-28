@Tags(['guard'])
library;

// release.yml's order is its safety property: a tag re-runs the whole PR gate,
// the bundle is built with signing that fails closed, and nothing is published
// — to Play, to the GitHub release, or as an artifact — until the bundle has
// been scanned for permissions and matched against the committed upload
// certificate. None of those steps may be skipped or allowed to fail quietly,
// and the decoded keystore is removed however the job ends.

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'repo_files.dart';
import 'workflows.dart';

bool _isPlayUpload(YamlMap s) =>
    '${s['uses']}'.startsWith('r0adkll/upload-google-play@');

bool _publishes(YamlMap s) =>
    _isPlayUpload(s) ||
    '${s['uses']}'.startsWith('actions/upload-artifact@') ||
    RegExp(r'gh release upload|tools/attach_release_asset\.sh')
        .hasMatch('${s['run'] ?? ''}');

/// Every property [workflow] breaks, by name.
List<String> releaseOrderViolations(YamlMap workflow) {
  final violations = <String>[];
  final on = triggers(workflow);
  final push = on is YamlMap ? on['push'] : null;
  final tags = push is YamlMap ? push['tags'] : null;
  if (on is! YamlMap ||
      on.keys.toList().join(',') != 'push' ||
      push is! YamlMap ||
      push.keys.toList().join(',') != 'tags' ||
      tags is! YamlList ||
      tags.join(',') != 'v*') {
    violations.add('triggers only on v* tags');
  }
  final jobs = jobsOf(workflow);
  final gate = jobs['gate'];
  if (gate is! YamlMap || gate['uses'] != './.github/workflows/ci.yml') {
    violations.add('the gate job is ci.yml itself');
  }
  final ship = jobs['ship'];
  if (ship is! YamlMap) return [...violations, 'a ship job exists'];
  final needs = ship['needs'];
  if (!(needs is YamlList ? needs.toList() : [needs]).contains('gate')) {
    violations.add('ship needs gate');
  }
  if (ship['if'] != null || ship['continue-on-error'] != null) {
    violations.add('ship has no if: or continue-on-error');
  }

  final steps = stepsOf(ship);
  final build = steps.indexWhere(
    (s) => '${s['run']}'.contains('flutter build appbundle'),
  );
  final scan = steps.indexWhere((s) => s['run'] == 'tools/check_aab.sh');
  final cert = steps.indexWhere(
    (s) => s['run'] == 'tools/verify_upload_cert.sh',
  );
  final publishing = [
    for (var i = 0; i < steps.length; i++)
      if (_publishes(steps[i])) i,
  ];
  if (build < 0) return [...violations, 'a build step exists'];
  if (!steps.any(_isPlayUpload)) {
    return [...violations, 'a Play upload step exists'];
  }
  if ((steps[build]['env'] as YamlMap?)?['HS_RELEASE'] != '1') {
    violations.add('the build sets HS_RELEASE to "1"');
  }
  for (final (name, index) in [
    ('the permission scan', scan),
    ('the certificate check', cert),
  ]) {
    if (index < build ||
        publishing.any((p) => p < index) ||
        publishing.isEmpty) {
      violations.add('$name runs after the build and before any publish');
    }
  }
  for (final (name, index) in [
    ('the build', build),
    ('the permission scan', scan),
    ('the certificate check', cert),
  ]) {
    if (index >= 0 &&
        (steps[index]['if'] != null ||
            steps[index]['continue-on-error'] != null)) {
      violations.add('$name has no if: or continue-on-error');
    }
  }
  if (steps
      .where(_isPlayUpload)
      .any((s) => (s['with'] as YamlMap?)?['track'] != 'internal')) {
    violations.add('every Play upload targets internal');
  }
  if (!steps.any(
    (s) =>
        s['if'] == 'always()' &&
        '${s['run']}'.contains(r'rm -f "$RUNNER_TEMP/upload.keystore"'),
  )) {
    violations.add('an always() step removes the decoded keystore');
  }
  return violations;
}

void main() {
  const good = r'''
on:
  push:
    tags: ['v*']
jobs:
  gate:
    uses: ./.github/workflows/ci.yml
  ship:
    needs: gate
    steps:
      - run: flutter build appbundle --release
        env:
          HS_RELEASE: "1"
      - run: tools/check_aab.sh
      - run: tools/verify_upload_cert.sh
      - uses: actions/upload-artifact@v7
      - run: tools/attach_release_asset.sh
      - uses: r0adkll/upload-google-play@v1
        with:
          track: internal
      - if: always()
        run: rm -f "$RUNNER_TEMP/upload.keystore"
''';

  List<String> violations(String yaml) =>
      releaseOrderViolations(parseWorkflow(yaml));

  group('the rule, proven both ways', () {
    test('the safe order passes', () {
      expect(violations(good), isEmpty);
    });

    test('each broken property is named', () {
      final broken = good
          .replaceFirst("tags: ['v*']", "tags: ['*']")
          .replaceFirst('    needs: gate\n', '')
          .replaceFirst('HS_RELEASE: "1"', 'HS_RELEASE: "0"')
          .replaceFirst('      - run: tools/verify_upload_cert.sh\n', '')
          .replaceFirst('track: internal', 'track: production')
          .replaceFirst('      - if: always()\n', '      - if: success()\n');
      expect(violations(broken), [
        'triggers only on v* tags',
        'ship needs gate',
        'the build sets HS_RELEASE to "1"',
        'the certificate check runs after the build and before any publish',
        'every Play upload targets internal',
        'an always() step removes the decoded keystore',
      ]);
    });

    test('a check moved after a publish is caught', () {
      final late = good
          .replaceFirst('      - run: tools/check_aab.sh\n', '')
          .replaceFirst(
            '      - run: tools/attach_release_asset.sh\n',
            '      - run: tools/attach_release_asset.sh\n'
                '      - run: tools/check_aab.sh\n',
          );
      expect(violations(late), [
        'the permission scan runs after the build and before any publish',
      ]);
    });

    test('a skippable or lenient check is caught', () {
      final skippable = good
          .replaceFirst(
            '      - run: tools/check_aab.sh\n',
            '      - run: tools/check_aab.sh\n        if: false\n',
          )
          .replaceFirst(
            '      - run: tools/verify_upload_cert.sh\n',
            '      - run: tools/verify_upload_cert.sh\n'
                '        continue-on-error: true\n',
          );
      expect(violations(skippable), [
        'the permission scan has no if: or continue-on-error',
        'the certificate check has no if: or continue-on-error',
      ]);
    });

    test('a second trigger is caught', () {
      expect(
        violations(good.replaceFirst('on:\n', 'on:\n  workflow_dispatch:\n')),
        ['triggers only on v* tags'],
      );
    });
  });

  test('the real release.yml keeps its order', () {
    final found = releaseOrderViolations(
      readWorkflow('.github/workflows/release.yml'),
    );
    expect(found, isEmpty, reason: describeOffenders('release-order', found));
  });
}
