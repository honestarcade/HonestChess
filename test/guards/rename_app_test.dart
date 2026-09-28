@Tags(['guard'])
library;

// tools/rename_app.py is the first command a new app runs, and an app may run
// it again, so from whatever identity the repository holds it must leave
// nothing behind and change nothing when it refuses. Each case copies the
// tracked files to a scratch directory and renames the copy.
// android_identity_test.dart checks the real repository; this checks the
// script that keeps it true. In the template repository, a template-only
// workflow runs the gate and the battery on a renamed clone; the rename
// deleted it here (#34).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'app_identity.dart';
import 'repo_files.dart';

/// A scratch copy of every tracked file.
Directory copyRepository() {
  final dir = Directory.systemTemp.createTempSync('rename-app');
  for (final path in trackedFilesUnder('.')) {
    final source = File('${repoRoot.path}/$path');
    if (!source.existsSync()) continue;
    source.copySync(
      (File('${dir.path}/$path')..parent.createSync(recursive: true)).path,
    );
  }
  return dir;
}

ProcessResult rename(Directory dir, List<String> args) =>
    Process.runSync('python3', ['${dir.path}/tools/rename_app.py', ...args]);

String read(Directory dir, String path) =>
    File('${dir.path}/$path').readAsStringSync();

/// Every file under [dir] with its bytes, to prove a refusal wrote nothing.
Map<String, String> snapshot(Directory dir) => {
  for (final f in dir.listSync(recursive: true).whereType<File>())
    f.path: String.fromCharCodes(f.readAsBytesSync()),
};

/// Files the rename owns that still name [oldId] as a whole id.
List<String> leftovers(Directory dir, String oldId) {
  final token = RegExp('(?<![\\w.])${RegExp.escape(oldId)}(?!\\w)');
  return [
    for (final path in [
      'android/app/build.gradle.kts',
      'android/app/src/main/AndroidManifest.xml',
      'tools/check_aab.sh',
      'app_identity.yaml',
      ...Directory('${dir.path}/.github/workflows')
          .listSync()
          .map((f) => f.path.substring(dir.path.length + 1)),
    ])
      if (token.hasMatch(read(dir, path))) path,
  ];
}

void main() {
  late AppIdentity before;
  late String target;
  late Directory dir;
  late ProcessResult result;

  setUpAll(() {
    before = readIdentity();
    target = before.packageId == 'com.guardtest.renamed'
        ? 'com.guardtest.renamedagain'
        : 'com.guardtest.renamed';
    dir = copyRepository();
    // An app has already lost the template-only workflow; recreate it so the
    // rename's deletion of it is exercised everywhere.
    File('${dir.path}/.github/workflows/template-smoke.yml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: Template smoke\n');
    result = rename(dir, [
      target,
      'Renamed App',
      '--orientation',
      'landscape',
      '--min-sdk',
      '26',
    ]);
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  test('positive control: the rename succeeds', () {
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });

  test('no copy of the old id survives', () {
    final left = leftovers(dir, before.packageId);
    expect(
      left,
      isEmpty,
      reason: describeOffenders('rename-app-leftover', left),
    );
  });

  test('every value lands where the identity guard reads it', () {
    final slug = target.split('.').last;
    final identity = read(dir, 'app_identity.yaml');
    for (final line in [
      'package_id: $target',
      'label: Renamed App',
      'dart_package: renamed_app',
      'slug: $slug',
      'min_sdk: 26',
      'orientation: landscape',
    ]) {
      expect(identity, contains(line));
    }
    expect(
      read(dir, 'android/app/build.gradle.kts'),
      allOf(contains('applicationId = "$target"'), contains('minSdk = 26')),
    );
    expect(
      read(dir, 'android/app/src/main/AndroidManifest.xml'),
      allOf(
        contains('android:label="Renamed App"'),
        contains('android:screenOrientation="landscape"'),
      ),
    );
    expect(read(dir, 'pubspec.yaml'), startsWith('name: renamed_app\n'));
    expect(
      read(dir, 'test/widget_test.dart'),
      contains('package:renamed_app/'),
    );
    expect(
      read(dir, 'tools/setup_play_ci.sh'),
      contains('APP_SLUG="\${HS_APP_SLUG:-$slug}"'),
    );
    expect(
      read(
        dir,
        'android/app/src/main/kotlin/${target.replaceAll('.', '/')}/'
        'MainActivity.kt',
      ),
      contains('package $target\n'),
    );
  });

  test('the old Kotlin source and the template-only workflow are gone', () {
    final survivors = [
      for (final path in [
        '${before.kotlinDir}/MainActivity.kt',
        '.github/workflows/template-smoke.yml',
      ])
        if (FileSystemEntity.typeSync('${dir.path}/$path') !=
            FileSystemEntityType.notFound)
          path,
    ];
    expect(
      survivors,
      isEmpty,
      reason: describeOffenders('rename-app-survivor', survivors),
    );
  });

  test('a refused rename changes nothing', () {
    final scratch = copyRepository();
    try {
      final untouched = snapshot(scratch);
      expect(rename(scratch, ['com.example.other', 'Other']).exitCode, 2);
      expect(snapshot(scratch), untouched);
      // A file that no longer matches the identity: the rename must stop
      // before writing anything, not half-way through.
      final scan = File('${scratch.path}/tools/check_aab.sh');
      scan.writeAsStringSync(
        scan.readAsStringSync().replaceAll(before.packageId, 'x.y'),
      );
      final drifted = snapshot(scratch);
      final mismatch = rename(scratch, ['com.acme.cards', 'Acme Cards']);
      expect(
        [mismatch.exitCode, snapshot(scratch)],
        [1, drifted],
        reason:
            'rename-app-partial: a refused rename wrote files\n'
            '${mismatch.stderr}',
      );
    } finally {
      scratch.deleteSync(recursive: true);
    }
  });
}
