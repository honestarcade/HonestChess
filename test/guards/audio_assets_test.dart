@Tags(['guard'])
library;

// Every sound the app plays is a real, licensed clip: a short 44.1 kHz mono
// 16-bit WAV named in lib/feedback/clips.dart, recorded in
// assets/audio/LICENSES.md, and bundled one by one (#95). Ported from Honest
// Solitaire's audio guard (its #98) on 2026-09-29.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'audio_rules.dart';
import 'repo_files.dart';

/// A WAV of [seconds] of silence, with an optional [extra] chunk before the
/// data.
List<int> _wav(
  double seconds, {
  int rate = 44100,
  int channels = 1,
  int bits = 16,
  int format = 1,
  int riffSlack = 0,
  String? extra,
}) {
  final data = (seconds * rate).round() * channels * bits ~/ 8;
  final extraBytes = extra == null ? 0 : 8 + 4;
  final b = ByteData(44 + extraBytes + data);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + extraBytes + data + riffSlack, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, format, Endian.little);
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * channels * bits ~/ 8, Endian.little);
  b.setUint16(32, channels * bits ~/ 8, Endian.little);
  b.setUint16(34, bits, Endian.little);
  var at = 36;
  if (extra != null) {
    tag(at, extra);
    b.setUint32(at + 4, 4, Endian.little);
    tag(at + 8, 'INFO');
    at += 12;
  }
  tag(at, 'data');
  b.setUint32(at + 4, data, Endian.little);
  return b.buffer.asUint8List();
}

const _clipsSource = '''
const Map<Clip, ClipSpec> clips = {
  Clip.move: ClipSpec('assets/audio/move.wav', loop: false),
  Clip.music: ClipSpec('assets/audio/music.wav', loop: true),
};
''';

String _licences(Iterable<String> names) =>
    '# Audio\n\n## Licensed\n\n| File | Source | Licence |\n|---|---|---|\n'
    '${names.map((n) => '| `$n` | ElevenLabs | Creator plan |\n').join()}';

/// The pubspec's `flutter: assets:` entries, read structurally.
List<String> _pubspecAssets(String pubspec) {
  final flutter = (loadYaml(pubspec) as YamlMap)['flutter'] as YamlMap?;
  final assets = flutter?['assets'] as YamlList?;
  return [for (final a in assets ?? const []) '$a'];
}

