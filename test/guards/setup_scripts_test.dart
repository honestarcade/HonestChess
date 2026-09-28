@Tags(['guard'])
library;

// The one-time setup scripts handle the upload key and the Play service
// account key, so their refusals must be seen to fire: make_upload_key.sh
// never overwrites a key, a credentials file or the committed certificate;
// set_ci_secrets.sh uploads nothing unless the credentials open the keystore;
// setup_play_ci.sh refuses an unconfirmed gcloud account and never leaves the
// service account key on disk. Each runs with keytool, gh and gcloud stubbed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'stubs.dart';

// Writes the files keytool would, from its -keystore and -file arguments.
const _keytool = r'''#!/bin/bash
[ "${KEYTOOL_FAIL:-}" = 1 ] && [ "$1" != -help ] && { echo "keytool: bad password" >&2; exit 1; }
ks=""; file=""; mode="$1"
while [ $# -gt 0 ]; do
  case "$1" in
    -keystore) ks="$2"; shift 2 ;;
    -file) file="$2"; shift 2 ;;
    -help) echo "Key and Certificate Management Tool"; exit 0 ;;
    *) shift ;;
  esac
done
case "$mode" in
  -genkeypair) echo keystore > "$ks" ;;
  -exportcert) echo PEM > "$file" ;;
  -printcert) echo "SHA256: AA:BB" ;;
esac
exit 0
''';

const _gh = r'''#!/bin/bash
echo "$*" >> "$RUNNER_TEMP/gh.log"
case "$1 $2" in
  "secret set")
    cat > /dev/null
    [ "${GH_SET:-ok}" = ok ] || { echo "HTTP 403" >&2; exit 1; } ;;
esac
exit 0
''';

const _gcloud = r'''#!/bin/bash
echo "$*" >> "$RUNNER_TEMP/gcloud.log"
case "$*" in
  "auth list"*) echo "${GCLOUD_ACCOUNT:-}" ;;
  "services list"*) echo androidpublisher.googleapis.com ;;
  "iam service-accounts keys create"*) echo '{"private_key_id": "k1"}' > "$5" ;;
esac
exit 0
''';

const _password = 'a-long-throwaway-password-for-tests';

/// The files of [paths] that exist under [dir].
List<String> _existing(Directory dir, List<String> paths) =>
    paths.where((p) => File('${dir.path}/$p').existsSync()).toList();

List<String> _log(Directory dir, String name) {
  final f = File('${dir.path}/$name');
  return f.existsSync() ? f.readAsLinesSync() : const [];
}

