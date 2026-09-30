import 'package:flutter/services.dart';

import '../board/board_options.dart';
import 'contrast.dart';

/// The design's colour tokens (`ArtSource/design/Honest Chess.dc.html`).
/// Later screens add theirs here, so a colour has one name across the app.
/// A text colour the design drew below WCAG AA on a surface it sits on is
/// moved in its own hue just far enough to pass (#99): [shifts] records
/// each one's design value, and [textPairs] every text colour on every
/// surface, for test/guards/contrast_test.dart.
abstract final class Palette {
  /// The brand sheet's six swatches, exactly.
  static const List<Color> brandSheet = [
    teal,
    brandBlue,
    violet,
    screenBg,
    barRed,
    artInkLight,
  ];

  /// The screen background; `lib/main.dart` keeps its own `_navy` with the
  /// same value because the launcher-icon guard reads it there.
  static const screenBg = Color(0xFF05285F);

  /// The two ends of the screens' radial gradients, [screenBg] between.
  static const gradientInner = Color(0xFF0A3A80);
  static const gradientOuter = Color(0xFF031634);
  static const teal = Color(0xFF00D6B4);
  static const textDim = Color(0xFF8FB6E9);

  /// The splash's progress label.
  static const textLabel = Color(0xFF88AADD);

  /// Piece ink: white pieces are [pieceWhite] outlined in [pieceBlack];
  /// black pieces are [pieceBlack] edged in [pieceEdgeLight].
  static const pieceWhite = Color(0xFFFCFBF7);
  static const pieceBlack = Color(0xFF12181F);

  /// Black pieces' light edge: [pieceWhite] at 90%.
  static const pieceEdgeLight = Color(0xE6FCFBF7);

  /// The board frame: its drop shadow and its 1 px ring.
  static const boardShadow = Color(0x73000000); // rgba(0,0,0,.45)
  static const boardRing = Color(0x1FFFFFFF); // rgba(255,255,255,.12)

  /// Coordinate labels are the board theme's own, per square colour:
  /// `BoardTheme.labelOnLight` and `labelOnDark`.

  /// Square highlights (`renderVals`' `hl`, `ring` and `dot`): the selected
  /// square's tint and ring, a king in check, the last move's two squares,
  /// a capture target's ring and a quiet target's dot. The rings and the
  /// dot are these on a dark square and [markInkOnLight] on a light one.
  static const selectedTint = Color(0x6B00D6B4); // rgba(0,214,180,.42)
  static const selectedRing = teal;
  static const checkTint = Color(0x80E05A4E); // rgba(224,90,78,.5)
  static const lastMoveTint = Color(0x3300D6B4); // rgba(0,214,180,.2)
  static const captureRing = Color(0x9900D6B4); // rgba(0,214,180,.6)
  static const moveDot = Color(0x9E00D6B4); // rgba(0,214,180,.62)

  /// The shapes that carry each highlight without colour (#100): the last
  /// move's corner mark on a light and on a dark square; a king in check's
  /// badge is a white "!" on [danger].
  static const lastMoveMarkOnLight = markInkOnLight;
  static const lastMoveMarkOnDark = Color(0xB3FFFFFF); // white at .7

  /// Every ring, dot and corner mark on a light square (#144): [teal]
  /// darkened at its own hue to WCAG 1.4.11's 3:1 on each theme's light
  /// square under the tints those shapes sit on, so they show in
  /// greyscale. test/ui/board_shapes_test.dart re-derives it. Dark squares
  /// keep the design's inks above.
  static const markInkOnLight = Color(0xFF007E69);
  static const checkBadgeInk = _white;

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
  static const dangerText = Color(0xFFFF9486);

  /// [teal] as text on a teal tint over the play screen's gradient (the
  /// lit panel's line, the status chip once the game is over) and on About
  /// Honest Arcade's NO ADS chip: the brand teal moved lighter in its own
  /// hue for contrast (#99, [shifts]), the swatch itself kept.
  static const tealOnTint = Color(0xFF16DBB8);

  /// A player panel: lit for the side to move (fill and 1 px inset edge),
  /// dim otherwise; the king chip's two faces.
  static const panelLit = Color(0x2400D6B4); // rgba(0,214,180,.14)
  static const panelLitEdge = Color(0x6600D6B4); // rgba(0,214,180,.4)
  static const panelDim = Color(0x0DFFFFFF); // rgba(255,255,255,.05)
  static const kingChipLight = Color(0xFFF1EFE7);
  static const kingChipDark = pieceBlack;

