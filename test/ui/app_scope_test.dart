import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/main.dart';
import 'package:honest_chess/platform/platform_channel.dart';
import 'package:honest_chess/ui/app_scope.dart';

import '../support/app_harness.dart';
import 'game/fake_computer.dart';

/// Records the scope it sees in initState, where no dependency may be made.
class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  late final AppScope scope;

  @override
  void initState() {
    super.initState();
    scope = AppScope.of(context);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('the harness puts a memory store and a fake in the scope', (
    tester,
  ) async {
    final harness = await pumpUnderScope(tester, const _Probe());
    final probe = tester.state<_ProbeState>(find.byType(_Probe));
    expect(probe.scope.store, same(harness.store));
    expect(probe.scope.platform, same(harness.platform));
    expect(await harness.store.persistent, isFalse);
  });

  testWidgets('a dialog route sees the scope too', (tester) async {
    final harness = await pumpUnderScope(tester, const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    showDialog<void>(context: context, builder: (_) => const _Probe());
    await tester.pumpAndSettle();
    final probe = tester.state<_ProbeState>(find.byType(_Probe));
    expect(probe.scope.store, same(harness.store));
  });

  testWidgets('no scope is a FlutterError naming AppScope', (tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(
      () => AppScope.of(tester.element(find.byType(SizedBox))),
      throwsA(
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('AppScope'),
        ),
      ),
    );
  });

  testWidgets('the root builds its defaults once, the store through the '
      'injected platform', (tester) async {
    final platform = FakePlatformChannel();
    var asked = 0;
    platform.onFilesDir = () async {
      asked++;
      return null;
    };
    await tester.pumpWidget(
      HonestChessApp(computerFactory: FakeComputers().call, platform: platform),
    );
    final root = tester.state<HonestChessAppState>(find.byType(HonestChessApp));
    final store = root.store;
    expect(root.platform, same(platform));
    expect(
      await store.persistent,
      isFalse,
      reason: 'app: no files directory means an in-memory store',
    );
    expect(asked, 1, reason: 'app: the store asked the injected platform');
    await tester.pumpWidget(
      HonestChessApp(computerFactory: FakeComputers().call, platform: platform),
    );
    expect(root.store, same(store), reason: 'app: never rebuilt');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with nothing injected the root uses the production channel', (
    tester,
  ) async {
    await tester.pumpWidget(
      HonestChessApp(computerFactory: FakeComputers().call),
    );
    // No channel answers in a test, so launch waits out the read timeout.
    await tester.pump(const Duration(seconds: 5));
    final root = tester.state<HonestChessAppState>(find.byType(HonestChessApp));
    expect(root.platform, isA<MethodChannelPlatform>());
    expect(root.store, isA<AppStore>());
    await tester.pumpWidget(const SizedBox());
  });
}
