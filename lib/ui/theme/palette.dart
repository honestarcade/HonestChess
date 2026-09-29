import 'package:flutter/services.dart';

/// The design's colour tokens (`ArtSource/design/Honest Chess.dc.html`).
/// Later screens add theirs here, so a colour has one name across the app.
abstract final class Palette {
  /// The screen background; `lib/main.dart` keeps its own `_navy` with the
  /// same value because the launcher-icon guard reads it there.
  static const screenBg = Color(0xFF05285F);

  /// The two ends of the screens' radial gradients, [screenBg] between.
  static const gradientInner = Color(0xFF0A3A80);
  static const gradientOuter = Color(0xFF031634);
  static const teal = Color(0xFF00D6B4);
  static const textDim = Color(0xFF7FA6D8);

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

  /// Square highlights (`renderVals`' `hl`, `ring` and `dot`): the selected
  /// square's tint and ring, a king in check, the last move's two squares,
  /// a capture target's ring and a quiet target's dot.
  static const selectedTint = Color(0x6B00D6B4); // rgba(0,214,180,.42)
  static const selectedRing = teal;
  static const checkTint = Color(0x80E05A4E); // rgba(224,90,78,.5)
  static const lastMoveTint = Color(0x3300D6B4); // rgba(0,214,180,.2)
  static const captureRing = Color(0x9900D6B4); // rgba(0,214,180,.6)
  static const moveDot = Color(0x9E00D6B4); // rgba(0,214,180,.62)

  /// The overlays' scrim and card (the promotion sheet's, the pause
  /// card's): the card's fill, its 1 px inset edge and its drop shadow.
  static const scrim = Color(0xD1030E20); // rgba(3,14,32,.82)
  static const cardSurface = Color(0xFF0B3670);
  static const cardEdge = Color(0x1AFFFFFF); // rgba(255,255,255,.1)
  static const cardShadow = Color(0x8C000000); // rgba(0,0,0,.55)

  /// A choice button on a card: its fill, its edge and its label.
  static const choiceFill = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const choiceEdge = Color(0x29FFFFFF); // rgba(255,255,255,.16)
  static const textBody = Color(0xFF9FC3EE);

  /// The play screen's top bar: the pause pill's fill and edge, and the
  /// status chip's fill as the game goes on, has ended, or is in check.
  static const pillFill = choiceFill;
  static const pillEdge = Color(0x24FFFFFF); // rgba(255,255,255,.14)
  static const statusFill = Color(0x12FFFFFF); // rgba(255,255,255,.07)
  static const statusOverFill = Color(0x2900D6B4); // rgba(0,214,180,.16)
  static const statusCheckFill = Color(0x33E05A4E); // rgba(224,90,78,.2)

  /// Red text: a side in check on the status chip, a clock under 30 s.
  static const dangerText = Color(0xFFFF8C7E);

  /// A player panel: lit for the side to move (fill and 1 px inset edge),
  /// dim otherwise; the king chip's two faces.
  static const panelLit = Color(0x2400D6B4); // rgba(0,214,180,.14)
  static const panelLitEdge = Color(0x6600D6B4); // rgba(0,214,180,.4)
  static const panelDim = Color(0x0DFFFFFF); // rgba(255,255,255,.05)
  static const kingChipLight = Color(0xFFF1EFE7);
  static const kingChipDark = pieceBlack;

  /// The tool row under the board (`renderVals`' `T`): a neutral tool's
  /// fill, edge and ink, and the accented New tool's.
  static const toolFill = choiceFill;
  static const toolEdge = pillEdge;
  static const toolInk = Color(0xFFDCE9F8);
  static const accentFill = Color(0x1F00D6B4); // rgba(0,214,180,.12)
  static const accentEdge = panelLitEdge;
  static const accentInk = teal;

  /// The pause card's buttons: [onTeal], the ink of Resume and of every
  /// label on teal, the draw button's fill and edge, and Resign's red fill
  /// and edge (its ink is [dangerText]).
  static const onTeal = Color(0xFF04213F);
  static const drawFill = panelDim;
  static const drawEdge = Color(0x2EFFFFFF); // rgba(255,255,255,.18)
  static const resignFill = Color(0x1FE05A4E); // rgba(224,90,78,.12)
  static const resignEdge = checkTint;

  /// The result card (`isOver`): its darker scrim, the far stop of its
  /// 170° gradient from [cardSurface], its teal inset edge, its body text
  /// ([textLead], also How to play's gesture text), and a
  /// stat tile's fill. The View board button is the design's secondary
  /// outline: [panelDim] fill, [choiceEdge] edge.
  static const resultScrim = Color(0xD9030E20); // rgba(3,14,32,.85)
  static const resultCardEnd = Color(0xFF04213F);
  static const resultEdge = Color(0x4D00D6B4); // rgba(0,214,180,.3)
  static const textLead = Color(0xFFBBD2EC);
  static const statFill = choiceFill;

