import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart'
    show substrateFromDecodedPage;
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/data/step_calibration.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/step_divisor_card.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Walk/run activity_class step filter', () {
    test('credits only activity_class 1 (walk) and 2 (run) when classes exist',
        () {
      const t0 = 1791763200;
      final frames = <Map<String, dynamic>>[
        {'rec_ts': t0 + 0, 'step_count': 100, 'activity_class': 0, 'hr': 70},
        // +15 ticks while typing at desk (activity_class = 0) -> rejected!
        {'rec_ts': t0 + 1, 'step_count': 115, 'activity_class': 0, 'hr': 72},
        // +20 ticks walking (activity_class = 1) -> credited (only +20, NOT +35!)
        {'rec_ts': t0 + 2, 'step_count': 135, 'activity_class': 1, 'hr': 95},
        // +30 ticks running (activity_class = 2) -> credited
        {'rec_ts': t0 + 3, 'step_count': 165, 'activity_class': 2, 'hr': 142},
        // +8 ticks other/fidget (activity_class = 3) -> rejected
        {'rec_ts': t0 + 4, 'step_count': 173, 'activity_class': 3, 'hr': 80},
      ];
      final sub = substrateFromDecodedPage(frames, const []);
      expect(sub.activityClass, [0, 0, 1, 2, 3]);

      final deltas = counterDeltasFromSubstrate(
        sub,
        cumulativeCounterModulus: 65536,
      );
      expect(deltas!.total, 50);

      final spans = hardwareStepSpansFromCounter(
        sub,
        cumulativeCounterModulus: 65536,
      );
      expect(spans!.fold<int>(0, (a, s) => a + s.steps), 50);
    });

    test('substrates with no activity_class (-1) keep all valid deltas', () {
      const t0 = 1791763200;
      final frames = <Map<String, dynamic>>[
        {'rec_ts': t0 + 0, 'step_count': 100, 'hr': 70},
        {'rec_ts': t0 + 1, 'step_count': 115, 'hr': 72},
        {'rec_ts': t0 + 2, 'step_count': 135, 'hr': 95},
      ];
      final sub = substrateFromDecodedPage(frames, const []);
      expect(
        hardwareStepsFromCounter(sub, cumulativeCounterModulus: 65536),
        35,
      );
    });

    test('matches Oct 12 real WHOOP 5.0 oracle (25,179 walk/run ticks) when local fixture present',
        () async {
      final fixture = File('output/openstrap.db');
      if (!fixture.existsSync()) return;

      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        fixture.absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      addTearDown(() => db.close());

      final startSec = DateTime(2026, 10, 12).millisecondsSinceEpoch ~/ 1000;
      final endSec = DateTime(2026, 10, 13).millisecondsSinceEpoch ~/ 1000;
      final rows = await db.rawQuery(
        'SELECT rec_ts, hr, step_count, activity_class, device_family '
        'FROM decoded_onehz WHERE rec_ts >= ? AND rec_ts < ? '
        'ORDER BY rec_ts ASC',
        [startSec, endSec],
      );
      final sub = substrateFromDecodedPage(rows, const []);
      final total = hardwareStepsFromCounter(
        sub,
        cumulativeCounterModulus: 65536,
      );
      expect(total, 25179);
    });
  });

  group('User-configurable step divisor (default 1.0, zero hardcoding)', () {
    test('defaults to 1.0, clamps to [0.5, 30.0], and divides cleanly', () {
      expect(kDefaultStepDivisor, 1.0);
      expect(clampStepDivisor(null), 1.0);
      expect(clampStepDivisor(0.1), 0.5);
      expect(clampStepDivisor(45.0), 30.0);
      expect(clampStepDivisor(2.5), 2.5);

      expect(applyStepCalibration(25179, null), 25179);
      expect(applyStepCalibration(25179, null, userDivisor: 1.0), 25179);
      expect(applyStepCalibration(25179, null, userDivisor: 2.5), 10072);
    });

    testWidgets('StepDivisorCard renders on MetricDetail(steps), saves, and resets',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      await Prefs.reload();

      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final todayTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: MetricDetail(
            'steps',
            data: MetricData(
              series: [(t: todayTs, v: 25179)],
              daysAvailable: 6,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StepDivisorCard), findsOneWidget);
      expect(find.textContaining('1.0'), findsWidgets);

      var changedDivisor = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: StepDivisorCard(
              onChanged: (d) => changedDivisor = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '2.5');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(Prefs.getDouble(Prefs.stepDivisor, 1.0), closeTo(2.5, 1e-6));
      expect(changedDivisor, closeTo(2.5, 1e-6));

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(Prefs.getDouble(Prefs.stepDivisor, 1.0), closeTo(1.0, 1e-6));
      expect(changedDivisor, closeTo(1.0, 1e-6));
    });
  });
}
