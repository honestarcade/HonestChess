@Tags(['guard'])
library;

// Every tick goes through lib/feedback/haptics.dart (#97), so the Haptics
// setting is honoured in one place. A HapticFeedback call pasted anywhere
// else — or Flutter's own Feedback helper, or Android's performHapticFeedback
// in the app's Kotlin — would tick with the setting off. Comments are
// stripped; string literals are read too, so the channel's method name
// cannot be invoked by hand either. (Honest Solitaire's guard, reused.)

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const allowed = 'lib/feedback/haptics.dart';

/// Where every Android source set of the app lives.
const androidSources = 'android/app/src';

final _bannedDart = RegExp(
  r"'HapticFeedback\.vibrate'|HapticFeedback\.|Feedback\.forTap|"
  r'Feedback\.forLongPress',
);

final _bannedKotlin = RegExp(r'performHapticFeedback');

/// `<match> in <path>` for every banned use in [source]'s Dart code.
List<String> hapticOffenders(String path, String source) => [
  for (final m in _bannedDart.allMatches(stripDartComments(source)))
    '${m.group(0)} in $path',
];

/// `<match> in <path>` for every haptic call in [source]'s Kotlin code;
/// Kotlin's comments are Dart's.
List<String> kotlinHapticOffenders(String path, String source) => [
  for (final m in _bannedKotlin.allMatches(stripDartComments(source)))
    '${m.group(0)} in $path',
];

void main() {
  group('the rules', () {
    test('code is read, comments are not', () {
      const src = '''
// HapticFeedback.lightImpact() in a comment
/* Feedback.forTap in a block */
void undo() { HapticFeedback.lightImpact(); }
void press(BuildContext c) { Feedback.forLongPress(c); Feedback.forTap(c); }
final name = 'HapticFeedback.vibrate';
''';
      expect(hapticOffenders('lib/x.dart', src), [
        'HapticFeedback. in lib/x.dart',
        'Feedback.forLongPress in lib/x.dart',
        'Feedback.forTap in lib/x.dart',
        "'HapticFeedback.vibrate' in lib/x.dart",
      ]);
      const kotlin = '''
// view.performHapticFeedback(0)
fun tick(view: View) { view.performHapticFeedback(1) }
''';
      expect(kotlinHapticOffenders('a.kt', kotlin), [
        'performHapticFeedback in a.kt',
      ]);
    });
  });

  test('the port exists and ticks with lightImpact', () {
    expect(
      pathExists(allowed),
      isTrue,
      reason: 'haptics-scan: $allowed missing',
    );
    expect(
      stripDartComments(readFile(allowed)),
      contains('HapticFeedback.lightImpact()'),
      reason: 'haptics-scan: $allowed no longer ticks with lightImpact',
    );
  });

  test('nothing outside the port calls HapticFeedback or Feedback', () {
    final dartFiles = [
      for (final path in trackedFilesUnder('lib'))
        if (path.endsWith('.dart')) path,
    ];
    expect(dartFiles, contains(allowed));
    final offenders = [
      for (final path in dartFiles)
        if (path != allowed) ...hapticOffenders(path, readFile(path)),
    ];
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('haptics-scan: Dart', offenders),
    );
  });

  test('no Kotlin file of the app calls performHapticFeedback', () {
    final kotlinFiles = [
      for (final path in filesUnder(androidSources))
        if (path.endsWith('.kt')) path,
    ];
    expect(kotlinFiles, isNotEmpty, reason: 'haptics-scan: no Kotlin found');
    final offenders = [
      for (final path in kotlinFiles)
        ...kotlinHapticOffenders(path, readFile(path)),
    ];
    expect(
      offenders,
      isEmpty,
      reason: describeOffenders('haptics-scan: Kotlin', offenders),
    );
  });
}
