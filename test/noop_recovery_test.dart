import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';
import 'package:openstrap_edge/compute/readiness_calibration_backfill.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('RecoveryScorer byte-identical NOOP math', () {
    test('neutral z=0 night lands on 100 / (1 + exp(-0.32)) ~= 57.93%', () {
      final m = RecoveryScorer.scoreMetric(
        hrv: 90.0,
        rhr: 52.0,
        resp: 14.5,
        hrvHistory: const [90.0, 90.0, 90.0, 90.0],
        rhrHistory: const [52.0, 52.0, 52.0, 52.0],
        respHistory: const [14.5, 14.5, 14.5, 14.5],
        sleepPerf: RecoveryScorer.sleepPerfCenter,
        skinTempDevC: 0.0,
      );
      expect(m.present, isTrue, reason: m.note);
      expect(m.value!.compositeZ, closeTo(0.0, 1e-9));
      final expected = 100.0 / (1.0 + math.exp(-0.32));
      expect(m.value!.score, closeTo(expected, 1e-6));
    });

    test('cold-start abstains on 0..3 prior HRV nights and scores on 4th prior (Night 5)',
        () {
      for (var n = 0; n < 4; n++) {
        final m = RecoveryScorer.scoreMetric(
          hrv: 92.0,
          rhr: 52.0,
          resp: 14.5,
          hrvHistory: List<double>.filled(n, 90.0),
          rhrHistory: List<double>.filled(n, 53.0),
          respHistory: List<double>.filled(n, 14.5),
          sleepPerf: 0.88,
        );
        expect(m.present, isFalse);
        expect(m.note, 'need_baseline:have=$n,need=4');
      }

      final night5 = RecoveryScorer.scoreMetric(
        hrv: 96.0,
        rhr: 51.0,
        resp: 14.2,
        hrvHistory: const [83.0, 86.8, 94.5, 96.7],
        rhrHistory: const [56.9, 54.1, 52.3, 53.4],
        respHistory: const [14.8, 14.6, 14.5, 14.4],
        sleepPerf: 0.921,
        skinTempDevC: 0.01,
      );
      expect(night5.present, isTrue, reason: night5.note);
      expect(night5.value!.score, greaterThan(60.0));
    });

    test('skin-temp deviation applies symmetric penalty and missing optional terms renormalize',
        () {
      const hrvH = [90.0, 90.0, 90.0, 90.0];
      const rhrH = [52.0, 52.0, 52.0, 52.0];
      final base = RecoveryScorer.scoreMetric(
        hrv: 90.0,
        rhr: 52.0,
        resp: null,
        hrvHistory: hrvH,
        rhrHistory: rhrH,
        respHistory: const [],
        sleepPerf: 0.85,
        skinTempDevC: 0.0,
      );
      final warm = RecoveryScorer.scoreMetric(
        hrv: 90.0,
        rhr: 52.0,
        resp: null,
        hrvHistory: hrvH,
        rhrHistory: rhrH,
        respHistory: const [],
        sleepPerf: 0.85,
        skinTempDevC: 0.8,
      );
      final cool = RecoveryScorer.scoreMetric(
        hrv: 90.0,
        rhr: 52.0,
        resp: null,
        hrvHistory: hrvH,
        rhrHistory: rhrH,
        respHistory: const [],
        sleepPerf: 0.85,
        skinTempDevC: -0.8,
      );
      expect(warm.value!.score, closeTo(cool.value!.score, 1e-9));
      expect(warm.value!.score, lessThan(base.value!.score));
    });
  });

  group('Owner 6-day WHOOP 5.0 sequence & historical backfill', () {
    test('backfillNoopRecovery scores finalized Night 5 & Night 6 from stored series',
        () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_noop_recovery_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      addTearDown(() async {
        await LocalDb.close();
        await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      });

      // Exact numbers from the owner's 6 WHOOP 5.0 nights (2026-10-08..13)
      const nights = [
        ('2026-10-08', 56.93, 82.96, 67.2, 3325.0),
        ('2026-10-09', 54.10, 86.79, 94.2, 3330.0),
        ('2026-10-10', 52.30, 94.55, 82.3, 3335.0),
        ('2026-10-11', 53.41, 96.69, 83.5, 3326.0),
        ('2026-10-12', 51.89, 93.00, 92.1, 3342.0),
        ('2026-10-13', 51.69, 91.00, 89.1, 3360.0),
      ];

      for (final (day, rhr, rmssd, eff, tempAdc) in nights) {
        await LocalDb.putDayResult(
          dayId: day,
          algoVersion: 97,
          windowJson: '{}',
          finalized: true,
          rhr: rhr,
          rmssd: rmssd,
          readiness: null,
          source: 'band',
          deviceFamily: 'gen5',
          payloadJson: jsonEncode({
            'date': day,
            'device_family': 'gen5',
            'clinical': {
              'readiness_composite': {'value': '—', 'confidence': 0},
            },
            'scalars': {
              'rhr': rhr,
              'rmssd': rmssd,
              'readiness': null,
              'efficiency': eff,
              'skin_temp_adc': tempAdc,
            },
          }),
          series: {
            'rhr': rhr,
            'rmssd': rmssd,
            'ln_rmssd': math.log(rmssd),
            'efficiency': eff,
            'skin_temp_adc': tempAdc,
          },
        );
      }

      final rescored = await backfillNoopRecovery(rawDays: const {});
      expect(rescored, 2, reason: 'Oct 12 (Night 5) and Oct 13 (Night 6) score');

      final oct11 = await LocalDb.dayResult('2026-10-11');
      final oct12 = await LocalDb.dayResult('2026-10-12');
      final oct13 = await LocalDb.dayResult('2026-10-13');
      expect(oct11!['readiness'], isNull);
      expect(oct12!['algo_version'], kAlgoVersion);
      expect((oct12['readiness'] as num).toDouble(), inInclusiveRange(55.0, 85.0));
      expect((oct13!['readiness'] as num).toDouble(), inInclusiveRange(50.0, 85.0));
    });

    test('deriveDayBundle scores Night 5 directly from 4 prior RMSSD/RHR nights',
        () {
      const onset = 1791846000;
      const dur = 6 * 3600;
      final ts = [for (var i = 0; i < dur; i++) onset + i];
      final hr = List<int>.filled(dur, 52);
      final rrMs = <double>[];
      final rrTsMs = <double>[];
      var tMs = onset * 1000.0;
      while (tMs < (onset + dur) * 1000.0) {
        final ibi =
            1150.0 + 115.0 * math.sin(2 * math.pi * 0.24 * (tMs / 1000.0));
        rrMs.add(ibi);
        rrTsMs.add(tMs);
        tMs += ibi;
      }
      final b = deriveDayBundle(
        DayBundleInput(
          date: '2026-10-12',
          dayTsSec: ts,
          dayHr: hr,
          sleepTsSec: ts,
          sleepHr: hr,
          sleepRrTsMs: rrTsMs,
          sleepRrMs: rrMs,
          sleepSkinTemp: List<int>.filled(dur, 3342),
          sleepJson: {
            'efficiency_pct': 92.1,
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
          hypnoStages: List<String>.filled(dur ~/ 30, 'light'),
          sleepOnsetSec: onset,
          sleepOffsetSec: onset + dur,
          profile: const {'age': 30, 'sex': 'm'},
          deviceFamily: 'gen5',
          rmssdHistory: const [82.96, 86.79, 94.55, 96.69],
          rhrHistory: const [56.93, 54.10, 52.30, 53.41],
          skinTempAdcHistory: const [3325.0, 3330.0, 3335.0, 3326.0],
        ).toJson(),
      );
      final sc = (b['scalars'] as Map).cast<String, dynamic>();
      expect(sc['readiness'], isNotNull);
      expect((sc['readiness'] as num).toDouble(), greaterThan(60.0));
    });
  });
}
