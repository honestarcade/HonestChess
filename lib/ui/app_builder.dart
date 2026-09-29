import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/motion.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// The largest system text size the screens follow; above it they stay
/// as they are at it, so the fixed layouts keep their room.
const double maxTextScale = 1.3;

/// The smallest: a system size below the design's never shrinks its text.
const double minTextScale = 1.0;

/// [system] held between [minTextScale] and [maxTextScale].
TextScaler clampTextScaler(TextScaler system) =>
    system.clamp(minScaleFactor: minTextScale, maxScaleFactor: maxTextScale);

/// The `MaterialApp.builder` of the app root and of the test harness, so
/// every screen, in the app and in its tests, sits under the same clamped
/// text size, [board]'s motion setting and the one system-bar style (screens
/// set none of their own).
TransitionBuilder appBuilder(ValueListenable<BoardOptions> board) =>
    (context, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(textScaler: clampTextScaler(media.textScaler)),
        child: SettingsMotion(
          board: board,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: appOverlayStyle,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      );
    };
