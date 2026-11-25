import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:openstrap_edge/ui2/screens/biological_age_card.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  group('VitalityEngine & Pace of Aging (NOOP parity)', () {
    test('average 40yo peer lands at Body Age 40.0, Vitality 50.0, Pace 1.00x',
        () {
      final res = VitalityEngine.compute(
        VitalityInputs(
          chronoAge: 40.0,
          restingHR: 65.0,
          vo2max: 45.0,
          expectedVO2max: 45.0,
          sleepHours: 7.5,
          sleepConsistency: 0.75,
          rmssd: VitalityEngine.rmssdNorm(40.0),
          rmssdNorm: VitalityEngine.rmssdNorm(40.0),
          steps: 7000.0,
        ),
      );
      expect(res, isNotNull);
      expect(res!.bodyAge, closeTo(40.0, 1e-6));
      expect(res.vitality, closeTo(50.0, 1e-6));
      expect(res.paceOfAging, closeTo(1.0, 1e-6));
    });

    test('fitter 40yo reads younger with Vitality > 50 and Pace < 1.0x', () {
      final res = VitalityEngine.compute(
        VitalityInputs(
          chronoAge: 40.0,
          restingHR: 52.0,
          sleepHours: 7.4,
          sleepConsistency: 0.88,
          rmssd: 91.0,
          rmssdNorm: VitalityEngine.rmssdNorm(40.0),
          steps: 10500.0,
        ),
      );
      expect(res, isNotNull);
      expect(res!.bodyAge, lessThan(40.0));
      expect(res.deltaYears, greaterThan(0.0));
      expect(res.vitality, greaterThan(55.0));
      expect(res.paceOfAging, lessThan(1.0));
    });

    test('abstains when fewer than 3 factors or invalid age', () {
      expect(
        VitalityEngine.compute(
          const VitalityInputs(chronoAge: 40.0, restingHR: 55.0, steps: 8000.0),
        ),
        isNull,
      );
      expect(
        VitalityEngine.compute(
          const VitalityInputs(
            chronoAge: 0.0,
            restingHR: 55.0,
            sleepHours: 7.5,
            steps: 8000.0,
          ),
        ),
        isNull,
      );
    });
  });

  group('FitnessAgeEngine & 3-Tier Standing VO2max', () {
    test('reference peer (RHR 65, PAI 5.0) equals chronological age', () {
      expect(
        FitnessAgeEngine.fitnessAge(
          age: 35.0,
          sex: 'male',
          restingHR: 65.0,
          paIndex: 5.0,
        ),
        closeTo(35.0, 1e-6),
      );
    });

    test('3-tier VO2max selects GPS submax -> Nes waist -> Uth HR-ratio -> null',
        () {
      // Tier 1: GPS workout submax wins even when waist & RHR exist
      final t1 = resolveStandingVo2max(
        latestSubmaxVo2max: 49.4,
        age: 40.0,
        sex: 'male',
        waistCm: 84.0,
        restingHR: 60.0,
        rhrDays: 6,
        paIndex: 5.0,
      );
      expect(t1, isNotNull);
      expect(t1!.tier, 1);
      expect(t1.source, 'submax_gps');
      expect(t1.value, closeTo(49.4, 1e-6));

      // Tier 2: Nes 2011 waist wins when no workout submax exists and waistCm > 0
      final t2 = resolveStandingVo2max(
        latestSubmaxVo2max: null,
        age: 40.0,
        sex: 'male',
        waistCm: 84.0,
        restingHR: 60.0,
        rhrDays: 6,
        paIndex: 5.0,
      );
      expect(t2, isNotNull);
      expect(t2!.tier, 2);
      expect(t2.source, 'nes_waist');
      expect(
        t2.value,
        closeTo(
          100.27 - 0.296 * 40.0 + 0.226 * 5.0 - 0.369 * 84.0 - 0.155 * 60.0,
          1e-6,
        ),
      );

      // Tier 3: Uth 2004 (15.3 * Tanaka(40)=180 / RHR 60 = 45.9) when no waist
      final t3 = resolveStandingVo2max(
        latestSubmaxVo2max: null,
        age: 40.0,
        sex: 'male',
        waistCm: null,
        restingHR: 60.0,
        rhrDays: 4,
        paIndex: 5.0,
      );
      expect(t3, isNotNull);
      expect(t3!.tier, 3);
      expect(t3.source, 'uth_hr_ratio');
      expect(t3.value, closeTo(45.9, 1e-6));

      // Abstention: < 4 RHR nights and no GPS workout submax -> null
      final abstained = resolveStandingVo2max(
        latestSubmaxVo2max: null,
        age: 40.0,
        sex: 'male',
        waistCm: 84.0,
        restingHR: 60.0,
        rhrDays: 3,
        paIndex: 5.0,
      );
      expect(abstained, isNull);
    });
  });

  group('BiologicalAgeCard on HealthScreen & HomeScreen', () {
    testWidgets('renders Body Age, Pace of Aging, Vitality, Fitness Age, and VO2max tier',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const snap = LongevitySnapshot(
        chronoAge: 34.0,
        bodyAge: 31.4,
        paceOfAging: 0.80,
        vitality: 56.5,
        fitnessAge: 30.8,
        vo2max: StandingVo2max(
          value: 48.2,
          tier: 1,
          source: 'submax_gps',
        ),
        helpingMost: 'Heart-rate variability',
        holdingBack: 'Sleep duration',
        rhrNights: 6,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: HealthScreen(
            data: const HealthData(
              daysWithData: 6,
              longevity: snap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BiologicalAgeCard), findsOneWidget);
      expect(find.textContaining('31'), findsWidgets);
      expect(find.textContaining('0.80×'), findsOneWidget);
      expect(find.textContaining('48.2'), findsOneWidget);
      expect(find.textContaining('GPS workout'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const HomeScreen(
            data: HomeData(
              longevity: snap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BiologicalAgeSummaryRow), findsOneWidget);
      expect(find.textContaining('0.80×'), findsOneWidget);
    });
  });
}
