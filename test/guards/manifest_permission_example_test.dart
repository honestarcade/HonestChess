@Tags(['guard'])
library;

// The source half of the no-permissions rule (CLAUDE.md invariant 1): no
// manifest outside the debug and profile source sets requests a permission,
// no manifest declares one, and no manifest a build reads strips one at build
// time. Flutter's own dev-only INTERNET request lives in debug and profile,
// which are never uploaded. tools/check_aab.sh is the artefact half, since a
// plugin's merged manifest is visible only in the built bundle;
// bundle_scan_test.dart proves that script fails.

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

/// `<uses-permission>` and `<uses-permission-sdk-23>` elements in
/// [manifestXml], comments removed.
List<String> usesPermissionOffenders(String manifestXml) =>
    RegExp(r'<uses-permission\b[^>]*>')
        .allMatches(stripXmlComments(manifestXml))
        .map((m) => m.group(0)!)
        .toList();

/// `<permission>`, `<permission-group>` and `<permission-tree>` elements in
/// [manifestXml]. A declaration grants this app nothing, but the bundle scan
/// refuses one, so the source refuses it first.
List<String> permissionElementOffenders(String manifestXml) =>
    RegExp(r'<permission(?:-group|-tree)?\b[^>]*>')
        .allMatches(stripXmlComments(manifestXml))
        .map((m) => m.group(0)!)
        .toList();

/// Build-time removal rules (`tools:node="remove"`, `"removeAll"` or
/// `"replace"`, and `tools:remove="…"`). A plugin that brings a permission is
/// refused, not adopted and then stripped: a removal rule hides the permission
/// from this guard while the plugin still expects it.
List<String> removalRuleOffenders(String manifestXml) =>
    RegExp(r'tools:node\s*=\s*"(?:remove|removeAll|replace)"|tools:remove\s*=')
        .allMatches(stripXmlComments(manifestXml))
        .map((m) => m.group(0)!)
        .toList();

/// Every AndroidManifest.xml under android/ a build would read — on disk,
/// tracked or not, build output excluded.
List<String> sourceManifests() =>
    filesUnder('android')
        .where((p) => p.endsWith('AndroidManifest.xml'))
        .where((p) => !p.contains('/build/') && !p.contains('/.gradle/'))
        .toList();

const mainManifest = 'android/app/src/main/AndroidManifest.xml';

/// The manifests that may not request a permission: all of [manifests] but
/// the debug and profile source sets, which carry Flutter's dev-only
/// INTERNET and never reach Play.
List<String> requestScopedManifests(Iterable<String> manifests) => [
  for (final path in manifests)
    if (!path.contains('/src/debug/') && !path.contains('/src/profile/')) path,
];

void main() {
  group('the real manifests', () {
    late List<String> manifests;

    setUpAll(() => manifests = sourceManifests());

    test('the reader finds every source set', () {
      expect(
        manifests,
        containsAll([
          mainManifest,
          'android/app/src/debug/AndroidManifest.xml',
          'android/app/src/profile/AndroidManifest.xml',
        ]),
        reason: 'manifest-reader: the source manifests were not all found',
      );
    });

    test('no manifest outside debug and profile requests a permission', () {
      final scoped = requestScopedManifests(manifests);
      expect(scoped, contains(mainManifest));
      final offenders = [
        for (final path in scoped)
          for (final e in usesPermissionOffenders(readFile(path))) '$path: $e',
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('permission-guard', offenders),
      );
    });

    test('no manifest declares a permission', () {
      final offenders = [
        for (final path in manifests)
          for (final e in permissionElementOffenders(readFile(path)))
            '$path: $e',
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('manifest-permission-element', offenders),
      );
    });

    test('no manifest under android/ carries a removal rule', () {
      final offenders = [
        for (final path in manifests)
          for (final rule in removalRuleOffenders(readFile(path)))
            '$path: $rule',
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('manifest-removal-rule', offenders),
      );
    });
  });

  group('the rules, proven both ways', () {
    test('a clean manifest passes', () {
      const clean = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="app">
        <activity android:name=".MainActivity" />
    </application>
</manifest>
''';
      expect(usesPermissionOffenders(clean), isEmpty);
      expect(permissionElementOffenders(clean), isEmpty);
      expect(removalRuleOffenders(clean), isEmpty);
    });

    test('a requested permission is caught, in either element', () {
      const dirty = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission-sdk-23 android:name="android.permission.CAMERA" />
    <application android:label="app" />
</manifest>
''';
      final offenders = usesPermissionOffenders(dirty);
      expect(offenders, hasLength(2));
      expect(offenders.first, contains('android.permission.INTERNET'));
    });

    test('permission declarations of all three kinds are caught', () {
      const dirty = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <permission android:name="com.x.P" />
    <permission-group android:name="com.x.G" />
    <permission-tree android:name="com.x.T" />
    <application android:label="app" />
</manifest>
''';
      expect(permissionElementOffenders(dirty), hasLength(3));
    });

    test('every removal rule shape is caught, a merge rule is not', () {
      const dirty = '''
<uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
<uses-permission android:name="android.permission.CAMERA" tools:node = "removeAll" />
<uses-permission android:name="android.permission.CAMERA" tools:node="replace" />
<application tools:remove="android:allowBackup" />
<activity tools:node="merge" />
''';
      expect(removalRuleOffenders(dirty), hasLength(4));
    });

    test(
      'only debug and profile may request, every other source set may not',
      () {
        expect(
          requestScopedManifests([
            'android/app/src/main/AndroidManifest.xml',
            'android/app/src/debug/AndroidManifest.xml',
            'android/app/src/profile/AndroidManifest.xml',
            'android/app/src/release/AndroidManifest.xml',
            'android/app/src/staging/AndroidManifest.xml',
          ]),
          [
            'android/app/src/main/AndroidManifest.xml',
            'android/app/src/release/AndroidManifest.xml',
            'android/app/src/staging/AndroidManifest.xml',
          ],
        );
      },
    );

    test('a commented-out element or rule does not count', () {
      const commented = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- <uses-permission android:name="android.permission.INTERNET" /> -->
    <!-- <permission android:name="com.x.P" /> -->
    <!-- <uses-permission tools:node="remove" /> -->
    <application android:label="app" />
</manifest>
''';
      expect(usesPermissionOffenders(commented), isEmpty);
      expect(permissionElementOffenders(commented), isEmpty);
      expect(removalRuleOffenders(commented), isEmpty);
    });
  });
}
