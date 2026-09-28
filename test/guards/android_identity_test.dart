@Tags(['guard'])
library;

// The app's identity: package id, launcher label, Dart package, setup-script
// slug, minSdk, orientation and platforms. app_identity.yaml holds each value
// once; this guard asserts every file that repeats one agrees with it, and
// that a release refuses the template's placeholder id.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'app_identity.dart';
import 'repo_files.dart';

/// The value of `name = "…"` or `name = N` in a Gradle Kotlin script, ignoring
/// `//` comments.
String? gradleValue(String gradle, String name) {
  final code = gradle
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
      .join('\n');
  return RegExp(
    '^\\s*$name\\s*=\\s*"?([^"\\s]+)"?\\s*\$',
    multiLine: true,
  ).firstMatch(code)?.group(1);
}

/// The `<activity>` start tag for `.MainActivity`, comments removed.
String? mainActivityElement(String manifest) => RegExp(
  r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>',
  dotAll: true,
).firstMatch(stripXmlComments(manifest))?.group(0);

/// The orientation [mainActivityElement] locks to, or `any` when unlocked.
String activityOrientation(String activityElement) =>
    RegExp(r'android:screenOrientation="([^"]*)"')
        .firstMatch(activityElement)
        ?.group(1) ??
    'any';

String? applicationLabel(String manifest) => RegExp(
  r'<application\b[^>]*android:label="([^"]*)"',
  dotAll: true,
).firstMatch(stripXmlComments(manifest))?.group(1);

/// Every `com.example.*` id in [text] other than [expected]: what a partial
/// rename leaves behind.
List<String> foreignPackageIds(String text, String expected) =>
    RegExp(r'(?<![A-Za-z0-9_.])com\.example(?:\.[a-z_][a-z0-9_]*)+')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .where((id) => id != expected)
        .toList();

/// Every step in [workflowYaml], across all jobs, keyed by its `id:`.
Map<String, YamlMap> stepsById(String workflowYaml) {
  final jobs = (loadYaml(workflowYaml) as YamlMap)['jobs'] as YamlMap;
  final steps = <String, YamlMap>{};
  for (final job in jobs.values.whereType<YamlMap>()) {
    for (final step
        in (job['steps'] as YamlList? ?? YamlList()).whereType<YamlMap>()) {
      final id = step['id'];
      if (id is String) steps[id] = step;
    }
  }
  return steps;
}

/// The value a shell script gives [variable] when its HS_* override is unset:
/// `NAME="${HS_NAME:-value}"`.
String? scriptDefault(String script, String variable) => RegExp(
  '^$variable="\\\$\\{HS_$variable:-([^}]*)\\}"',
  multiLine: true,
).firstMatch(script)?.group(1);

