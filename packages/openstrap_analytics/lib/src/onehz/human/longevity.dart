// HUMAN LAYER — Vitality, Body Age, Pace of Aging, Fitness Age, & 3-Tier VO2max.
//
// Byte-identical port of NOOP's `VitalityEngine` + `FitnessAgeEngine` combined
// with Edge's 3-tier standing VO2max ladder:
//   Tier 1: Submaximal GPS workout VO2max (`sessions.vo2max_estimate`)
//   Tier 2: Nes et al. 2011 HUNT non-exercise waist model
//   Tier 3: Uth–Sørensen 2004 HR-ratio model (`15.3 * HRmax / RHR`)
//   Abstention: null whenever inputs do not clear honest coverage gates.

import 'dart:math' as math;

class VitalityInputs {
  const VitalityInputs({
    required this.chronoAge,
    this.restingHR,
    this.vo2max,
    this.expectedVO2max,
    this.sleepHours,
    this.sleepConsistency,
    this.rmssd,
    this.rmssdNorm,
    this.steps,
  });

  final double chronoAge;
  final double? restingHR;
  final double? vo2max;
  final double? expectedVO2max;
  final double? sleepHours;
  final double? sleepConsistency;
  final double? rmssd;
  final double? rmssdNorm;
  final double? steps;
}

class VitalityContribution {
  const VitalityContribution({
    required this.key,
    required this.label,
    required this.lnHazard,
  });

  final String key;
  final String label;
  final double lnHazard;
}

class VitalityResult {
  const VitalityResult({
    required this.vitality,
    required this.bodyAge,
    required this.chronoAge,
    required this.deltaYears,
    required this.paceOfAging,
    required this.bandYears,
    required this.contributions,
    required this.factorsUsed,
  });

  final double vitality; // 0..100 (50 = typical for chronological age)
  final double bodyAge; // years, clamped [20, 90]
  final double chronoAge;
  final double deltaYears; // chronoAge - bodyAge (+ve = younger)
  final double paceOfAging; // Gompertz hazard ratio exp(sumLn), 1.0x = neutral
  final double bandYears;
  final List<VitalityContribution> contributions;
  final int factorsUsed;
}

class VitalityEngine {
  const VitalityEngine._();

  static const double lnHazardPerYear = 0.6931471805599453 / 8.0;
  static const double overlapShrink = 0.75;
  static const double minBodyAge = 20.0;
  static const double maxBodyAge = 90.0;
  static const double vitalityPerYear = 2.5;
  static const int minFactors = 3;
  static const double bandYears = 5.0;

  static const List<(double, double)> _rmssdAnchors = [
    (20.0, 47.0),
    (30.0, 40.0),
    (40.0, 33.0),
    (50.0, 29.0),
    (60.0, 25.0),
    (70.0, 22.0),
    (80.0, 20.0),
  ];

  static double rmssdNorm(double age) {
    if (age <= _rmssdAnchors.first.$1) return _rmssdAnchors.first.$2;
    if (age >= _rmssdAnchors.last.$1) return _rmssdAnchors.last.$2;
    for (var i = 1; i < _rmssdAnchors.length; i++) {
      final (a1, v1) = _rmssdAnchors[i];
      if (age <= a1) {
        final (a0, v0) = _rmssdAnchors[i - 1];
        return v0 + (v1 - v0) * (age - a0) / (a1 - a0);
      }
    }
    return _rmssdAnchors.last.$2;
  }

  static double? sleepConsistency(List<double> nightlyHours) {
    final xs = [for (final h in nightlyHours) if (h.isFinite && h > 0) h];
    if (xs.length < 3) return null;
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    if (mean <= 0) return null;
    var sumSq = 0.0;
    for (final x in xs) {
      final d = x - mean;
      sumSq += d * d;
    }
    final cv = math.sqrt(sumSq / xs.length) / mean;
    return (1.0 - cv).clamp(0.0, 1.0).toDouble();
  }

