// The setup mappings (#85): each time choice and the remembered choices
// turn into exactly the game #76's GameSetup describes.
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/defaults.dart';

void main() {
  test('each time choice maps to its control; only Custom reads the pair', () {
    expect(TimeChoice.untimed.toTimeControl(15, 10), const Untimed());
    expect(TimeChoice.blitz.toTimeControl(15, 10), Timed.blitz);
    expect(TimeChoice.rapid.toTimeControl(15, 10), Timed.rapid);
    expect(TimeChoice.classical.toTimeControl(15, 10), Timed.classical);
    expect(TimeChoice.custom.toTimeControl(15, 10), Timed(15, 10));
    for (final choice in TimeChoice.values) {
      expect(
        TimeChoice.of(choice.toTimeControl(15, 10)),
        choice,
        reason: 'defaults: ${choice.name} reads back as itself',
      );
    }
  });

  test('computerSetup carries the step, the given colour and the time', () {
    final choices = SetupChoices.initial.copyWith(
      computer: const ComputerChoices(
        step: Strength.strong,
        colour: ColourChoice.random,
        time: TimeChoice.custom,
      ),
      custom: const CustomTime(minutes: 15, increment: 10),
    );
    final setup = choices.computerSetup(Colour.black);
    expect(setup.mode, GameKind.vsComputer);
    expect(setup.strength, Strength.strong);
    expect(setup.colour, Colour.black);
    expect(setup.timeControl, Timed(15, 10));
    expect(setup.rotate, isFalse);
  });

  test('twoPlayerSetup carries the two-player time, not the computer\'s', () {
    final choices = SetupChoices.initial.copyWith(
      computer: SetupChoices.initial.computer.copyWith(time: TimeChoice.blitz),
      two: const TwoPlayerChoices(time: TimeChoice.classical),
    );
    final setup = choices.twoPlayerSetup();
    expect(setup.mode, GameKind.twoPlayers);
    expect(setup.strength, isNull);
    expect(setup.colour, isNull);
    expect(setup.timeControl, Timed.classical);
  });
}