  /// The side not to move: its clock is drawn at this opacity.
  static const double clockDimOpacity = 0.75;

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

  /// The menu's Continue: its meta line is [onTeal] at this opacity.
  static const double continueMetaOpacity = 0.71;

  /// The pause card's hint under Claim a draw: translucent white.
  static const hintInk = Color(0x8AFFFFFF);

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
  static const textMuted = Color(0xFF9ABCE3);
  static const textChoice = toolInk;
  static const kicker = Color(0xFF86AADC);

  /// The faintest text: Settings' version line.
  static const textFaint = Color(0xFF87AAD9);

  /// A filled teal button while pressed (the design's hover colour).
  static const tealPressed = Color(0xFF31E7CB);

  /// The pressed highlight of every Material ink button (the theme's
  /// `highlightColor`): Flutter's dark-theme grey, darkened at its own
  /// alpha until the text on each ink button reads while it is held.
  static const inkHighlight = Color(0x40565656);

  /// A promotion choice's ink while pressed: the design's teal wash,
  /// darkened at its own alpha until the piece's name reads on it.
  static const promoPressed = Color(0x3300947C);

  /// The two accents a choice is selected in ([Accent]): teal's fills (the
  /// soft one is [accentFill]) and the two-player screen's violet.
  static const tealFillSelected = panelLit;
  static const violet = Color(0xFF8448FC);
  static const violetText = Color(0xFFC5A3FF);
  static const violetFillSelected = Color(0x298448FC); // rgba(132,72,252,.16)

  /// The two-player screen's own: its Start game while pressed (the
  /// design's hover colour, darkened until white reads on it), and its
  /// header's kicker.
  static const violetPressed = Color(0xFF8757EC);
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
  static const skyBlue = Color(0xFF7DB9FF);
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
  static const danger = Color(0xFFCC493F);
  static const dangerPressed = Color(0xFFC94A3F);
  static const cancelEdge = Color(0x33FFFFFF); // rgba(255,255,255,.2)
  static const confirmShadow = Color(0x80000000); // rgba(0,0,0,.5)

  /// The menu's About Honest Arcade bar: its edge and its fill while
  /// pressed (its idle fill is [tealPanelFill]; the pressed one is the
  /// design's teal wash, darkened at its own alpha until the bar's text
  /// reads on it). Its damaged-data banner
  /// takes [resignFill] and [resignEdge], the same red washes.
  static const tealBarEdge = Color(0x5900D6B4); // rgba(0,214,180,.35)
  static const tealBarPressed = Color(0x2E009B82);

  /// The menu cards' mini-board art, fixed as drawn: the vs Computer
  /// card's 150° wash and squares ([onTeal] is the wash's far end,
  /// [textChoice] the light squares), the Two players card's, and the
  /// glyphs' two inks.
  static const computerArtBlue = Color(0xFF0F3E86);
  static const twoArtWashStart = Color(0xFF3B1F7A);
  static const twoArtWashEnd = Color(0xFF1B0E3C);
  static const twoArtLight = Color(0xFFE4DAFB);
  static const twoArtDark = Color(0xFF3B2076);
  static const artInkDark = Color(0xFF10161F);
  static const artInkLight = Color(0xFFF7F5EF);

  static const _white = Color(0xFFFFFFFF);