  /// The non-board screens (Settings, the setup screens): a section card's
  /// fill, a choice's idle fill, the soft and idle choice borders, the
  /// strong border of the header's back button, caption and idle-choice
  /// text, and the small upper-case kicker over a group.
  static const cardFill = panelDim;
  static const optionFill = Color(0x0AFFFFFF); // rgba(255,255,255,.04)
  static const borderSoft = boardRing;
  static const borderIdle = pillEdge;
  static const borderStrong = choiceEdge;
  static const textMuted = Color(0xFF87A9D0);
  static const textChoice = toolInk;
  static const kicker = Color(0xFF6E93C4);

  /// The faintest text: Settings' version line.
  static const textFaint = Color(0xFF4E739F);

  /// A filled teal button while pressed (the design's hover colour).
  static const tealPressed = Color(0xFF31E7CB);

  /// The two accents a choice is selected in ([Accent]): teal's fills (the
  /// soft one is [accentFill]) and the two-player screen's violet.
  static const tealFillSelected = panelLit;
  static const violet = Color(0xFF8448FC);
  static const violetText = Color(0xFFB48CFF);
  static const violetFillSelected = Color(0x298448FC); // rgba(132,72,252,.16)

  /// The two-player screen's own: its Start game while pressed (the
  /// design's hover colour), and its header's kicker.
  static const violetPressed = Color(0xFF9A68FF);
  static const kickerViolet = Color(0xFF9E7BFF);

  /// How to play's: a rule's body text, the first rule card's teal tint
  /// and its 1 px inset ring, and the square behind every other piece
  /// card's glyph (the rest take the board theme's light colour).
  static const textPale = Color(0xFFD3E6FF);
  static const tealTint = Color(0x1C00D6B4); // rgba(0,214,180,.11)
  static const tealRing = Color(0x5700D6B4); // rgba(0,214,180,.34)
  static const pieceCardSquare = kingChipLight;

  /// About Honest Arcade's: the first paragraph's and the Support card's
  /// text, the blue ticks and the NO TRACKING chip's text and fill, the
  /// text links' underline, and the Support card's border and the two ends
  /// of its 135° wash.
  static const textBright = Color(0xFFC6DAF0);
  static const skyBlue = Color(0xFF6FB4FF);
  static const blueFillChip = Color(0x290076F1); // rgba(0,118,241,.16)
  static const linkUnderline = Color(0x667FA6D8); // rgba(127,166,216,.4)
  static const supportBorder = Color(0x4700D6B4); // rgba(0,214,180,.28)
  static const supportWashStart = Color(0x2100D6B4); // rgba(0,214,180,.13)
  static const supportWashEnd = Color(0x218448FC); // rgba(132,72,252,.13)

  /// About the App's promises panel: its fill and its inset ring.
  static const tealPanelFill = Color(0x1A00D6B4); // rgba(0,214,180,.1)
  static const tealPanelRing = Color(0x5200D6B4); // rgba(0,214,180,.32)

  /// Statistics': the bars' blue and red (with [teal], [violet] and
  /// [skyBlue], by row), a bar's empty track, the reset red and its
  /// pressed shade, the Cancel button's edge, and the confirmation card's
  /// drop shadow. The Reset statistics button's fill and edge are
  /// [resignFill] and [resignEdge], the same red washes.
  static const brandBlue = Color(0xFF0076F1);
  static const barRed = Color(0xFFC6483D);
  static const barTrack = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  static const danger = Color(0xFFE05A4E);
  static const dangerPressed = Color(0xFFC94A3F);
  static const cancelEdge = Color(0x33FFFFFF); // rgba(255,255,255,.2)
  static const confirmShadow = Color(0x80000000); // rgba(0,0,0,.5)
}

/// The system bars on every route, set once at the app root: light icons
/// over a transparent status bar, and the navigation bar in [Palette.screenBg].
const appOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Palette.screenBg,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// The colour a chosen option, a pressed option and a switch's track are
/// drawn in: teal everywhere but the two-player screen, which is violet.
enum Accent {
  teal(
    main: Palette.teal,
    fillSelected: Palette.tealFillSelected,
    text: Palette.teal,
  ),
  violet(
    main: Palette.violet,
    fillSelected: Palette.violetFillSelected,
    text: Palette.violetText,
  );

  const Accent({
    required this.main,
    required this.fillSelected,
    required this.text,
  });

  /// The selected and pressed border, and a switch's track when on.
  final Color main;

  /// A selected setup choice's fill.
  final Color fillSelected;

  /// A selected choice's label and a stepper's value.
  final Color text;
}

/// The app's font families, as pubspec.yaml declares them.
abstract final class Fonts {
  static const outfit = 'Outfit';
  static const plexMono = 'PlexMono';

  /// Noto Sans Symbols 2, subset to the chess symbols.
  static const pieces = 'HonestPieces';
}
