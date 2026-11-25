import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';
import 'package:openstrap_edge/data/step_calibration.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WHOOP 5.0 nightlySkinTemp settle band (150 centi-C)', () {
    List<AdcSample> gen5Night({required int coldSec, int totalSec = 28800}) => [
          for (var i = 0; i < totalSec; i++)
            AdcSample(
              i * 1000.0,
              (i >= 0 && i < coldSec) ? 3000.0 : 3340.0,
            ),
        ];

    test('trims 5% cold warm-up and keeps 33.40 C settled mean', () {
      final m = nightlySkinTemp(gen5Night(coldSec: 1440), deviceFamily: 'gen5');
      expect(m.present, isTrue, reason: m.note);
      expect(m.value!.unit, 'centi_c');
      expect(m.value!.settledFraction, closeTo(0.95, 1e-9));
      expect(m.value!.mean, closeTo(3340.0, 1e-9));
      expect(m.value!.provisional, isFalse);
    });

    test('refuses a night spending 25% >1.5 C below median', () {
      final m = nightlySkinTemp(gen5Night(coldSec: 7200), deviceFamily: 'gen5');
      expect(m.present, isFalse);
      expect(m.note, startsWith('unsettled_skin_temp:settled=0.75'));
    });

    test('keeps a +1.0 C fever segment untouched', () {
      final fever = [
        for (var i = 0; i < 28800; i++)
          AdcSample(i * 1000.0, i < 7200 ? 3440.0 : 3340.0),
      ];
      final m = nightlySkinTemp(fever, deviceFamily: 'gen5');
      expect(m.present, isTrue);
      expect(m.value!.settledFraction, 1.0);
      expect(m.value!.mean, closeTo(3365.0, 1e-9));
    });
  });

  group('onehz_pipeline exact skin_temp_c, 4th-night dev_c, and site scoping',
      () {
    Map<String, dynamic> runNight({
      required List<double> priorHistory,
      int wearingSite = Wearing.wrist,
    }) {
      const onset = 1791846000;
      const dur = 6 * 3600;
      final ts = [for (var i = 0; i < dur; i++) onset + i];
      final hr = List<int>.filled(dur, 56);
      final skinTemp = List<int>.filled(dur, 3360); // 33.60 °C
      final enmo = List<double>.filled(dur, 0.005);
      final epochs = dur ~/ 30;
      return deriveDayBundle(
        DayBundleInput(
          date: '2026-10-13',
          dayTsSec: ts,
          dayHr: hr,
          stepSpans: const [],
          dayRrTsMs: const [],
          dayRrMs: const [],
          sleepTsSec: ts,
          sleepHr: hr,
          sleepRrTsMs: const [],
          sleepRrMs: const [],
          sleepSkinTemp: skinTemp,
          sleepEnmo: enmo,
          sleepJson: {
            'window': {
              'value': {
                'onset_ms': onset * 1000,
                'offset_ms': (onset + dur) * 1000,
              },
            },
            'accounting': {
              'value': {'tst_sec': dur},
            },
          },
          hypnoStages: List<String>.filled(epochs, 'light'),
          sleepOnsetSec: onset,
          sleepOffsetSec: onset + dur,
          tonightSleepOnsetSec: 0,
          profile: const {'age': 30, 'sex': 'm'},
          dayConfidence: 0.9,
          dayFlags: const [],
          deviceFamily: 'gen5',
          skinTempAdcHistory: priorHistory,
          wearingSite: wearingSite,
        ).toJson(),
      );
    }

    test('Night 1 emits exact skin_temp_c (33.60 C) with null dev_c', () {
      final b = runNight(priorHistory: const []);
      final sc = (b['scalars'] as Map).cast<String, dynamic>();
      expect(sc['skin_temp_c'], closeTo(33.6, 1e-6));
      expect(sc['skin_temp_dev_c'], isNull);
    });

    test('Night 4 (3 prior nights) emits skin_temp_dev_c (+0.30 C)', () {
      final b = runNight(priorHistory: const [3320.0, 3330.0, 3340.0]);
      final sc = (b['scalars'] as Map).cast<String, dynamic>();
      expect(sc['skin_temp_c'], closeTo(33.6, 1e-6));
      expect(sc['skin_temp_dev_c'], closeTo(0.3, 1e-6));
    });

    test('ambiguous mid-day wear-site switch (wearingSite=0) does not bank baseline',
        () {
      final b = runNight(
        priorHistory: const [3320.0, 3330.0, 3340.0],
        wearingSite: 0,
      );
      final sc = (b['scalars'] as Map).cast<String, dynamic>();
      expect(sc['skin_temp_adc'], isNull);
      expect(sc['skin_temp_dev_c'], isNull);
    });

    test('filterSkinTempHistoryByWearSite isolates Wrist and Bicep nights', () {
      final all = [
        (date: '2026-10-08', value: 3325.0), // legacy unstamped -> Wrist
        (date: '2026-10-09', value: 3335.0), // explicit Wrist
        (date: '2026-10-10', value: 3440.0), // explicit Bicep
        (date: '2026-10-11', value: 3450.0), // explicit Bicep
      ];
      final sites = <String, int>{
        '2026-10-09': Wearing.wrist,
        '2026-10-10': Wearing.bicep,
        '2026-10-11': Wearing.bicep,
      };
      expect(
        filterSkinTempHistoryByWearSite(
          all,
          sites: sites,
          wearingSite: Wearing.wrist,
        ),
        [3325.0, 3335.0],
      );
      expect(
        filterSkinTempHistoryByWearSite(
          all,
          sites: sites,
          wearingSite: Wearing.bicep,
        ),
        [3440.0, 3450.0],
      );
      expect(
        filterSkinTempHistoryByWearSite(
          all,
          sites: sites,
          wearingSite: 0,
        ),
        isEmpty,
      );
    });
  });

  group('HealthScreen Vitals & MetricDetail skin_temp UI', () {
    testWidgets('shows exact C and F headline + usual delta, and unsuppresses chart',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      expect(specOf('skin_temp').suppress, isNull);

      final metricUnits = UnitsController.seed(UnitSystem.metric);

      final healthData = HealthData(
        daysWithData: 6,
        today: const {
          'skin_temp': {
            'value': 1.2,
            'confidence': 0.9,
            'abs_c': 33.6,
            'dev_c': 0.3,
          },
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<UnitsController>.value(
          value: metricUnits,
          child: MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: HealthScreen(
              data: healthData,
              vitals: const VitalsData(),
              tab: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('33.6'), findsOneWidget);
      expect(find.text('°C'), findsOneWidget);
      expect(find.textContaining('+0.3 °C'), findsOneWidget);

      await metricUnits.setSystem(UnitSystem.imperial);
      await tester.pumpAndSettle();

      expect(find.text('92.5'), findsOneWidget);
      expect(find.text('°F'), findsOneWidget);
      expect(find.textContaining('+0.5 °F'), findsOneWidget);
    });
  });
}