  /// Every colour moved from the design for contrast (#99, and #141's
  /// pressed fills), with the design's value: test/guards/contrast_test.dart
  /// re-derives each from [textPairs] (and the board pairs), so a hand edit
  /// that overshoots is caught.
  static final List<ColourShift> shifts = [
    ColourShift(
      'bone dark square',
      BoardTheme.bone.dark,
      Color(0xFF6B7788),
      ShiftWay.darker,
    ),
    for (final theme in BoardTheme.values) ...[
      ColourShift(
        '${theme.name} label, light square',
        theme.labelOnLight,
        Color(0x6B000000),
        ShiftWay.alpha,
      ),
      ColourShift(
        '${theme.name} label, dark square',
        theme.labelOnDark,
        Color(0x80FFFFFF),
        ShiftWay.alpha,
      ),
    ],
    const ColourShift(
      'dangerText',
      dangerText,
      Color(0xFFFF8C7E),
      ShiftWay.lighter,
    ),
    const ColourShift(
      'textFaint',
      textFaint,
      Color(0xFF4E739F),
      ShiftWay.lighter,
    ),
    const ColourShift(
      'textLabel',
      textLabel,
      Color(0xFF5C7FB0),
      ShiftWay.lighter,
    ),
    const ColourShift('kicker', kicker, Color(0xFF6E93C4), ShiftWay.lighter),
    const ColourShift('skyBlue', skyBlue, Color(0xFF6FB4FF), ShiftWay.lighter),
    const ColourShift('textDim', textDim, Color(0xFF7FA6D8), ShiftWay.lighter),
    const ColourShift(
      'textMuted',
      textMuted,
      Color(0xFF87A9D0),
      ShiftWay.lighter,
    ),
    const ColourShift(
      'violetText',
      violetText,
      Color(0xFFB48CFF),
      ShiftWay.lighter,
    ),
    const ColourShift('tealOnTint', tealOnTint, teal, ShiftWay.lighter),
    const ColourShift(
      'the draw hint',
      hintInk,
      Color(0x80FFFFFF),
      ShiftWay.alpha,
    ),
    const ColourShift('danger', danger, Color(0xFFE05A4E), ShiftWay.darker),
    const ColourShift(
      'violetPressed',
      violetPressed,
      Color(0xFF9A68FF),
      ShiftWay.darker,
    ),
    const ColourShift(
      'tealBarPressed',
      tealBarPressed,
      Color(0x2E00D6B4),
      ShiftWay.darker,
    ),
    const ColourShift(
      'promoPressed',
      promoPressed,
      Color(0x3300D6B4),
      ShiftWay.darker,
    ),
    const ColourShift(
      'inkHighlight',
      inkHighlight,
      Color(0x40CCCCCC),
      ShiftWay.darker,
    ),
  ];

