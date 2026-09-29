import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The four square colour pairs of the design's `THEMES`.
enum BoardTheme {
  navy(light: Color(0xFFDCE9F8), dark: Color(0xFF0F3E86)),
  teal(light: Color(0xFFD6F0EB), dark: Color(0xFF0B615A)),
  violet(light: Color(0xFFE4DAFB), dark: Color(0xFF3B2076)),
  bone(light: Color(0xFFF1EFE7), dark: Color(0xFF6B7788));

  const BoardTheme({required this.light, required this.dark});

  final Color light;
  final Color dark;

  /// The name Settings shows: NAVY, CLASSIC, FELT….
  String get label => name.toUpperCase();
}

/// The design's three piece styles (`GLYPH`).
enum PieceStyle {
  /// The filled chess symbols, for both colours.
  classic,

  /// The hollow chess symbols, for both colours.
  outline,

  /// Upper-case letters in the monospaced face, for both colours.
  flat;

  /// The name Settings shows: NAVY, CLASSIC, FELT….
  String get label => name.toUpperCase();
}

/// One band of a repeating stripe pattern: [width] design px of [colour].
final class StripeBand {
  const StripeBand(this.colour, this.width);

  final Color colour;
  final double width;
}

/// A CSS `repeating-linear-gradient` with hard stops: [bands] repeat along
/// the gradient line, which points [angleDegrees] clockwise from "up".
final class StripePattern {
  const StripePattern(this.angleDegrees, this.bands);

  final double angleDegrees;
  final List<StripeBand> bands;

  /// One repeat, in design px.
  double get period => bands.fold(0, (sum, b) => sum + b.width);
}

/// The design's three board surfaces (`TEX`), drawn over the squares.
enum BoardSurface {
  plain(null),

  /// `repeating-linear-gradient(45deg, rgba(255,255,255,.05) 0 1px,
  /// rgba(0,0,0,.03) 1px 4px)`.
  felt(
    StripePattern(45, [
      StripeBand(Color(0x0DFFFFFF), 1),
      StripeBand(Color(0x08000000), 3),
    ]),
  ),

  /// `repeating-linear-gradient(87deg, rgba(0,0,0,.09) 0 2px,
  /// rgba(255,255,255,.05) 2px 7px)`.
  wood(
    StripePattern(87, [
      StripeBand(Color(0x17000000), 2),
      StripeBand(Color(0x0DFFFFFF), 5),
    ]),
  );

  const BoardSurface(this.pattern);

  /// Null for [plain], which draws nothing over the squares.
  final StripePattern? pattern;

  /// The name Settings shows: NAVY, CLASSIC, FELT….
  String get label => name.toUpperCase();
}

/// How the board looks and behaves: the design's Settings rows that touch
/// the board, edited in Settings and kept by `SettingsStore`
/// (lib/data/settings_store.dart), which holds its codec so this class
/// stays free of persistence.
@immutable
final class BoardOptions {
  const BoardOptions({
    this.theme = BoardTheme.navy,
    this.pieceStyle = PieceStyle.classic,
    this.surface = BoardSurface.felt,
    this.legalMoveDots = true,
    this.lastMoveHighlight = true,
    this.takebackAllowed = true,
    this.autoQueen = false,
    this.rotateEachTurn = false,
    this.animations = true,
    this.sfx = true,
    this.music = false,
    this.flagCheck = true,
  });

  final BoardTheme theme;
  final PieceStyle pieceStyle;
  final BoardSurface surface;

  /// Mark every square the selected piece can reach.
  final bool legalMoveDots;

  /// Tint the two squares of the move just played.
  final bool lastMoveHighlight;

  /// New games allow takeback (the game fixes it at its start).
  final bool takebackAllowed;

  /// Skip the promotion sheet and take a queen.
  final bool autoQueen;

  /// Two-player only: turn the board to face whoever moves.
  final bool rotateEachTurn;

  /// Slide pieces to their square instead of jumping.
  final bool animations;

  /// Play a sound for each move and for the end of a game.
  final bool sfx;

  /// Play the quiet loop while a game is live on the board.
  final bool music;

  /// Redden the king's square whenever it is in check.
  final bool flagCheck;

  BoardOptions copyWith({
    BoardTheme? theme,
    PieceStyle? pieceStyle,
    BoardSurface? surface,
    bool? legalMoveDots,
    bool? lastMoveHighlight,
    bool? takebackAllowed,
    bool? autoQueen,
    bool? rotateEachTurn,
    bool? animations,
    bool? sfx,
    bool? music,
    bool? flagCheck,
  }) => BoardOptions(
    theme: theme ?? this.theme,
    pieceStyle: pieceStyle ?? this.pieceStyle,
    surface: surface ?? this.surface,
    legalMoveDots: legalMoveDots ?? this.legalMoveDots,
    lastMoveHighlight: lastMoveHighlight ?? this.lastMoveHighlight,
    takebackAllowed: takebackAllowed ?? this.takebackAllowed,
    autoQueen: autoQueen ?? this.autoQueen,
    rotateEachTurn: rotateEachTurn ?? this.rotateEachTurn,
    animations: animations ?? this.animations,
    sfx: sfx ?? this.sfx,
    music: music ?? this.music,
    flagCheck: flagCheck ?? this.flagCheck,
  );

  @override
  bool operator ==(Object other) =>
      other is BoardOptions &&
      other.theme == theme &&
      other.pieceStyle == pieceStyle &&
      other.surface == surface &&
      other.legalMoveDots == legalMoveDots &&
      other.lastMoveHighlight == lastMoveHighlight &&
      other.takebackAllowed == takebackAllowed &&
      other.autoQueen == autoQueen &&
      other.rotateEachTurn == rotateEachTurn &&
      other.animations == animations &&
      other.sfx == sfx &&
      other.music == music &&
      other.flagCheck == flagCheck;

  @override
  int get hashCode => Object.hash(
    theme,
    pieceStyle,
    surface,
    legalMoveDots,
    lastMoveHighlight,
    takebackAllowed,
    autoQueen,
    rotateEachTurn,
    animations,
    sfx,
    music,
    flagCheck,
  );
}
