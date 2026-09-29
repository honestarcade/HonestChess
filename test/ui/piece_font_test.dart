// The piece font covers every piece the board draws, and the fonts the
// tests load are the fonts the app registers.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';

import '../flutter_test_config.dart';

/// The code points a TrueType font's Unicode BMP cmap subtable (format 4)
/// maps to a real glyph.
Set<int> cmapCodePoints(Uint8List font) {
  final data = ByteData.sublistView(font);
  final numTables = data.getUint16(4);
  int? cmap;
  for (var i = 0; i < numTables; i++) {
    final record = 12 + 16 * i;
    if (String.fromCharCodes(font.sublist(record, record + 4)) == 'cmap') {
      cmap = data.getUint32(record + 8);
    }
  }
  if (cmap == null) throw const FormatException('no cmap table');
  final subtables = data.getUint16(cmap + 2);
  final codes = <int>{};
  for (var i = 0; i < subtables; i++) {
    final record = cmap + 4 + 8 * i;
    final platform = data.getUint16(record);
    final encoding = data.getUint16(record + 2);
    if (platform != 3 || encoding != 1) continue;
    final sub = cmap + data.getUint32(record + 4);
    if (data.getUint16(sub) != 4) continue;
    final segments = data.getUint16(sub + 6) ~/ 2;
    final ends = sub + 14;
    final starts = ends + 2 * segments + 2;
    final deltas = starts + 2 * segments;
    final rangeOffsets = deltas + 2 * segments;
    for (var s = 0; s < segments; s++) {
      final end = data.getUint16(ends + 2 * s);
      final start = data.getUint16(starts + 2 * s);
      final delta = data.getUint16(deltas + 2 * s);
      final rangeAt = rangeOffsets + 2 * s;
      final range = data.getUint16(rangeAt);
      for (var c = start; c <= end && c != 0xFFFF; c++) {
        var glyph = 0;
        if (range == 0) {
          glyph = (c + delta) & 0xFFFF;
        } else {
          final at = rangeAt + range + 2 * (c - start);
          final raw = data.getUint16(at);
          glyph = raw == 0 ? 0 : (raw + delta) & 0xFFFF;
        }
        if (glyph != 0) codes.add(c);
      }
    }
  }
  return codes;
}

void main() {
  final pieceFont = File('assets/fonts/pieces/HonestPieces.ttf')
      .readAsBytesSync();

  test('the piece font has a glyph for every symbol the board draws', () {
    final covered = cmapCodePoints(pieceFont);
    for (final style in [PieceStyle.classic, PieceStyle.outline]) {
      for (final piece in Piece.values) {
        final symbol = pieceGlyph(piece, style).runes.first;
        expect(
          covered,
          contains(symbol),
          reason:
              'piece-font: ${piece.name} in ${style.name} '
              '(U+${symbol.toRadixString(16).toUpperCase()}) is in the subset',
        );
      }
    }
  });

  test('the piece font holds nothing but the chess symbols', () {
    expect(cmapCodePoints(pieceFont), {
      for (var c = 0x2654; c <= 0x265F; c++) c,
    }, reason: 'piece-font: subset to U+2654–265F, as SOURCE.md says');
  });

  test('the cmap reader rejects a font it cannot read (the complement)', () {
    expect(
      () => cmapCodePoints(Uint8List(12)),
      throwsFormatException,
      reason: 'piece-font: a file with no cmap is not read as empty',
    );
  });

  test('tests load exactly the fonts pubspec.yaml registers', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    final fonts = (pubspec['flutter'] as Map)['fonts'] as List;
    final registered = {
      for (final family in fonts.cast<Map>())
        family['family'] as String: [
          for (final f in (family['fonts'] as List).cast<Map>())
            f['asset'] as String,
        ],
    };
    expect(
      registered,
      testFonts,
      reason: 'fonts: test/flutter_test_config.dart mirrors pubspec.yaml',
    );
    for (final files in registered.values) {
      for (final f in files) {
        expect(File(f).existsSync(), isTrue, reason: 'fonts: $f is bundled');
      }
    }
  });

  test('every font folder carries its OFL, and pubspec lists it', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    final assets = ((pubspec['flutter'] as Map)['assets'] as List)
        .cast<String>();
    for (final dir in Directory(
      'assets/fonts',
    ).listSync().whereType<Directory>()) {
      final ofl = '${dir.path}/OFL.txt';
      expect(File(ofl).existsSync(), isTrue, reason: 'fonts: $ofl exists');
      expect(
        File(ofl).readAsStringSync(),
        contains('SIL Open Font License'),
        reason: 'fonts: $ofl is the OFL',
      );
      expect(assets, contains(ofl), reason: 'fonts: $ofl ships as an asset');
    }
  });
}
