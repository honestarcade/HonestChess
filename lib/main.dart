import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/data/stats_listener.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/platform/platform_channel.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';

// The launcher-icon guard reads this literal here; Palette.screenBg is the
// same colour for everything else.
const _navy = Color(0xFF05285F);

/// Starts the app on the saved game, or a new game against the computer.
/// [strength] and [seed] replace the new game's step and seed, for the
/// device test only: either one skips the saved game, so the test never
/// lands on a paused leftover.
void main({Strength? strength, int? seed}) {
  registerFontLicences();
  runApp(
    HonestChessApp(
      resumeSaved: strength == null && seed == null,
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

/// The app's theme, shared by the root and test/support/app_harness.dart.
ThemeData appTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _navy,
  fontFamily: Fonts.outfit,
);

/// The app root. It owns the settings, the game controller and the saved
/// games; it reads the settings and the saved games before the first board
/// and opens on the saved game Continue would offer — paused — or, with
/// none, on a new [firstGame].
class HonestChessApp extends StatefulWidget {
  const HonestChessApp({
    super.key,
    this.computerFactory = ComputerPlayerOpponent.new,
    this.firstGame = vsComputerDefault,
    this.seed,
    this.store,
    this.platform,
    this.resumeSaved = true,
  });

  /// The device store; null builds the production one over [platform].
  final AppStore? store;

  /// The Android bridge; null builds the production channel.
  final PlatformChannel? platform;

  /// Builds the computer for each game against it; tests pass a fake.
  final ComputerFactory computerFactory;

  final GameSetup firstGame;

  /// The first game's computer seed; fresh when null.
  final int? seed;

  /// Whether launch opens on a saved game when there is one; false always
  /// starts [firstGame].
  final bool resumeSaved;

  @override
  State<HonestChessApp> createState() => HonestChessAppState();
}

class HonestChessAppState extends State<HonestChessApp> {
  /// The board options and setup choices; every change to the board options
  /// reaches the controller and the board at once.
  final settings = SettingsStore();

  /// Built once, never rebuilt: a test injecting only a platform gets a
  /// store resolved through it.
  late final PlatformChannel platform;
  late final AppStore store;
  late final GameController controller;
  late final GameSaves saves;
  late final StatsRecorder stats;
  late final StatsListener _statsListener;

  /// Leaving the app pauses the live game, whose pause is saved, and then
  /// waits for the store to write it.
  late final AppLifecycleListener _lifecycle;

  /// Whether the saved games have been read and a game is on the board.
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    platform = widget.platform ?? MethodChannelPlatform();
    store = widget.store ?? AppStore.onDevice(platform);
    controller = GameController.idle(
      computerFactory: widget.computerFactory,
      options: settings.board.value,
    );
    settings.board.addListener(_boardChanged);
    saves = GameSaves(store)..attach(controller.events);
    stats = StatsRecorder(store: store);
    // Before the launch load, so a finished game found there is counted.
    _statsListener = StatsListener(
      controller: controller,
      recorder: stats,
      saves: saves,
    );
    _lifecycle = AppLifecycleListener(onStateChange: _left);
    _launch();
  }

  void _boardChanged() => controller.options = settings.board.value;

  Future<void> _launch() async {
    stats.load().ignore();
    // Read before the first game, which takes its takeback rule from them.
    final settingsLoaded = settings.load(store);
    try {
      await saves.loadAll();
    } on Object catch (e) {
      // The app starts without the saved games rather than not at all.
      debugPrint('launch: the saved games could not be read: $e');
    }
    await settingsLoaded;
    if (!mounted) return;
    final offered = widget.resumeSaved ? saves.offered : null;
    final game = offered == null ? null : saves.load(offered.mode);
    if (game == null ||
        !controller.restore(game, recorded: saves.recorded(offered!.mode))) {
      await controller.newGame(widget.firstGame, seed: widget.seed);
      if (!mounted) return;
    }
    setState(() => _launched = true);
  }

  Future<void> _left(AppLifecycleState state) async {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.hidden) {
      return;
    }
    // A clock already at zero ends the game on time rather than being
    // saved at 0:00.
    controller.checkFlag();
    controller.autoPause();
    await saves.flush();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _statsListener.dispose();
    stats.dispose();
    saves.dispose();
    settings.board.removeListener(_boardChanged);
    settings.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A plain navy frame while the saved games load.
    if (!_launched) return const ColoredBox(color: _navy);
    return AppScope(
      store: store,
      platform: platform,
      controller: controller,
      saves: saves,
      stats: stats,
      settings: settings,
      child: MaterialApp(
        title: 'Honest Chess',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        home: ValueListenableBuilder<BoardOptions>(
          valueListenable: settings.board,
          builder: (context, options, _) => GameScreen(
            options: options,
            controller: controller,
            seed: widget.seed,
            computerFactory: widget.computerFactory,
          ),
        ),
      ),
    );
  }
}