ProcessResult runReleaseIdentity(String identityYaml) {
  final dir = Directory.systemTemp.createTempSync('identity');
  try {
    final file = File('${dir.path}/app_identity.yaml')
      ..writeAsStringSync(identityYaml);
    return Process.runSync('bash', [
      '${repoRoot.path}/tools/release_identity.sh',
      file.path,
    ]);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

const validIdentity = '''
package_id: com.acme.cards
label: Acme Cards
dart_package: acme_cards
slug: cards
min_sdk: 24
orientation: portrait
platforms: [android]
''';

void main() {
  group('the rules, proven both ways', () {
    test('a valid identity has no problems', () {
      expect(identityProblems(validIdentity), isEmpty);
    });

    test('each malformed field is named', () {
      final cases = {
        'package_id: com.acme.cards': 'package_id: Com.Acme',
        'label: Acme Cards': 'label: Acme "Cards"',
        'dart_package: acme_cards': 'dart_package: Acme-Cards',
        'slug: cards': 'slug: c',
        'min_sdk: 24': 'min_sdk: "24"',
        'orientation: portrait': 'orientation: sideways',
        'platforms: [android]': 'platforms: [ios]',
      };
      for (final MapEntry(key: good, value: bad) in cases.entries) {
        final key = good.split(':').first;
        expect(identityProblems(validIdentity.replaceFirst(good, bad)), [
          startsWith(key),
        ], reason: 'identity rule did not refuse "$bad"');
      }
      expect(identityProblems('package_id: [a'), [startsWith('does not')]);
    });

    test('gradleValue reads quoted and bare values, not comments', () {
      const gradle =
          '  namespace = "a.b"\n'
          '  // minSdk = 19\n'
          '        minSdk = 21\n';
      expect(gradleValue(gradle, 'namespace'), 'a.b');
      expect(gradleValue(gradle, 'minSdk'), '21');
      expect(gradleValue(gradle, 'applicationId'), isNull);
    });

    test('an orientation lock is read, and a commented one is not', () {
      const locked =
          '<activity android:name=".MainActivity" '
          'android:screenOrientation="portrait">';
      expect(activityOrientation(mainActivityElement(locked)!), 'portrait');
      expect(
        activityOrientation(
          mainActivityElement(
            '<!-- $locked --><activity android:name=".MainActivity">',
          )!,
        ),
        'any',
      );
    });

    test('a leftover template id is found, the expected one is not', () {
      const text = 'com.example.your_app com.acme.cards com.example.your_app2';
      expect(foreignPackageIds(text, 'com.acme.cards'), [
        'com.example.your_app',
        'com.example.your_app2',
      ]);
      expect(foreignPackageIds(text, 'com.example.your_app'), [
        'com.example.your_app2',
      ]);
    });

    test('the release pre-flight refuses the placeholder id', () {
      final refused = runReleaseIdentity(
        validIdentity.replaceFirst('com.acme.cards', 'com.example.your_app'),
      );
      expect(
        refused.exitCode,
        1,
        reason:
            'release-identity: the placeholder id was not refused '
            '(stderr: ${refused.stderr})',
      );
      final accepted = runReleaseIdentity(validIdentity);
      expect(accepted.exitCode, 0, reason: '${accepted.stderr}');
      expect((accepted.stdout as String).trim(), 'com.acme.cards');
      expect(runReleaseIdentity('label: x\n').exitCode, 1);
    });
  });

  group('the real app', () {
    late AppIdentity id;

    setUpAll(() => id = readIdentity());

    test('build.gradle.kts names the package and minSdk', () {
      final gradle = readFile('android/app/build.gradle.kts');
      expect(
        [
          gradleValue(gradle, 'namespace'),
          gradleValue(gradle, 'applicationId'),
        ],
        [id.packageId, id.packageId],
        reason:
            'android-identity-gradle: namespace/applicationId is not '
            '${id.packageId}',
      );
      expect(
        gradleValue(gradle, 'minSdk'),
        '${id.minSdk}',
        reason: 'android-identity-min-sdk: minSdk is not ${id.minSdk}',
      );
    });

    test('MainActivity lives in the package', () {
      final path = '${id.kotlinDir}/MainActivity.kt';
      expect(
        pathExists(path),
        isTrue,
        reason: 'android-identity-kotlin: $path does not exist',
      );
      expect(
        readFile(path),
        contains('package ${id.packageId}\n'),
        reason: 'android-identity-kotlin: $path is not in ${id.packageId}',
      );
    });

    test('the launcher label and the orientation', () {
      final manifest = readFile('android/app/src/main/AndroidManifest.xml');
      expect(
        applicationLabel(manifest),
        id.label,
        reason:
            'android-identity-label: the launcher label is not "${id.label}"',
      );
      final activity = mainActivityElement(manifest);
      expect(activity, isNotNull, reason: 'android-identity: no MainActivity');
      expect(
        activityOrientation(activity!),
        id.orientation,
        reason:
            'android-identity-orientation: MainActivity is not locked to '
            '${id.orientation}',
      );
    });

    test('pubspec.yaml names the Dart package', () {
      final pubspec = loadYaml(readFile('pubspec.yaml')) as YamlMap;
      expect(
        pubspec['name'],
        id.dartPackage,
        reason: 'android-identity-dart: pubspec name is not ${id.dartPackage}',
      );
    });

    test('check_aab.sh and every workflow name the same package', () {
      expect(
        readFile('tools/check_aab.sh'),
        contains('PACKAGE="\${APP_PACKAGE_ID:-${id.packageId}}"'),
        reason:
            'android-identity-package: check_aab.sh does not default to '
            '${id.packageId}',
      );
      final named = {
        '.github/workflows/release.yml play packageName': stepsById(
          readFile('.github/workflows/release.yml'),
        )['play']?['with']?['packageName'],
        '.github/workflows/play-api-check.yml play PACKAGE': stepsById(
          readFile('.github/workflows/play-api-check.yml'),
        )['play']?['env']?['PACKAGE'],
        '.github/workflows/play-promote.yml promote PACKAGE': stepsById(
          readFile('.github/workflows/play-promote.yml'),
        )['promote']?['env']?['PACKAGE'],
      };
      final offenders = [
        for (final MapEntry(:key, :value) in named.entries)
          if (value != id.packageId) '$key is $value',
        for (final path in [
          'tools/check_aab.sh',
          'android/app/build.gradle.kts',
          ...trackedFilesUnder('.github/workflows'),
        ]) ...[
          for (final foreign in foreignPackageIds(readFile(path), id.packageId))
            '$path names $foreign',
          if (readFile(path).contains('vars.APP_PACKAGE_ID'))
            '$path reads vars.APP_PACKAGE_ID instead of the literal id',
        ],
      ];
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('android-identity-package', offenders),
      );
    });

    test('the setup scripts default to the same slug and label', () {
      final offenders = <String>[];
      for (final path in [
        'tools/make_upload_key.sh',
        'tools/setup_play_ci.sh',
        'tools/set_ci_secrets.sh',
      ]) {
        final script = readFile(path);
        final slug = scriptDefault(script, 'APP_SLUG');
        if (slug != id.slug) offenders.add('$path APP_SLUG is $slug');
        if (path != 'tools/set_ci_secrets.sh') {
          final label = scriptDefault(script, 'APP_DISPLAY_NAME');
          if (label != id.label) {
            offenders.add('$path APP_DISPLAY_NAME is $label');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('android-identity-scripts', offenders),
      );
    });

    test('exactly the declared platforms exist', () {
      final present = knownPlatforms.where(pathExists).toList()..sort();
      expect(
        present,
        [...id.platforms]..sort(),
        reason: 'android-identity-platform: the platform folders are $present',
      );
    });

    test('a release refuses the placeholder before anything is built', () {
      final steps =
          (((loadYaml(readFile('.github/workflows/release.yml'))
                          as YamlMap)['jobs']
                      as YamlMap)['ship']['steps']
                  as YamlList)
              .whereType<YamlMap>()
              .toList();
      final identity = steps.indexWhere(
        (s) => s['run'] == 'tools/release_identity.sh',
      );
      final firstBuild = steps.indexWhere(
        (s) => '${s['run']}'.contains('flutter build'),
      );
      expect(
        identity >= 0 && firstBuild > identity,
        isTrue,
        reason:
            'release-identity-order: no step runs tools/release_identity.sh '
            'before the bundle is built',
      );
    });
  });
}
