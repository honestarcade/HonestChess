// Runs before every test file in test/a11y/ in place of the root
// test/flutter_test_config.dart (flutter_test uses the nearest one only).
//
// The root config's bundled fonts, and motion off through the phone's own
// switch (`MediaQuery.disableAnimations`), so a screen is checked where it
// comes to rest rather than part-way through a slide or a card's rise.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../flutter_test_config.dart' as root;

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    root.testExecutable(() async {
      final binding = TestWidgetsFlutterBinding.instance;
      setUp(() {
        binding.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
      });
      tearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await testMain();
    });
