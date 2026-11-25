import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart' show ChartPoint;
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/screens/overnight_hrv_card.dart';
import 'package:openstrap_edge/ui2/screens/sleep_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  final onsetSec = DateTime(2026, 10, 13, 0, 0).millisecondsSinceEpoch ~/ 1000;

  List<ChartPoint> sampleTimeline() => [
        // 00:00..00:25 (6 buckets): 70, 80, 90, 92, 100, 110
        (t: onsetSec + 0 * 300, v: 70.0),
        (t: onsetSec + 1 * 300, v: 80.0),
        (t: onsetSec + 2 * 300, v: 90.0),
        (t: onsetSec + 3 * 300, v: 92.0),
        (t: onsetSec + 4 * 300, v: 100.0),
        (t: onsetSec + 5 * 300, v: 110.0),
        // 30-min gap (buckets 6..11 null)
        // 01:00..01:10 (3 buckets): 95, 105, 120
        (t: onsetSec + 12 * 300, v: 95.0),
        (t: onsetSec + 13 * 300, v: 105.0),
        (t: onsetSec + 14 * 300, v: 120.0),
      ];

  group('computeOvernightHrvStats', () {
    test('preserves unmeasured 5-min buckets as null and computes exact stats',
        () {
      final stats = computeOvernightHrvStats(
        OvernightHrvData(
          timeline: sampleTimeline(),
          rmssdMean: 91.0,
          sdnn: 84.0,
        ),
      );
      expect(stats.hasValues, isTrue);
      // 15 buckets (0..14 inclusive), buckets 6..11 null
      expect(stats.denseSeries.length, 15);
      for (var i = 6; i <= 11; i++) {
        expect(stats.denseSeries[i], isNull, reason: 'bucket $i must stay null');
      }
      // Sorted values: [70, 80, 90, 92, 95, 100, 105, 110, 120] -> min=70, median=95, max=120
      expect(stats.minMs, closeTo(70.0, 1e-6));
      expect(stats.medianMs, closeTo(95.0, 1e-6));
      expect(stats.meanMs, closeTo(91.0, 1e-6));
      expect(stats.maxMs, closeTo(120.0, 1e-6));
      expect(stats.sdnnMs, closeTo(84.0, 1e-6));
    });
  });

  group('Main-screen OvernightHrvCard promotion', () {
    testWidgets('MetricDetail(hrv) renders OvernightHrvCard with Min/Median/Mean/Max/SDNN',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final todayTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final data = MetricData(
        series: [(t: todayTs, v: 91.0)],
        daysAvailable: 6,
        overnightHrv: OvernightHrvData(
          timeline: sampleTimeline(),
          rmssdMean: 91.0,
          sdnn: 84.0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: MetricDetail('hrv', data: data),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OvernightHrvCard), findsOneWidget);
      expect(find.text('Min'), findsOneWidget);
      expect(find.text('Median'), findsOneWidget);
      expect(find.text('Mean'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('SDNN'), findsOneWidget);
      expect(find.text('70 ms'), findsOneWidget);
      expect(find.text('95 ms'), findsOneWidget);
      expect(find.text('120 ms'), findsOneWidget);
      expect(find.text('84 ms'), findsOneWidget);
    });

    testWidgets('SleepDetail renders OvernightHrvCard with stats and zero bare dashes',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final sleepData = SleepData(
        day: '2026-10-13',
        night: {
          'duration_min': 441,
          'in_bed_min': 495,
          'efficiency': 0.891,
          'onset_ts': onsetSec,
          'wake_ts': onsetSec + 14 * 300,
          'stages': [
            {'start': onsetSec, 'end': onsetSec + 14 * 300, 'stage': 'light'},
          ],
          'stage_min': {'light': 300, 'deep': 81, 'rem': 60, 'wake': 54},
        },
        overnightHrv: OvernightHrvData(
          timeline: sampleTimeline(),
          rmssdMean: 91.0,
          sdnn: null, // absent SDNN must omit tile, never print bare '—'
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: SleepDetail(data: sleepData),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OvernightHrvCard), findsOneWidget);
      expect(find.text('Min'), findsOneWidget);
      expect(find.text('Median'), findsOneWidget);
      expect(find.text('Mean'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('SDNN'), findsNothing);
      final bareDashes = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').trim() == '—');
      expect(bareDashes, isEmpty);
    });
  });
}