void main() {
  group('make_upload_key.sh', () {
    const outputs = [
      'secrets/test-upload.keystore',
      'secrets/test-signing-credentials.txt',
      'cert/upload.pem',
    ];

    ({ScriptRun run, List<String> made, String credentials}) makeKey({
      Map<String, String> env = const {},
      Map<String, String> files = const {},
    }) {
      var made = <String>[];
      var credentials = '';
      final run = runWithStubs(
        [tool('make_upload_key.sh')],
        stubs: {'keytool': _keytool},
        files: files,
        env: {
          'HS_KEYTOOL': '{dir}/bin/keytool',
          'HS_SECRETS_DIR': '{dir}/secrets',
          'HS_UPLOAD_CERT_OUT': '{dir}/cert/upload.pem',
          'HS_APP_SLUG': 'test',
          'HS_KEYSTORE_PASS': _password,
          ...env,
        },
        inspect: (dir) {
          made = _existing(dir, outputs);
          final c = File('${dir.path}/${outputs[1]}');
          credentials = c.existsSync() ? c.readAsStringSync() : '';
        },
      );
      return (run: run, made: made, credentials: credentials);
    }

    test('positive control: every file is written, no password printed', () {
      final r = makeKey();
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect(r.made, outputs);
      expect(r.credentials, contains('HS_KEYSTORE_PASS="$_password"'));
      expect(r.run.output, isNot(contains(_password)));
    });

    for (final existing in outputs) {
      test('an existing ${existing.split('/').last} is never overwritten', () {
        final r = makeKey(files: {existing: 'ORIGINAL'});
        expect(
          [r.run.exitCode, r.made],
          [
            2,
            [existing],
          ],
          reason:
              'setup-scripts: make_upload_key.sh wrote over or beside an '
              'existing $existing\n${r.run.output}',
        );
      });
    }

    test('a missing or short password is refused before keytool runs', () {
      for (final pass in ['', 'short', 'x' * 31]) {
        final r = makeKey(env: {'HS_KEYSTORE_PASS': pass});
        expect(
          [r.run.exitCode, r.made],
          [2, isEmpty],
          reason:
              'setup-scripts: a ${pass.length}-character password was not '
              'refused\n${r.run.output}',
        );
      }
    });

    test('a 32-character password is the floor, and accepted (#36)', () {
      final r = makeKey(env: {'HS_KEYSTORE_PASS': 'y' * 32});
      expect(r.run.exitCode, 0, reason: r.run.output);
    });
  });

  group('set_ci_secrets.sh', () {
    const credentials =
        '''
# comment
export HS_KEYSTORE_PATH="{dir}/secrets/test-upload.keystore"
export HS_KEYSTORE_PASS="$_password"
export HS_KEY_ALIAS="upload"
export HS_KEY_PASS="$_password"
''';

    ({ScriptRun run, List<String> gh}) setSecrets({
      Map<String, String> env = const {},
      String? creds = credentials,
    }) {
      var gh = <String>[];
      final run = runWithStubs(
        [tool('set_ci_secrets.sh')],
        stubs: {'keytool': _keytool, 'gh': _gh},
        files: {
          'secrets/test-upload.keystore': 'keystore',
          'secrets/test-signing-credentials.txt': ?creds,
        },
        env: {
          'HS_KEYTOOL': '{dir}/bin/keytool',
          'HS_SECRETS_DIR': '{dir}/secrets',
          'HS_APP_SLUG': 'test',
          'HS_REPO': 'acme/app',
          ...env,
        },
        inspect: (dir) => gh = _log(dir, 'gh.log'),
      );
      return (run: run, gh: gh);
    }

    List<String> secretsSet(List<String> gh) => [
      for (final c in gh)
        if (c.startsWith('secret set ')) c.split(' ')[2],
    ];

    test('positive control: all four secrets are set, none printed', () {
      final r = setSecrets();
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect(secretsSet(r.gh), [
        'HS_KEYSTORE_B64',
        'HS_KEYSTORE_PASS',
        'HS_KEY_ALIAS',
        'HS_KEY_PASS',
      ]);
      expect(r.gh.every((c) => c.contains('-R acme/app')), isTrue);
      expect(r.run.output, isNot(contains(_password)));
    });

    test('credentials that do not open the keystore upload nothing', () {
      final r = setSecrets(env: {'KEYTOOL_FAIL': '1'});
      expect(
        [r.run.exitCode, secretsSet(r.gh)],
        [2, isEmpty],
        reason:
            'setup-scripts: set_ci_secrets.sh uploaded after a failed '
            'pre-flight\n${r.run.output}',
      );
    });

    test('a key password that differs from the store password is refused', () {
      final r = setSecrets(
        creds: credentials.replaceFirst(
          'HS_KEY_PASS="$_password"',
          'HS_KEY_PASS="other"',
        ),
      );
      expect([r.run.exitCode, secretsSet(r.gh)], [2, isEmpty]);
    });

    test('a missing credentials file or repository is refused', () {
      final noFile = setSecrets(creds: null);
      expect([noFile.run.exitCode, secretsSet(noFile.gh)], [2, isEmpty]);
      final noRepo = setSecrets(env: {'HS_REPO': ''});
      expect(noRepo.run.exitCode, isNot(0));
      expect(secretsSet(noRepo.gh), isEmpty);
    });
  });

  group('setup_play_ci.sh', () {
    ({ScriptRun run, List<String> gh, bool keyLeft}) setup(
      Map<String, String> env,
    ) {
      var gh = <String>[];
      var keyLeft = true;
      final run = runWithStubs(
        [tool('setup_play_ci.sh')],
        stubs: {'gcloud': _gcloud, 'gh': _gh},
        env: {
          'HS_SECRETS_DIR': '{dir}/secrets',
          'HS_APP_SLUG': 'test-app',
          'HS_REPO': 'acme/app',
          'GCLOUD_ACCOUNT': 'owner@example.com',
          'HS_PLAY_ACCOUNT': 'owner@example.com',
          ...env,
        },
        inspect: (dir) {
          gh = _log(dir, 'gh.log');
          keyLeft = File('${dir.path}/secrets/test-app-ci.json').existsSync();
        },
      );
      return (run: run, gh: gh, keyLeft: keyLeft);
    }

    bool uploaded(List<String> gh) =>
        gh.any((c) => c.startsWith('secret set PLAY_SERVICE_ACCOUNT_JSON'));

    test('positive control: the key is uploaded, then deleted', () {
      final r = setup({});
      expect(r.run.exitCode, 0, reason: r.run.output);
      expect([uploaded(r.gh), r.keyLeft], [true, false]);
    });

    test('a failed upload still deletes the key', () {
      final r = setup({'GH_SET': 'fail'});
      expect(
        [r.run.exitCode == 0, r.keyLeft],
        [false, false],
        reason:
            'setup-scripts: setup_play_ci.sh left a service account key on '
            'disk after a failed upload\n${r.run.output}',
      );
    });

    test('an unconfirmed or missing gcloud account is refused', () {
      for (final env in [
        {'HS_PLAY_ACCOUNT': 'someone-else@example.com'},
        {'HS_PLAY_ACCOUNT': ''},
        {'GCLOUD_ACCOUNT': ''},
      ]) {
        final r = setup(env);
        expect(
          [r.run.exitCode, uploaded(r.gh)],
          [4, false],
          reason: 'setup-scripts: $env was not refused\n${r.run.output}',
        );
      }
    });
  });
}
