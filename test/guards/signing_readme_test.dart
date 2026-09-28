@Tags(['guard'])
library;

// android/signing/README.md states the upload certificate's SHA-256. The
// owner compares that line with the Play Console's upload key, so a README
// that drifts from the committed certificate sends them to the wrong key.
// This computes the fingerprint from the PEM itself.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';
import 'sha256.dart';

const readmePath = 'android/signing/README.md';
const pemPath = 'android/signing/upload_certificate.pem';

/// The certificate's DER bytes, from a PEM's base64 body.
List<int> derOf(String pem) {
  final body = RegExp(
    r'-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----',
    dotAll: true,
  ).firstMatch(pem);
  if (body == null) throw const FormatException('no certificate in the PEM');
  return base64.decode(body.group(1)!.replaceAll(RegExp(r'\s'), ''));
}

/// The fingerprints on the README's `| SHA-256 |` rows.
List<String> readmeFingerprints(String readme) => [
  for (final m in RegExp(
    r'^\| SHA-256 \| `([0-9A-F:]+)` \|',
    multiLine: true,
  ).allMatches(readme))
    m.group(1)!,
];

/// Why [readme] does not state [pem]'s fingerprint, or null when it does.
String? fingerprintMismatch(String readme, String pem) {
  final stated = readmeFingerprints(readme);
  final actual = colonHex(sha256(derOf(pem)));
  if (stated.length != 1) {
    return 'signing-readme: expected one SHA-256 row, found ${stated.length}';
  }
  if (stated.single != actual) {
    return 'signing-readme: README says ${stated.single}, '
        'the certificate is $actual';
  }
  return null;
}

void main() {
  group('sha256', () {
    test('matches the FIPS 180-4 test vectors', () {
      expect(
        colonHex(sha256(utf8.encode('abc'))),
        colonHex(
          _hex(
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          ),
        ),
      );
      expect(
        colonHex(sha256(const [])),
        colonHex(
          _hex(
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          ),
        ),
      );
      expect(
        colonHex(
          sha256(
            utf8.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
            ),
          ),
        ),
        colonHex(
          _hex(
            '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
          ),
        ),
      );
    });
  });

  group('proven both ways', () {
    final pem = File('${repoRoot.path}/$pemPath').readAsStringSync();
    final actual = colonHex(sha256(derOf(pem)));

    test('a README stating the right fingerprint passes', () {
      expect(fingerprintMismatch('| SHA-256 | `$actual` |\n', pem), isNull);
    });

    test('a README with one wrong pair is refused', () {
      final wrong = '00${actual.substring(2)}';
      expect(
        fingerprintMismatch('| SHA-256 | `$wrong` |\n', pem),
        contains('signing-readme: README says'),
      );
    });

    test('a README with no fingerprint row is refused', () {
      expect(fingerprintMismatch('no table here\n', pem), contains('found 0'));
    });
  });

  test('the README states the committed certificate\'s fingerprint', () {
    final readme = File('${repoRoot.path}/$readmePath').readAsStringSync();
    final pem = File('${repoRoot.path}/$pemPath').readAsStringSync();
    final mismatch = fingerprintMismatch(readme, pem);
    expect(mismatch, isNull, reason: mismatch);
  });
}

List<int> _hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];
