import 'package:flutter/painting.dart';

/// The design's colour tokens (`ArtSource/design/Honest Chess.dc.html`).
/// Later screens add theirs here, so a colour has one name across the app.
abstract final class Palette {
  /// The screen background; `lib/main.dart` keeps its own `_navy` with the
  /// same value because the launcher-icon guard reads it there.
  static const navy = Color(0xFF05285F);
  static const navyLight = Color(0xFF0A3A80);
  static const navyDeep = Color(0xFF031634);
  static const teal = Color(0xFF00D6B4);
  static const byline = Color(0xFF7FA6D8);

  /// Piece ink: white pieces are [pieceWhite] outlined in [pieceBlack];
  /// black pieces are [pieceBlack] with a faint light halo.
  static const pieceWhite = Color(0xFFFCFBF7);
  static const pieceBlack = Color(0xFF12181F);

  /// The board frame: its drop shadow and its 1 px ring.
  static const boardShadow = Color(0x73000000); // rgba(0,0,0,.45)
  static const boardRing = Color(0x1FFFFFFF); // rgba(255,255,255,.12)

  /// Coordinate labels, per the colour of the square they sit on.
  static const coordOnDark = Color(0x80FFFFFF); // rgba(255,255,255,.5)
  static const coordOnLight = Color(0x6B000000); // rgba(0,0,0,.42)
}

/// The app's font families, as pubspec.yaml declares them.
abstract final class Fonts {
  static const outfit = 'Outfit';
  static const plexMono = 'PlexMono';

  /// Noto Sans Symbols 2, subset to the chess symbols.
  static const pieces = 'HonestPieces';
}