  static List<VitalityContribution> contributions(VitalityInputs inputs) {
    final out = <VitalityContribution>[];
    if (inputs.restingHR case final rhr? when rhr.isFinite && rhr > 0) {
      out.add(VitalityContribution(
        key: 'rhr',
        label: 'Resting heart rate',
        lnHazard: ((rhr - 65.0) / 10.0) * 0.100,
      ));
    }
    if (inputs.vo2max case final vo2?
        when vo2.isFinite &&
            inputs.expectedVO2max != null &&
            inputs.expectedVO2max! > 0) {
      final expVo2 = inputs.expectedVO2max!;
      out.add(VitalityContribution(
        key: 'vo2max',
        label: 'Cardio fitness',
        lnHazard: ((expVo2 - vo2) / 3.5).clamp(-4.0, 4.0) * 0.130,
      ));
    }
    if (inputs.sleepHours case final sh? when sh.isFinite && sh > 0) {
      final dev = math.max(0.0, (sh - 7.5).abs() - 0.5);
      out.add(VitalityContribution(
        key: 'sleep',
        label: 'Sleep duration',
        lnHazard: dev.clamp(0.0, 3.0) * 0.110,
      ));
    }
    if (inputs.sleepConsistency case final c? when c.isFinite) {
      out.add(VitalityContribution(
        key: 'consistency',
        label: 'Sleep regularity',
        lnHazard: (0.75 - c.clamp(0.0, 1.0)) * 0.450,
      ));
    }
    if (inputs.rmssd case final h?
        when h.isFinite &&
            h > 0 &&
            inputs.rmssdNorm != null &&
            inputs.rmssdNorm! > 0) {
      final norm = inputs.rmssdNorm!;
      out.add(VitalityContribution(
        key: 'hrv',
        label: 'Heart-rate variability',
        lnHazard: ((norm - h) / norm).clamp(-1.0, 1.0) * 0.160,
      ));
    }
    if (inputs.steps case final s? when s.isFinite && s >= 0) {
      final deficit = (7000.0 - s.clamp(0.0, 11000.0)) / 1000.0;
      out.add(VitalityContribution(
        key: 'steps',
        label: 'Daily steps',
        lnHazard: deficit.clamp(-4.0, 4.0) * 0.064,
      ));
    }
    return out;
  }

  static VitalityResult? compute(VitalityInputs inputs) {
    if (!inputs.chronoAge.isFinite || inputs.chronoAge <= 0) return null;
    final contribs = contributions(inputs);
    if (contribs.length < minFactors) return null;
    final sumLn =
        contribs.fold(0.0, (acc, c) => acc + c.lnHazard) * overlapShrink;
    final deltaAge = sumLn / lnHazardPerYear;
    final bodyAge =
        (inputs.chronoAge + deltaAge).clamp(minBodyAge, maxBodyAge).toDouble();
    final delta = inputs.chronoAge - bodyAge;
    final vitality =
        (50.0 + delta * vitalityPerYear).clamp(0.0, 100.0).toDouble();
    final pace = math.exp(sumLn).clamp(0.4, 2.5).toDouble();
    return VitalityResult(
      vitality: vitality,
      bodyAge: bodyAge,
      chronoAge: inputs.chronoAge,
      deltaYears: delta,
      paceOfAging: pace,
      bandYears: bandYears,
      contributions: contribs,
      factorsUsed: contribs.length,
    );
  }
}

class FitnessAgeResult {
  const FitnessAgeResult({
    this.vo2max,
    required this.fitnessAge,
    required this.chronoAge,
    required this.deltaYears,
    required this.bandYears,
    required this.lowerConfidence,
  });

  final double? vo2max;
  final double fitnessAge;
  final double chronoAge;
  final double deltaYears;
  final double bandYears;
  final bool lowerConfidence;
}

class FitnessAgeEngine {
  const FitnessAgeEngine._();

  static const double menIntercept = 100.27;
  static const double menAge = 0.296;
  static const double menWC = 0.369;
  static const double menRHR = 0.155;
  static const double menPAI = 0.226;

  static const double womenIntercept = 74.74;
  static const double womenAge = 0.247;
  static const double womenWC = 0.259;
  static const double womenRHR = 0.114;
  static const double womenPAI = 0.198;

  static const double restingHRReference = 65.0;
  static const double paiReference = 5.0;
  static const double displayBandYears = 5.0;
  static const double minAge = 20.0;
  static const double maxAge = 80.0;
  static const int minCoverageDays = 4;
  static const int goodCoverageDays = 6;

  static bool _isFemale(String sex) {
    final s = sex.trim().toLowerCase();
    return s == 'f' || s == 'female';
  }

  static bool _isKnownBinary(String sex) {
    final s = sex.trim().toLowerCase();
    return s == 'm' || s == 'male' || s == 'f' || s == 'female';
  }

  static (double, double, double, double, double) _coeffs(String sex) =>
      _isFemale(sex)
          ? (womenIntercept, womenAge, womenWC, womenRHR, womenPAI)
          : (menIntercept, menAge, menWC, menRHR, menPAI);

  static double estimateVO2max({
    required double age,
    required String sex,
    required double waistCm,
    required double restingHR,
    required double paIndex,
  }) {
    final (intercept, ageC, wcC, rhrC, paiC) = _coeffs(sex);
    return intercept -
        ageC * age +
        paiC * paIndex -
        wcC * waistCm -
        rhrC * restingHR;
  }

