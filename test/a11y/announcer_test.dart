// FlutterAnnouncer speaks only to a screen reader (#102, #146): built for
// real and read at the accessibility channel, it sends nothing while
// accessibleNavigation is off, and the one polite announcement while it is
// on. The announcer scan guard only matches the gate's text; this checks
// what the gate does.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/a11y/announcer.dart';

/// Every message sent on the accessibility channel from here on.
List<Map<Object?, Object?>> _listen(WidgetTester tester) {
  final sent = <Map<Object?, Object?>>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (message) async {
      sent.add(message! as Map<Object?, Object?>);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return sent;
}

/// A context under [accessibleNavigation].
Future<BuildContext> _context(
  WidgetTester tester, {
  required bool accessibleNavigation,
}) async {
  late BuildContext context;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(accessibleNavigation: accessibleNavigation),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return context;
}

void main() {
  testWidgets('without a screen reader nothing reaches the channel', (
    tester,
  ) async {
    final sent = _listen(tester);
    final context = await _context(tester, accessibleNavigation: false);
    FlutterAnnouncer(() => context).announce('e4, pawn');
    await tester.pump();
    expect(
      sent,
      isEmpty,
      reason: 'announcer: silent with accessibleNavigation off',
    );
  });

  testWidgets('with a screen reader the announcement is sent, politely', (
    tester,
  ) async {
    final sent = _listen(tester);
    final context = await _context(tester, accessibleNavigation: true);
    FlutterAnnouncer(() => context).announce('e4, pawn');
    await tester.pump();
    expect(sent, hasLength(1), reason: 'announcer: one announcement');
    final data = sent.single['data']! as Map<Object?, Object?>;
    expect(sent.single['type'], 'announce');
    expect(data['message'], 'e4, pawn');
    // Flutter's event map carries an assertiveness only when it is not
    // polite.
    expect(
      data.containsKey('assertiveness'),
      isFalse,
      reason: 'announcer: polite, queued behind what is being spoken',
    );
  });

  testWidgets('no context, or an unmounted one, sends nothing', (tester) async {
    final sent = _listen(tester);
    FlutterAnnouncer(() => null).announce('e4, pawn');
    final context = await _context(tester, accessibleNavigation: true);
    await tester.pumpWidget(const SizedBox());
    FlutterAnnouncer(() => context).announce('e4, pawn');
    await tester.pump();
    expect(sent, isEmpty, reason: 'announcer: nothing to speak from');
  });
}
