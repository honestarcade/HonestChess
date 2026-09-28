@Tags(['guard'])
library;

// docs/privacy.md is what the Play listing links to, so it must describe this
// app: its package id and name as app_identity.yaml holds them, and the two
// promises the listing's data-safety answers rest on — no data collected and
// no permissions requested. It does not check the rest of the prose.

import 'package:flutter_test/flutter_test.dart';

import 'app_identity.dart';
import 'repo_files.dart';

const policyPath = 'docs/privacy.md';

/// [markdown] lower-cased, emphasis markers removed and whitespace runs
/// collapsed, so "**no\n  permissions**" reads as "no permissions".
String plain(String markdown) => markdown
    .replaceAll(RegExp(r'[*_`]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

/// What [policy] fails to say about the app [id], one line per gap.
List<String> policyGaps(String policy, AppIdentity id) {
  final text = plain(policy);
  return [
    if (!RegExp(r'^permalink: /privacy$', multiLine: true).hasMatch(policy))
      'no "permalink: /privacy" front matter',
    if (!policy.contains('`${id.packageId}`'))
      'does not name the package `${id.packageId}`',
    if (!policy.contains(id.label)) 'does not name the app "${id.label}"',
    if (!text.contains('no data')) 'does not say "no data" is collected',
    if (!text.contains('no permissions')) 'does not say "no permissions"',
  ];
}

void main() {
  late AppIdentity id;

  setUpAll(() => id = readIdentity());

  group('the rule, proven both ways', () {
    test('a policy naming the app and both promises passes', () {
      final policy =
          '---\npermalink: /privacy\n---\n# ${id.label}\n'
          'Package `${id.packageId}` collects **no data** and requests '
          '**no permissions**.\n';
      expect(policyGaps(policy, id), isEmpty);
    });

    test('another app\'s policy is refused', () {
      const policy =
          '---\npermalink: /privacy\n---\n# Honest Solitaire\n'
          'Package `com.honestarcade.solitaire` collects no data and requests '
          'no permissions.\n';
      expect(policyGaps(policy, id), hasLength(2));
    });

    test('a policy missing a promise is refused', () {
      final policy =
          '---\npermalink: /privacy\n---\n# ${id.label}\n'
          'Package `${id.packageId}` collects no data.\n';
      expect(policyGaps(policy, id), ['does not say "no permissions"']);
    });

    test('a promise wrapped across lines still counts', () {
      final policy =
          '---\npermalink: /privacy\n---\n# ${id.label}\n'
          'Package `${id.packageId}` collects **no\n  data** and requests **no\n'
          '  permissions**.\n';
      expect(policyGaps(policy, id), isEmpty);
    });
  });

  test('docs/privacy.md describes this app', () {
    final gaps = policyGaps(readFile(policyPath), id);
    expect(gaps, isEmpty, reason: describeOffenders('privacy-policy', gaps));
  });
}