void main() {
  group('the rules', () {
    final declared = declaredClips(_clipsSource);
    final clip = _wav(.1);
    final loop = _wav(30);
    Map<String, List<int>> files() => {
      'move.wav': clip,
      'music.wav': loop,
      'LICENSES.md': const [],
      'PROMPTS.md': const [],
    };
    List<Offender> check(Map<String, List<int>> f, String licences) =>
        audioOffenders(f, licences, declared);

    test('the clip list is read from clips.dart', () {
      expect(declared.map((c) => c.name), ['move.wav', 'music.wav']);
      expect(declared.last.loop, isTrue);
      expect(declared.first.loop, isFalse);
      expect(declaredClips('nothing here'), isEmpty);
      expect(
        check(
          files(),
          _licences(['move.wav', 'music.wav']),
        ).where((o) => o.path == 'clips.dart'),
        isEmpty,
      );
      expect(
        audioOffenders(
          const {'LICENSES.md': [], 'PROMPTS.md': []},
          _licences([]),
          const [],
        ).single,
        (path: 'clips.dart', message: 'declares no clips'),
        reason: 'an empty clip list must not pass as "nothing to check"',
      );
    });

    test(
      'two recorded clips pass; a stray file, a missing clip, a missing row, '
      'an absent licensed file and a missing record fail, named',
      () {
        expect(check(files(), _licences(['move.wav', 'music.wav'])), isEmpty);
        expect(
          check({
            ...files(),
            'stray.wav': clip,
          }, _licences(['move.wav', 'music.wav'])).single.path,
          'stray.wav',
        );
        final missing = files()..remove('move.wav');
        expect(check(missing, _licences(['music.wav'])).single, (
          path: 'move.wav',
          message: 'missing',
        ));
        expect(
          check(files(), _licences(['music.wav'])).single.message,
          contains('Licensed'),
        );
        expect(
          check(
            files(),
            _licences(['move.wav', 'music.wav', 'absent.wav']),
          ).single,
          (path: 'absent.wav', message: 'licensed but absent'),
        );
        expect(
          check(
            files()..remove('PROMPTS.md'),
            _licences(['move.wav', 'music.wav']),
          ).single.path,
          'PROMPTS.md',
        );
      },
    );

    test(
      'a row needs a source and a licence, and only the Licensed table counts',
      () {
        const partial =
            '## Licensed\n\n| File | Source | Licence |\n|---|---|---|\n'
            '| `move.wav` | ElevenLabs |  |\n';
        expect(licensedClips(partial), isEmpty);
        const elsewhere =
            '## Other\n\n| File | Source | Licence |\n|---|---|---|\n'
            '| `move.wav` | a | b |\n\n## Licensed\n\nnone\n';
        expect(licensedClips(elsewhere), isEmpty);
        expect(licensedClips(_licences(['move.wav'])), {'move.wav'});
      },
    );

    test('the format: PCM 16-bit 44.1 kHz mono, agreeing sizes, non-empty, within limits', () {
      expect(
        wavProblems(_wav(.1, rate: 48000), loop: false).single,
        contains('48000'),
      );
      expect(
        wavProblems(_wav(.1, channels: 2), loop: false).single,
        contains('mono'),
      );
      expect(
        wavProblems(_wav(.1, bits: 8), loop: false).single,
        contains('16-bit'),
      );
      expect(
        wavProblems(_wav(.1, format: 3), loop: false).single,
        contains('PCM'),
      );
      expect(
        wavProblems(_wav(.1, format: 0xFFFE), loop: false).single,
        contains('not PCM'),
        reason: 'WAVE_FORMAT_EXTENSIBLE is refused',
      );
      expect(
        wavProblems(_wav(.1, extra: 'LIST'), loop: false),
        isEmpty,
        reason: 'a LIST chunk before the data is stepped over',
      );
      expect(wavProblems(_wav(.1, extra: 'fact'), loop: false), isEmpty);
      expect(wavProblems([1, 2, 3], loop: false).single, contains('RIFF'));
      expect(wavProblems(_wav(0), loop: false).single, contains('empty'));
      expect(
        wavProblems(_wav(.1, riffSlack: 4), loop: false).single,
        contains('RIFF size'),
      );
      expect(
        wavProblems(_wav(2), loop: false),
        isEmpty,
        reason: '2.000 s is allowed',
      );
      expect(wavProblems(_wav(2.1), loop: false).single, contains('over 2 s'));
      expect(
        wavProblems(_wav(3, channels: 2), loop: false),
        contains(contains('over ${250 * 1024}')),
      );
      expect(wavProblems(_wav(30), loop: true), isEmpty);
      expect(wavProblems(_wav(28), loop: true).single, contains('under 29 s'));
      expect(wavProblems(_wav(32), loop: true).single, contains('over 31 s'));
    });

    test('the pubspec bundles each clip, never the directory', () {
      const ok = [
        'assets/fonts/outfit/OFL.txt',
        'assets/audio/move.wav',
        'assets/audio/music.wav',
      ];
      expect(pubspecAudioOffenders(ok, declared), isEmpty);
      expect(
        pubspecAudioOffenders(
          ok.where((a) => a != 'assets/audio/move.wav'),
          declared,
        ).single,
        contains('move.wav'),
      );
      expect(pubspecAudioOffenders(['assets/audio/'], declared), hasLength(3));
      expect(
        _pubspecAssets(
          'flutter:\n  # a comment\n  assets:\n    - a.wav\n\n    - b.wav\n',
        ),
        ['a.wav', 'b.wav'],
      );
    });
  });

  group('the repository', () {
    final declared = declaredClips(readFile('lib/feedback/clips.dart'));

    test('audio-assets: every clip the app plays is present, licensed and well-formed', () {
      final dir = Directory('${repoRoot.path}/assets/audio');
      final files = {
        for (final f in dir.listSync().whereType<File>())
          f.uri.pathSegments.last: f.readAsBytesSync(),
      };
      final offenders = audioOffenders(
        files,
        files.containsKey('LICENSES.md')
            ? readFile('assets/audio/LICENSES.md')
            : '',
        declared,
      );
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('audio-assets', [
          for (final o in offenders) 'assets/audio/${o.path}: ${o.message}',
        ]),
      );
    });

    test('audio-declared: pubspec.yaml bundles each clip one by one', () {
      final offenders = pubspecAudioOffenders(
        _pubspecAssets(readFile('pubspec.yaml')),
        declared,
      );
      expect(
        offenders,
        isEmpty,
        reason: describeOffenders('audio-declared', offenders),
      );
    });

    test('audio-readme: the README names the licence record and says the clips are not MIT', () {
      final paragraph = RegExp(r'\*\*Audio\.\*\*[^\n]*(\n[^\n]+)*')
          .firstMatch(readFile('README.md'))
          ?.group(0);
      expect(
        paragraph,
        isNotNull,
        reason: 'audio-readme: no **Audio.** paragraph in the licence section',
      );
      expect(
        paragraph,
        contains('assets/audio/LICENSES.md'),
        reason: 'audio-readme: the paragraph does not name assets/audio/LICENSES.md',
      );
      expect(
        paragraph,
        contains('not covered by the MIT'),
        reason:
            'audio-readme: the paragraph does not say the clips are not MIT',
      );
    });
  });
}
