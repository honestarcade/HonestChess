import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';

// The launcher-icon guard reads this literal here; Palette.navy is the same
// colour for everything else.
const _navy = Color(0xFF05285F);

/// Starts the app on a game against the computer. [strength] and [seed]
/// replace the first game's step and seed, for the device test only.
void main({Strength? strength, int? seed}) {
  registerFontLicences();
  runApp(
    HonestChessApp(
      firstGame: strength == null
          ? vsComputerDefault
          : (
              mode: GameKind.vsComputer,
              strength: strength,
              colour: vsComputerDefault.colour,
              timeControl: vsComputerDefault.timeControl,
              rotate: false,
            ),
      seed: seed,
    ),
  );
}

/// The bundled fonts' OFL texts (assets/fonts/SOURCE.md), each shown on the
/// licence page under the family it covers.
const fontLicences = {
  'Outfit': 'assets/fonts/outfit/OFL.txt',
  'IBM Plex Mono': 'assets/fonts/plexmono/OFL.txt',
  'Noto Sans Symbols 2': 'assets/fonts/pieces/OFL.txt',
};

void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: family, value: path) in fontLicences.entries) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(path));
    }
  });
}

/// The app root. It holds the board options in memory with the design's
/// defaults until M4's Settings saves them, and opens on [firstGame].
class HonestChessApp extends StatefulWidget {
  const HonestChessApp({
    super.key,
    this.computerFactory = ComputerPlayerOpponent.new,
    this.firstGame = vsComputerDefault,
    this.seed,
  });

  /// Builds the computer for each game against it; tests pass a fake.
  final ComputerFactory computerFactory;

  final GameSetup firstGame;

  /// The first game's computer seed; fresh when null.
  final int? seed;

  @override
  State<HonestChessApp> createState() => HonestChessAppState();
}

class HonestChessAppState extends State<HonestChessApp> {
  BoardOptions boardOptions = const BoardOptions();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Honest Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _navy,
        fontFamily: Fonts.outfit,
      ),
      home: GameScreen(
        options: boardOptions,
        setup: widget.firstGame,
        seed: widget.seed,
        computerFactory: widget.computerFactory,
      ),
    );
  }
}
