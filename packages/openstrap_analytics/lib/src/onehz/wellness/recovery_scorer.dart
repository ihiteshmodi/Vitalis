// WELLNESS — NOOP RecoveryScorer (55/20/15/5/5 Winsorized-EWMA + logistic).
//
// Byte-identical port of NOOP's `RecoveryScorer.swift`:
//   higher HRV vs EWMA baseline       -> higher recovery (wHRV      = 0.55)
//   lower resting HR vs EWMA baseline -> higher recovery (wRHR      = 0.20)
//   higher sleep performance          -> higher recovery (wSleep    = 0.15)
//   lower resp vs EWMA baseline       -> higher recovery (wResp     = 0.05)
//   skin-temp deviation from 0 C      -> lower recovery  (wSkinTemp = 0.05)
//
// Cold-start gate: requires `Baselines.minNightsSeed` (4) prior valid HRV
// nights, so Recovery publishes starting on Night 5. Missing optional drivers
// drop cleanly and surviving weights renormalize.

import 'dart:math' as math;

import '../foundations/ewma_baselines.dart';
import '../types.dart';
import '../util.dart';
import 'readiness_composite.dart' show Readiness;

/// Prior valid HRV nights required before [RecoveryScorer] publishes a score
/// (4 prior nights -> Night 5).
const int kRecoveryMinBaselineNights = Baselines.minNightsSeed;

class RecoveryScorer {
  const RecoveryScorer._();

  static const double wHRV = 0.55;
  static const double wRHR = 0.20;
  static const double wSleep = 0.15;
  static const double wResp = 0.05;
  static const double wSkinTemp = 0.05;

  static const double skinTempScaleC = 1.0;
  static const double sleepPerfCenter = 0.85;
  static const double sleepPerfScale = 0.12;

  static const double logisticK = 1.6;
  static const double logisticZ0 = -0.20;
  static const double populationMean = 58.0;

  static const double bandRedMax = 34.0;
  static const double bandYellowMax = 67.0;

  static String band(double score) {
    if (score < bandRedMax) return 'red';
    if (score < bandYellowMax) return 'yellow';
    return 'green';
  }

  /// Robust z-score using EWMA spread: `(value - mean) / max(1.253 * spread, 1e-9)`.
  static double zScore(double value, {required double mean, required double spread}) {
    final sigma = math.max(1.253 * spread, 1e-9);
    return (value - mean) / sigma;
  }

  static double logisticScore(double z) {
    final s = 100.0 / (1.0 + math.exp(-logisticK * (z - logisticZ0)));
    return s.clamp(0.0, 100.0);
  }

  /// Score tonight's Recovery into the shared [Metric<Readiness>] envelope.
  ///
  /// [hrvHistory], [rhrHistory], and [respHistory] are ordered oldest-first and
  /// strictly PRIOR to tonight (self-excluded).
  static Metric<Readiness> scoreMetric({
    required double? hrv,
    required double? rhr,
    required double? resp,
    required List<double?> hrvHistory,
    required List<double?> rhrHistory,
    required List<double?> respHistory,
    double? sleepPerf,
    double? skinTempDevC,
  }) {
    final hrvState = Baselines.foldHistory(hrvHistory, Baselines.hrvCfg);
    final nHave = hrvState?.nValid ?? 0;

    if (hrv == null || !(Baselines.hrvCfg.minVal <= hrv && hrv <= Baselines.hrvCfg.maxVal)) {
      if (nHave < kRecoveryMinBaselineNights) {
        return Metric<Readiness>.absent(
          tier: Tier.estimate,
          inputs_used: const [],
          note: needBaselineNote(have: nHave, need: kRecoveryMinBaselineNights),
        );
      }
      return const Metric<Readiness>.absent(
        tier: Tier.estimate,
        inputs_used: [],
        note: 'no sleep-session RMSSD tonight — "—" (never imputed).',
      );
    }

    if (hrvState == null || !hrvState.usable) {
      return Metric<Readiness>.absent(
        tier: Tier.estimate,
        inputs_used: const [],
        note: needBaselineNote(have: nHave, need: kRecoveryMinBaselineNights),
      );
    }

    final rhrState = Baselines.foldHistory(rhrHistory, Baselines.restingHRCfg);
    final respState = Baselines.foldHistory(respHistory, Baselines.respCfg);

    final terms = <({String label, double z, double w})>[];
    final used = <String>[];

    final hrvZ = zScore(hrv, mean: hrvState.baseline, spread: hrvState.spread);
    terms.add((label: 'HRV', z: hrvZ, w: wHRV));
    used.add('HRV');

    if (rhr != null && rhrState != null && rhrState.usable) {
      final rhrZ = zScore(rhrState.baseline, mean: rhr, spread: rhrState.spread);
      terms.add((label: 'RHR', z: rhrZ, w: wRHR));
      used.add('RHR');
    }

    if (resp != null && respState != null && respState.usable) {
      final respZ = zScore(respState.baseline, mean: resp, spread: respState.spread);
      terms.add((label: 'RR', z: respZ, w: wResp));
      used.add('RR');
    }

    if (sleepPerf != null && sleepPerf.isFinite) {
      final sleepZ = (sleepPerf - sleepPerfCenter) / sleepPerfScale;
      terms.add((label: 'sleep', z: sleepZ, w: wSleep));
      used.add('sleep');
    }

    if (skinTempDevC != null && skinTempDevC.isFinite) {
      final tempZ = -skinTempDevC.abs() / skinTempScaleC;
      terms.add((label: 'temp', z: tempZ, w: wSkinTemp));
      used.add('temp');
    }

    final totalWeight = terms.fold(0.0, (acc, t) => acc + t.w);
    if (totalWeight <= 0) {
      return const Metric<Readiness>.absent(
        tier: Tier.estimate,
        inputs_used: [],
        note: 'no recovery inputs present — "—" (never imputed).',
      );
    }

    var compositeZ = 0.0;
    final drivers = <Driver>[];
    for (final t in terms) {
      final contrib = (t.z * t.w) / totalWeight;
      compositeZ += contrib;
      drivers.add(
        Driver(
          t.label,
          roundTo(contrib, 6),
          detail: 'ewma-z=${round6(t.z)}',
        ),
      );
    }
    drivers.sort(
      (a, b) => b.contribution.abs().compareTo(a.contribution.abs()),
    );

    final score = logisticScore(compositeZ);
    final conf = (0.4 + 0.12 * terms.length).clamp(0.4, 0.95);

    return Metric<Readiness>(
      value: Readiness(
        score,
        compositeZ,
        calibrationNights: hrvState.nValid,
      ),
      confidence: conf,
      tier: Tier.estimate,
      inputs_used: used,
      drivers: drivers,
      note: 'NOOP Recovery composite (55% HRV, 20% RHR, 15% Sleep, 5% Resp, '
          '5% Skin Temp; EWMA baselines + logistic k=1.6, z0=-0.20).',
    );
  }
}
