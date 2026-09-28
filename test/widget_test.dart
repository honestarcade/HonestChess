import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/main.dart';

void main() {
  testWidgets('the placeholder is Honest Chess, not the counter', (
    tester,
  ) async {
    await tester.pumpWidget(const HonestChessApp());

    expect(
      find.text('HonestChess', findRichText: true),
      findsOneWidget,
      reason: 'placeholder: the wordmark reads "Honest" + "Chess" on one line',
    );
    expect(find.text('BY HONEST ARCADE'), findsOneWidget);
    expect(
      find.byIcon(Icons.add),
      findsNothing,
      reason: "placeholder: the template's counter is gone",
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF05285F));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.title, 'Honest Chess');
  });
}
