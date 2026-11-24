// Scan-mode pairing: the user's switch for hosts (LiveContainer) where the
// AccessorySetupKit picker appears but its approval does not attach to this app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/onboarding/pairing.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  group('askPairingAllowed', () {
    test('ASK is the default where the platform has it', () {
      expect(
          askPairingAllowed(platformSupported: true, scanModeChosen: false),
          isTrue);
    });

    test('the user\'s scan-mode choice wins over the platform', () {
      expect(askPairingAllowed(platformSupported: true, scanModeChosen: true),
          isFalse);
    });

    test('no platform support stays unsupported either way', () {
      expect(
          askPairingAllowed(platformSupported: false, scanModeChosen: false),
          isFalse);
      expect(
          askPairingAllowed(platformSupported: false, scanModeChosen: true),
          isFalse);
    });
  });

  group('pairing screen', () {
    Future<void> pump(WidgetTester t, Widget view) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
          MaterialApp(theme: buildTheme(Brightness.light), home: view));
    }

    testWidgets('the switch is hidden when no handler is supplied',
        (t) async {
      await pump(t, PairingView(phase: PairPhase.idle, onPair: () {}));
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('flipping the switch reports the new value', (t) async {
      bool? got;
      await pump(
        t,
        PairingView(
          phase: PairPhase.idle,
          onPair: () {},
          onScanModeChanged: (v) => got = v,
        ),
      );
      await t.tap(find.byType(Switch));
      expect(got, isTrue);
    });

    testWidgets('the switch is locked while a pairing is in flight',
        (t) async {
      bool? got;
      await pump(
        t,
        PairingView(
          phase: PairPhase.scanning,
          stage: 'opening session',
          onPair: () {},
          onScanModeChanged: (v) => got = v,
        ),
      );
      expect(find.text('opening session'), findsOneWidget);
      await t.tap(find.byType(Switch), warnIfMissed: false);
      expect(got, isNull);
    });

    testWidgets('a cancelled picker still shows the raw error and stage',
        (t) async {
      await pump(
        t,
        PairingView(
          phase: PairPhase.cancelled,
          stage: 'opening picker',
          detail: '[ASK picker] Exception: Pairing cancelled.',
          onPair: () {},
        ),
      );
      expect(find.text('opening picker'), findsOneWidget);
      expect(find.text('[ASK picker] Exception: Pairing cancelled.'),
          findsOneWidget);
    });

    testWidgets(
        'an ASK failure offers one-tap retry via direct Bluetooth scan',
        (t) async {
      var retriedDirect = false;
      await pump(
        t,
        PairingView(
          phase: PairPhase.failed,
          stage: 'opening picker',
          detail: 'PlatformException(ask_picker, host mismatch, null)',
          onPair: () {},
          onRetryWithScan: () => retriedDirect = true,
        ),
      );
      expect(
        find.text('PlatformException(ask_picker, host mismatch, null)'),
        findsOneWidget,
      );
      await t.tap(find.text('Pair with direct Bluetooth scan'));
      expect(retriedDirect, isTrue);
    });
  });
}