  static double fitnessAge({
    required double age,
    required String sex,
    required double restingHR,
    required double paIndex,
  }) {
    final (_, ageC, _, rhrC, paiC) = _coeffs(sex);
    final fa = age +
        (rhrC * (restingHR - restingHRReference) -
                paiC * (paIndex - paiReference)) /
            ageC;
    return fa.clamp(minAge, maxAge).toDouble();
  }

  /// Reconstruct HUNT PA-index (0..15) from Edge's 0..21 daily strain series.
  /// Active day threshold: strain >= 8.0 (~30 on NOOP's 0..100 effort scale);
  /// 4 active days at strain 14.0 -> 2.5 * 2.0 = 5.0 (paiReference).
  static double physicalActivityIndexFromStrain21({
    required int activeDaysPerWeek,
    required double meanActiveStrain21,
  }) {
    final double frequency = switch (activeDaysPerWeek) {
      <= 0 => 0.0,
      1 => 0.5,
      2 => 1.0,
      3 || 4 => 2.5,
      _ => 5.0,
    };
    if (frequency == 0.0) return 0.0;
    final intensityDuration = (meanActiveStrain21 / 7.0).clamp(0.0, 3.0);
    return frequency * intensityDuration;
  }

  static FitnessAgeResult? compute({
    required double age,
    required String sex,
    required double restingHR,
    required double paIndex,
    double? waistCm,
    bool lowerConfidence = false,
  }) {
    if (age <= 0 || restingHR <= 0) return null;
    final fa = fitnessAge(
      age: age,
      sex: sex,
      restingHR: restingHR,
      paIndex: paIndex,
    );
    final vo2 = (waistCm != null && waistCm > 0)
        ? estimateVO2max(
            age: age,
            sex: sex,
            waistCm: waistCm,
            restingHR: restingHR,
            paIndex: paIndex,
          )
        : null;
    return FitnessAgeResult(
      vo2max: vo2 != null && vo2 > 3.5 && vo2 <= 95.0 ? vo2 : null,
      fitnessAge: fa,
      chronoAge: age,
      deltaYears: age - fa,
      bandYears: displayBandYears,
      lowerConfidence: lowerConfidence || !_isKnownBinary(sex),
    );
  }
}

class StandingVo2max {
  const StandingVo2max({
    required this.value,
    required this.tier,
    required this.source,
  });

  final double value;
  /// 1 = GPS submax workout, 2 = Nes 2011 waist non-exercise, 3 = Uth 2004 HR ratio.
  final int tier;
  final String source;
}

/// 3-tier standing VO2max ladder:
///   Tier 1 (`submax_gps`): Steady-state GPS workout submax (`sessions.vo2max_estimate`)
///   Tier 2 (`nes_waist`):  Nes 2011 HUNT waist-circumference model (`waistCm > 0`, `>= 4` RHR nights)
///   Tier 3 (`uth_hr_ratio`): Uth 2004 `15.3 * HRmax / RHR` (`age > 0`, `>= 4` RHR nights)
StandingVo2max? resolveStandingVo2max({
  double? latestSubmaxVo2max,
  double? age,
  String? sex,
  double? waistCm,
  double? restingHR,
  int rhrDays = 0,
  double paIndex = FitnessAgeEngine.paiReference,
  double? observedHrMax,
}) {
  if (latestSubmaxVo2max != null &&
      latestSubmaxVo2max.isFinite &&
      latestSubmaxVo2max > 3.5 &&
      latestSubmaxVo2max <= 95.0) {
    return StandingVo2max(
      value: latestSubmaxVo2max,
      tier: 1,
      source: 'submax_gps',
    );
  }

  if (age == null ||
      !age.isFinite ||
      age <= 0 ||
      restingHR == null ||
      !restingHR.isFinite ||
      restingHR <= 0 ||
      rhrDays < FitnessAgeEngine.minCoverageDays) {
    return null;
  }

  if (waistCm != null &&
      waistCm.isFinite &&
      waistCm > 0 &&
      sex != null &&
      sex.trim().isNotEmpty) {
    final nes = FitnessAgeEngine.estimateVO2max(
      age: age,
      sex: sex,
      waistCm: waistCm,
      restingHR: restingHR,
      paIndex: paIndex,
    );
    if (nes.isFinite && nes > 3.5 && nes <= 95.0) {
      return StandingVo2max(
        value: nes,
        tier: 2,
        source: 'nes_waist',
      );
    }
  }

  final hrMax = (observedHrMax != null && observedHrMax.isFinite && observedHrMax > restingHR + 20)
      ? observedHrMax
      : (208.0 - 0.7 * age);
  if (hrMax <= restingHR) return null;
  final uth = 15.3 * hrMax / restingHR;
  if (!uth.isFinite || uth <= 3.5 || uth > 95.0) return null;
  return StandingVo2max(
    value: uth,
    tier: 3,
    source: 'uth_hr_ratio',
  );
}