  /// Every text colour on every surface it is drawn on. A surface's
  /// translucent fills are composited over the one below; on the gradient
  /// screens (the menu, About Honest Arcade, the splash, the play screen)
  /// the bottom is the gradient's brightest stop, [gradientInner], the
  /// worst case for light text. The coordinate labels follow, per theme,
  /// on each square colour plain and under each of [squareTints].
  static final List<TextPair> textPairs = [
    const TextPair(
      'wordmark Chess',
      teal,
      Surfaces.gradient,
      size: TextSize.large,
    ),
    const TextPair('teal on a promise chip', teal, Surfaces.promiseChip),
    const TextPair('teal on the menu bar', teal, Surfaces.gradientTealBar),
    const TextPair('teal on the promises panel', teal, Surfaces.promisePanel),
    const TextPair('teal on the first rule card', teal, Surfaces.tealRuleCard),
    const TextPair(
      'teal on a soft chosen option',
      teal,
      Surfaces.tealChosenSoft,
    ),
    const TextPair('teal on a chosen option', teal, Surfaces.tealChosen),
    const TextPair('teal on an option', teal, Surfaces.option),
    const TextPair(
      'teal stat value',
      teal,
      Surfaces.tealTile,
      size: TextSize.large,
    ),
    const TextPair('teal on a gradient card', teal, Surfaces.gradientCard),
    const TextPair(
      'teal on the support wash',
      teal,
      Surfaces.gradientSupportTeal,
    ),
    const TextPair(
      'teal on the support wash, violet end',
      teal,
      Surfaces.gradientSupportViolet,
    ),
    const TextPair('teal on a card', teal, Surfaces.overlayCard),
    const TextPair('teal on the New tool', teal, Surfaces.gradientAccent),
    const TextPair('teal on the lit panel', tealOnTint, Surfaces.gradientLit),
    const TextPair(
      'teal on the finished status chip',
      tealOnTint,
      Surfaces.gradientStatusOver,
    ),
    const TextPair('ink on teal', onTeal, Surfaces.teal),
    TextPair(
      'Continue\'s meta',
      onTeal.withValues(alpha: continueMetaOpacity),
      Surfaces.teal,
    ),
    const TextPair('white on the gradient', _white, Surfaces.gradient),
    const TextPair('white on the screen', _white, Surfaces.screen),
    const TextPair('white on a menu button', _white, Surfaces.gradientOption),
    const TextPair('white on a gradient card', _white, Surfaces.gradientCard),
    const TextPair(
      'white on the support wash',
      _white,
      Surfaces.gradientSupportTeal,
    ),
    const TextPair(
      'white on the support wash, violet end',
      _white,
      Surfaces.gradientSupportViolet,
    ),
    const TextPair('white on a card', _white, Surfaces.card),
    const TextPair('white on an overlay card', _white, Surfaces.overlayCard),
    const TextPair(
      'white on an overlay choice',
      _white,
      Surfaces.overlayChoice,
    ),
    const TextPair('white on an overlay button', _white, Surfaces.overlayDim),
    const TextPair('white on violet', _white, Surfaces.violet),
    const TextPair('white on violet, pressed', _white, Surfaces.violetPressed),
    const TextPair('ink on teal, pressed', onTeal, Surfaces.tealPressed),
    TextPair(
      'Continue\'s meta, pressed',
      onTeal.withValues(alpha: continueMetaOpacity),
      Surfaces.tealPressed,
    ),
    const TextPair(
      'teal on the menu bar, pressed',
      teal,
      Surfaces.gradientTealBarPressed,
    ),
    const TextPair(
      'muted text on the menu bar, pressed',
      textMuted,
      Surfaces.gradientTealBarPressed,
    ),
    const TextPair(
      'body text on a promotion choice, pressed',
      textBody,
      Surfaces.overlayChoicePromoPressed,
    ),
    const TextPair(
      'tool ink on a tool, pressed',
      toolInk,
      Surfaces.gradientToolPressed,
    ),
    const TextPair(
      'teal on the New tool, pressed',
      teal,
      Surfaces.gradientAccentPressed,
    ),
    const TextPair('ink on teal, ink pressed', onTeal, Surfaces.tealInkPressed),
    const TextPair(
      'white on an overlay button, pressed',
      _white,
      Surfaces.overlayDimPressed,
    ),
    const TextPair(
      'red text on Resign, pressed',
      dangerText,
      Surfaces.overlayResignPressed,
    ),
    const TextPair(
      'white on the result bar, pressed',
      _white,
      Surfaces.overlayCardPressed,
    ),
    const TextPair(
      'teal on the result bar, pressed',
      teal,
      Surfaces.overlayCardPressed,
    ),
    const TextPair(
      'red text on the result bar, pressed',
      dangerText,
      Surfaces.overlayCardPressed,
    ),
    const TextPair('white on the reset red', _white, Surfaces.danger),
    const TextPair('the check badge', checkBadgeInk, Surfaces.danger),
    const TextPair(
      'white on the reset red, pressed',
      _white,
      Surfaces.dangerPressed,
    ),
    const TextPair('faint text', textFaint, Surfaces.screen),
    const TextPair('faint text on the gradient', textFaint, Surfaces.gradient),
    const TextPair('splash label', textLabel, Surfaces.gradient),
    const TextPair('kicker', kicker, Surfaces.screen),
    const TextPair('kicker on the gradient', kicker, Surfaces.gradient),
    const TextPair('kicker on a card', kicker, Surfaces.card),
    const TextPair('kicker on a note', kicker, Surfaces.optionBare),
    const TextPair('violet kicker', kickerViolet, Surfaces.screen),
    const TextPair('sky blue on its chip', skyBlue, Surfaces.gradientBlueChip),
    const TextPair(
      'sky blue on a gradient card',
      skyBlue,
      Surfaces.gradientCard,
    ),
    const TextPair('dim text on the gradient', textDim, Surfaces.gradient),
    const TextPair('dim text', textDim, Surfaces.screen),
    const TextPair('dim text on a card', textDim, Surfaces.card),
    const TextPair(
      'dim text on a gradient card',
      textDim,
      Surfaces.gradientCard,
    ),
    const TextPair('dim text on a teal tile', textDim, Surfaces.tealTile),
    const TextPair(
      'dim text on an overlay card',
      textDim,
      Surfaces.overlayCard,
    ),
    const TextPair(
      'dim text on an overlay choice',
      textDim,
      Surfaces.overlayChoice,
    ),
    TextPair(
      'the waiting side\'s clock',
      textDim.withValues(alpha: clockDimOpacity),
      Surfaces.gradientCard,
      size: TextSize.large,
    ),
    const TextPair(
      'muted text on the menu bar',
      textMuted,
      Surfaces.gradientTealBar,
    ),
    const TextPair('muted text on a teal tile', textMuted, Surfaces.tealTile),
    const TextPair(
      'muted text on a chosen option',
      textMuted,
      Surfaces.tealChosen,
    ),
    const TextPair('muted text on an option', textMuted, Surfaces.option),
    const TextPair('muted text on a note', textMuted, Surfaces.optionBare),
    const TextPair('muted text on a card', textMuted, Surfaces.card),
    const TextPair(
      'body text on the status chip',
      textBody,
      Surfaces.gradientStatus,
    ),
    const TextPair(
      'body text on a card link',
      textBody,
      Surfaces.overlayOption,
    ),
    const TextPair(
      'body text on a gradient card',
      textBody,
      Surfaces.gradientCard,
    ),
    const TextPair('body text on a card', textBody, Surfaces.card),
    const TextPair('body text', textBody, Surfaces.screen),
    const TextPair(
      'body text on an overlay choice',
      textBody,
      Surfaces.overlayChoice,
    ),
    const TextPair(
      'violet on its chip',
      violetText,
      Surfaces.gradientVioletChip,
    ),
    const TextPair(
      'violet on a chosen option',
      violetText,
      Surfaces.violetChosen,
    ),
    const TextPair(
      'violet on a gradient card',
      violetText,
      Surfaces.gradientCard,
    ),
    const TextPair('lead text on a card', textLead, Surfaces.card),
    const TextPair(
      'lead text on an overlay card',
      textLead,
      Surfaces.overlayCard,
    ),
    const TextPair('lead text', textLead, Surfaces.screen),
    const TextPair(
      'bright text on the gradient',
      textBright,
      Surfaces.gradient,
    ),
    const TextPair(
      'bright text on the support wash',
      textBright,
      Surfaces.gradientSupportTeal,
    ),
    const TextPair(
      'bright text on the support wash, violet end',
      textBright,
      Surfaces.gradientSupportViolet,
    ),
    const TextPair(
      'pale text on a promise chip',
      textPale,
      Surfaces.promiseChip,
    ),
    const TextPair(
      'pale text on the first rule card',
      textPale,
      Surfaces.tealRuleCard,
    ),
    const TextPair('pale text on a card', textPale, Surfaces.card),
    const TextPair('choice text on an option', textChoice, Surfaces.option),
    const TextPair('choice text on a card', textChoice, Surfaces.card),
    const TextPair('tool ink on a tool', toolInk, Surfaces.gradientTool),
    const TextPair(
      'panel names on the lit panel',
      pieceWhite,
      Surfaces.gradientLit,
    ),
    const TextPair(
      'panel names on the dim panel',
      pieceWhite,
      Surfaces.gradientCard,
    ),
    const TextPair('the pause pill', pieceWhite, Surfaces.gradientPill),
    const TextPair(
      'red text on the banner',
      dangerText,
      Surfaces.gradientBanner,
    ),
    const TextPair(
      'red text on the reset button',
      dangerText,
      Surfaces.resetButton,
    ),
    const TextPair('red text on Resign', dangerText, Surfaces.overlayResign),
    const TextPair(
      'red text on the check chip',
      dangerText,
      Surfaces.gradientStatusCheck,
    ),
    const TextPair(
      'red text on an overlay card',
      dangerText,
      Surfaces.overlayCard,
    ),
    const TextPair('red text', dangerText, Surfaces.screen),
    const TextPair(
      'a low clock on the lit panel',
      dangerText,
      Surfaces.gradientLit,
      size: TextSize.large,
    ),
    TextPair(
      'a low clock on the waiting side',
      dangerText.withValues(alpha: clockDimOpacity),
      Surfaces.gradientCard,
      size: TextSize.large,
    ),
    const TextPair('the draw hint', hintInk, Surfaces.overlayCard),
    for (final theme in BoardTheme.values) ...[
      TextPair('${theme.name} label, light square', theme.labelOnLight, [
        theme.light,
      ]),
      TextPair('${theme.name} label, dark square', theme.labelOnDark, [
        theme.dark,
      ]),
      for (final (tintName, tint) in squareTints)
        for (final (squareName, onLight, square) in [
          ('light', true, theme.light),
          ('dark', false, theme.dark),
        ])
          TextPair(
            '${theme.name} label, $squareName square, $tintName tint',
            theme.labelInk(onLight: onLight, tint: tint),
            [square, tint],
          ),
    ],
  ];

