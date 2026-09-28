@Tags(['guard', 'slow'])
library;

// verify_upload_cert.sh is the release's check that the bundle carries the key
// Play enrolled, so it must be seen to refuse. Two throwaway keys are made on
// the spot and a zip is signed with one of them: its own certificate matches,
// the other key's does not, and an unsigned bundle is refused outright.
// Tagged slow: keytool and jarsigner are JVM start-ups.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'stubs.dart';

void main() {
  late Directory dir;
  late String keytool;
  late String signed;
  late String unsigned;
  late String ownPem;
  late String otherPem;

  void ok(ProcessResult r) {
    if (r.exitCode != 0) throw StateError('${r.stdout}${r.stderr}');
  }

  String makeKey(String name) {
    final ks = '${dir.path}/$name.p12';
    final common = [
      '-keystore', ks, '-storetype', 'PKCS12', //
      '-storepass', 'throwaway-pass', '-alias', 'k',
    ];
    ok(
      Process.runSync(keytool, [
        '-genkeypair', ...common, '-keyalg', 'RSA', '-keysize', '2048', //
        '-validity', '2', '-dname', 'CN=$name',
      ]),
    );
    final pem = '${dir.path}/$name.pem';
    ok(
      Process.runSync(keytool, [
        '-exportcert',
        '-rfc',
        ...common,
        '-file',
        pem,
      ]),
    );
    return ks;
  }

  setUpAll(() {
    keytool = jdkTool('keytool');
    dir = Directory.systemTemp.createTempSync('upload-cert');
    final ownKs = makeKey('own');
    makeKey('other');
    ownPem = '${dir.path}/own.pem';
    otherPem = '${dir.path}/other.pem';
    File('${dir.path}/payload.txt').writeAsStringSync('not an app');
    for (final name in ['signed.aab', 'unsigned.aab']) {
      ok(
        Process.runSync('zip', [
          '-q',
          name,
          'payload.txt',
        ], workingDirectory: dir.path),
      );
    }
    signed = '${dir.path}/signed.aab';
    unsigned = '${dir.path}/unsigned.aab';
    ok(
      Process.runSync(jdkTool('jarsigner'), [
        '-keystore', ownKs, '-storetype', 'PKCS12', //
        '-storepass', 'throwaway-pass', signed, 'k',
      ]),
    );
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  ProcessResult verify(String bundle, String pem) => Process.runSync(
    'bash',
    [tool('verify_upload_cert.sh'), bundle],
    environment: {'HS_KEYTOOL': keytool, 'HS_UPLOAD_CERT': pem},
  );

  test('positive control: the signing key\'s own certificate matches', () {
    final r = verify(signed, ownPem);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('MATCH'));
  });

  test('a bundle signed by another key is refused', () {
    final r = verify(signed, otherPem);
    expect(
      [r.exitCode, '${r.stderr}'.contains('MISMATCH')],
      [1, true],
      reason:
          'upload-cert: a bundle signed by another key passed\n'
          '${r.stdout}${r.stderr}',
    );
  });

  test('an unsigned bundle is refused', () {
    final r = verify(unsigned, ownPem);
    expect(
      r.exitCode,
      2,
      reason: 'upload-cert: an unsigned bundle passed\n${r.stdout}${r.stderr}',
    );
  });

  test('a missing certificate is refused', () {
    final r = verify(signed, '${dir.path}/absent.pem');
    expect(r.exitCode, 2, reason: '${r.stdout}${r.stderr}');
  });
}
