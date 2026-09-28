// The device-level smoke test (#38): the real app, launched on an Android
// device or emulator, opens on the Honest Chess placeholder. It proves the
// harness end to end so later milestones only add tests (M6, epic #10).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:honest_chess/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app launches on a device and shows the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(const HonestChessApp());
    await tester.pumpAndSettle();

    expect(find.text('HonestChess', findRichText: true), findsOneWidget);
    expect(find.text('BY HONEST ARCADE'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