  /// The tints a highlighted square lays under its coordinates, by name.
  static const List<(String, Color)> squareTints = [
    ('selected', selectedTint),
    ('last move', lastMoveTint),
    ('check', checkTint),
  ];
}

/// Which way a colour was moved to reach its contrast.
enum ShiftWay { lighter, darker, alpha }

/// A colour [value] moved from the design's [design] for contrast (#99).
final class ColourShift {
  const ColourShift(this.name, this.value, this.design, this.way);

  final String name;
  final Color value;
  final Color design;
  final ShiftWay way;
}

/// The surfaces text sits on, as stacks of fills from the opaque bottom up
/// (see [TextPair]).
abstract final class Surfaces {
  static const screen = [Palette.screenBg];
  static const card = [Palette.screenBg, Palette.cardFill];
  static const option = [
    Palette.screenBg,
    Palette.cardFill,
    Palette.optionFill,
  ];

  /// A note straight on the screen in an option's fill.
  static const optionBare = [Palette.screenBg, Palette.optionFill];
  static const tealChosen = [
    Palette.screenBg,
    Palette.cardFill,
    Palette.tealFillSelected,
  ];
  static const tealChosenSoft = [
    Palette.screenBg,
    Palette.cardFill,
    Palette.accentFill,
  ];
  static const violetChosen = [
    Palette.screenBg,
    Palette.cardFill,
    Palette.violetFillSelected,
  ];

