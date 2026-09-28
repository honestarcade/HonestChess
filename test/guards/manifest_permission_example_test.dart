@Tags(['guard'])
library;

// The source half of the no-permissions rule: the main manifest requests and
// declares no permission, and no manifest a build reads strips one at build
// time. tools/check_aab.sh is the artefact half, since a plugin's merged
// manifest is visible only in the built bundle; bundle_scan_test.dart proves
// that script fails.
//
// If your app needs a permission, allow that one by name here and keep the
// rest of the rule, so the guard still tells "clean" from "the parser stopped
// seeing anything".

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

/// Build-time removal rules (`tools:node="remove"` or `"removeAll"`). A plugin
/// that brings a permission is refused, not adopted and then stripped: a
/// removal rule hides the permission from this guard while the plugin still
/// expects it.
List<String> removalRuleOffenders(String manifestXml) =>
    RegExp(r'tools:node\s*=\s*"(?:remove|removeAll)"')
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

void main() {
  group('the real manifests', () {
    test('the main manifest requests no permission', () {
      final offenders = usesPermissionOffenders(readFile(mainManifest));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('permission-guard', offenders),
      );
    });

    test('the main manifest declares no permission', () {
      final offenders = permissionElementOffenders(readFile(mainManifest));
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('manifest-permission-element', offenders),
      );
    });

    test('no manifest under android/ carries a removal rule', () {
      final manifests = sourceManifests();
      expect(
        manifests,
        containsAll([
          mainManifest,
          'android/app/src/debug/AndroidManifest.xml',
        ]),
        reason: 'manifest-reader: the source manifests were not all found',
      );
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

    test('a removal rule is caught, a merge rule is not', () {
      const dirty = '''
<uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
<uses-permission android:name="android.permission.CAMERA" tools:node = "removeAll" />
<activity tools:node="merge" />
''';
      expect(removalRuleOffenders(dirty), hasLength(2));
    });

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
