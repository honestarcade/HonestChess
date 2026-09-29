import 'package:honest_chess/feedback/haptics.dart';

/// A [HapticsPort] that counts its ticks.
class FakeHaptics implements HapticsPort {
  int ticks = 0;

  @override
  Future<void> tick() async => ticks++;
}
