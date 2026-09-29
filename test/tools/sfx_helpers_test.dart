// tools/sfx.py's offline helpers, through tools/test_sfx.py (#95), so the
// gate runs the Python tests with no CI change. A missing python3 fails
// rather than skips: a helper test that quietly stops running is no test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tools/test_sfx.py passes', () async {
    final ProcessResult result;
    try {
      result = await Process.run(
        'python3',
        ['-m', 'unittest', 'tools.test_sfx'],
        environment: {'PYTHONDONTWRITEBYTECODE': '1'},
      );
    } on ProcessException catch (e) {
      fail('python3 could not be started: ${e.message}');
    }
    expect(
      result.exitCode,
      0,
      reason:
          'python3 -m unittest tools.test_sfx failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });
}