  /// Statistics' highlighted card.
  static const tealTile = [Palette.screenBg, Palette.accentFill];
  static const tealRuleCard = [Palette.screenBg, Palette.tealTint];
  static const promisePanel = [Palette.screenBg, Palette.tealPanelFill];
  static const promiseChip = [
    Palette.screenBg,
    Palette.tealPanelFill,
    Palette.statusFill,
  ];
  static const resetButton = [Palette.screenBg, Palette.resignFill];
  static const teal = [Palette.teal];
  static const violet = [Palette.violet];
  static const danger = [Palette.danger];
  static const dangerPressed = [Palette.dangerPressed];
  static const violetPressed = [Palette.violetPressed];
  static const tealPressed = [Palette.tealPressed];

  /// Held down: the fills of the pressed states, and the ink buttons with
  /// [Palette.inkHighlight] over their fill.
  static const tealInkPressed = [Palette.teal, Palette.inkHighlight];
  static const gradientTealBarPressed = [
    Palette.gradientInner,
    Palette.tealBarPressed,
  ];
  static const gradientToolPressed = [
    Palette.gradientInner,
    Palette.toolFill,
    Palette.inkHighlight,
  ];
  static const gradientAccentPressed = [
    Palette.gradientInner,
    Palette.accentFill,
    Palette.inkHighlight,
  ];
  static const overlayCardPressed = [Palette.cardSurface, Palette.inkHighlight];
  static const overlayDimPressed = [
    Palette.cardSurface,
    Palette.panelDim,
    Palette.inkHighlight,
  ];
  static const overlayResignPressed = [
    Palette.cardSurface,
    Palette.resignFill,
    Palette.inkHighlight,
  ];
  static const overlayChoicePromoPressed = [
    Palette.cardSurface,
    Palette.choiceFill,
    Palette.promoPressed,
  ];

  static const gradient = [Palette.gradientInner];
  static const gradientCard = [Palette.gradientInner, Palette.cardFill];
  static const gradientOption = [Palette.gradientInner, Palette.optionFill];
  static const gradientTealBar = [Palette.gradientInner, Palette.tealPanelFill];
  static const gradientLit = [Palette.gradientInner, Palette.panelLit];
  static const gradientPill = [Palette.gradientInner, Palette.pillFill];
  static const gradientTool = [Palette.gradientInner, Palette.toolFill];
  static const gradientStatus = [Palette.gradientInner, Palette.statusFill];
  static const gradientStatusOver = [
    Palette.gradientInner,
    Palette.statusOverFill,
  ];
  static const gradientStatusCheck = [
    Palette.gradientInner,
    Palette.statusCheckFill,
  ];
  static const gradientAccent = [Palette.gradientInner, Palette.accentFill];
  static const gradientBlueChip = [Palette.gradientInner, Palette.blueFillChip];
  static const gradientVioletChip = [
    Palette.gradientInner,
    Palette.violetFillSelected,
  ];
  static const gradientSupportTeal = [
    Palette.gradientInner,
    Palette.supportWashStart,
  ];
  static const gradientSupportViolet = [
    Palette.gradientInner,
    Palette.supportWashEnd,
  ];
  static const gradientBanner = [Palette.gradientInner, Palette.resignFill];

  /// The overlays' cards (the pause, promotion and reset cards, and the
  /// result card at its brighter stop) and what sits on them.
  static const overlayCard = [Palette.cardSurface];
  static const overlayChoice = [Palette.cardSurface, Palette.choiceFill];
  static const overlayOption = [Palette.cardSurface, Palette.optionFill];
  static const overlayDim = [Palette.cardSurface, Palette.panelDim];
  static const overlayResign = [Palette.cardSurface, Palette.resignFill];
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
