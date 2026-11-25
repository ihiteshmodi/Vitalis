import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart'
    show
        FitnessAgeEngine,
        StandingVo2max,
        VitalityEngine,
        VitalityInputs,
        median,
        resolveStandingVo2max;

import '../../data/db.dart' show LocalDb;
import '../../l10n/app_localizations.dart';
import '../profile/profile.dart' show SetRow;
import '../ui2.dart';

class LongevitySnapshot {
  const LongevitySnapshot({
    this.chronoAge,
    this.bodyAge,
    this.paceOfAging,
    this.vitality,
    this.fitnessAge,
    this.vo2max,
    this.helpingMost,
    this.holdingBack,
    this.rhrNights = 0,
  });

  final double? chronoAge;
  final double? bodyAge;
  final double? paceOfAging;
  final double? vitality;
  final double? fitnessAge;
  final StandingVo2max? vo2max;
  final String? helpingMost;
  final String? holdingBack;
  final int rhrNights;

  bool get hasAnyMetric =>
      bodyAge != null ||
      fitnessAge != null ||
      vitality != null ||
      vo2max != null;
}

/// Pure orchestrator assembling [LongevitySnapshot] from the last 7 derived days
/// of `metric_series` plus profile (`age`, `sex`, `waist_cm`) and optional
/// GPS submax workout VO2max (`sessions.vo2max_estimate`).
LongevitySnapshot buildLongevitySnapshot({
  required Map<String, dynamic> profile,
  required List<double> recentRhr,
  required List<double> recentRmssd,
  required List<double> recentSleepMin,
  required List<double> recentSteps,
  required List<double> recentStrain21,
  double? latestSubmaxVo2max,
  double? observedHrMax,
}) {
  final age = (profile['age'] as num?)?.toDouble();
  final sex = (profile['sex'] as String?)?.trim();
  final waistCm = (profile['waist_cm'] as num?)?.toDouble();
  final rhrNights = recentRhr.length;
  final medRhr = recentRhr.isEmpty ? null : median(recentRhr);
  final medHrv = recentRmssd.isEmpty ? null : median(recentRmssd);
  final sleepHoursList = [
    for (final m in recentSleepMin)
      if (m > 0) m / 60.0,
  ];
  final meanSleepHours = sleepHoursList.isEmpty
      ? null
      : sleepHoursList.reduce((a, b) => a + b) / sleepHoursList.length;
  final meanSteps = recentSteps.isEmpty
      ? null
      : recentSteps.reduce((a, b) => a + b) / recentSteps.length;

  final activeStrains = [for (final s in recentStrain21) if (s >= 8.0) s];
  final meanActiveStrain = activeStrains.isEmpty
      ? 0.0
      : activeStrains.reduce((a, b) => a + b) / activeStrains.length;
  final pai = FitnessAgeEngine.physicalActivityIndexFromStrain21(
    activeDaysPerWeek: activeStrains.length,
    meanActiveStrain21: meanActiveStrain,
  );

  final vo2 = resolveStandingVo2max(
    latestSubmaxVo2max: latestSubmaxVo2max,
    age: age,
    sex: sex,
    waistCm: waistCm,
    restingHR: medRhr,
    rhrDays: rhrNights,
    paIndex: pai,
    observedHrMax: observedHrMax,
  );

  double? fitnessAge;
  if (age != null &&
      age > 0 &&
      sex != null &&
      sex.isNotEmpty &&
      medRhr != null &&
      rhrNights >= FitnessAgeEngine.minCoverageDays) {
    fitnessAge = FitnessAgeEngine.compute(
      age: age,
      sex: sex,
      restingHR: medRhr,
      paIndex: pai,
      waistCm: waistCm,
    )?.fitnessAge;
  }

  VitalityInputs? vIn;
  if (age != null && age > 0) {
    vIn = VitalityInputs(
      chronoAge: age,
      restingHR: medRhr,
      sleepHours: meanSleepHours,
      sleepConsistency: VitalityEngine.sleepConsistency(sleepHoursList),
      rmssd: medHrv,
      rmssdNorm: VitalityEngine.rmssdNorm(age),
      steps: meanSteps,
    );
  }
  final vRes = vIn == null ? null : VitalityEngine.compute(vIn);
  String? helping;
  String? holding;
  if (vRes != null && vRes.contributions.isNotEmpty) {
    final sorted = [...vRes.contributions]
      ..sort((a, b) => a.lnHazard.compareTo(b.lnHazard));
    if (sorted.first.lnHazard < 0) helping = sorted.first.label;
    if (sorted.last.lnHazard > 0) holding = sorted.last.label;
  }

  return LongevitySnapshot(
    chronoAge: age,
    bodyAge: vRes?.bodyAge,
    paceOfAging: vRes?.paceOfAging,
    vitality: vRes?.vitality,
    fitnessAge: fitnessAge,
    vo2max: vo2,
    helpingMost: helping,
    holdingBack: holding,
    rhrNights: rhrNights,
  );
}

Future<LongevitySnapshot?> loadLongevitySnapshotFromDb(
  Map<String, dynamic> profile,
) async {
  try {
    final results = await Future.wait([
      LocalDb.trailingSeriesValues('rhr', 7),
      LocalDb.trailingSeriesValues('rmssd', 7),
      LocalDb.trailingSeriesValues('tst_min', 7),
      LocalDb.trailingSeriesValues('steps', 7),
      LocalDb.trailingSeriesValues('strain', 7),
      LocalDb.trailingSeriesValues('hr_ceiling_bpm', 90),
    ]);
    final submaxVo2 = await LocalDb.latestSessionVo2max();
    final ceilings = results[5];
    final maxCeiling = ceilings.isEmpty
        ? null
        : ceilings.reduce((a, b) => a > b ? a : b);
    return buildLongevitySnapshot(
      profile: profile,
      recentRhr: results[0],
      recentRmssd: results[1],
      recentSleepMin: results[2],
      recentSteps: results[3],
      recentStrain21: results[4],
      latestSubmaxVo2max: submaxVo2,
      observedHrMax: maxCeiling,
    );
  } catch (_) {
    return null;
  }
}

String vo2maxTierLabel(StandingVo2max v, AppLocalizations? l) => switch (v.tier) {
      1 => l?.bioAgeVo2Tier1 ?? 'GPS workout submax',
      2 => l?.bioAgeVo2Tier2 ?? 'Non-exercise (waist)',
      _ => l?.bioAgeVo2Tier3 ?? 'Heart-rate ratio estimate',
    };

class BiologicalAgeCard extends StatelessWidget {
  const BiologicalAgeCard({
    super.key,
    required this.snapshot,
  });

  final LongevitySnapshot snapshot;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);

    if (!snapshot.hasAnyMetric) {
      final missingAge = snapshot.chronoAge == null || snapshot.chronoAge! <= 0;
      final needNights =
          (FitnessAgeEngine.minCoverageDays - snapshot.rhrNights).clamp(1, 4);
      return StatusCard(
        l?.bioAgeTitle ?? 'Body Age & Fitness',
        missingAge
            ? (l?.bioAgeNeedProfileBody ??
                'Add your age and sex in Profile to unlock Body Age, Pace of Aging, Fitness Age, and standing VO2max.')
            : (l?.bioAgeNeedNightsBody(needNights) ??
                'Needs $needNights more sleeping heart-rate night${needNights == 1 ? '' : 's'} to unlock Fitness Age and standing VO2max.'),
        icon: LucideIcons.sparkles,
      );
    }

    final delta = (snapshot.chronoAge != null && snapshot.bodyAge != null)
        ? snapshot.chronoAge! - snapshot.bodyAge!
        : null;
    final younger = (delta ?? 0) >= 0;
    final yrsDiff = delta?.abs().round() ?? 0;
    final deltaText = delta == null
        ? null
        : yrsDiff == 0
            ? (l?.bioAgeAboutYourAge ?? 'About your age')
            : younger
                ? (l?.bioAgeYearsYounger(yrsDiff) ??
                    '$yrsDiff yr${yrsDiff == 1 ? '' : 's'} younger')
                : (l?.bioAgeYearsOlder(yrsDiff) ??
                    '$yrsDiff yr${yrsDiff == 1 ? '' : 's'} older');

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: S.x4,
            runSpacing: S.x3,
            children: [
              if (snapshot.bodyAge != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l?.bioAgeBodyAgeLabel ?? 'BODY AGE',
                      style: F.over.copyWith(color: p.ink3),
                    ),
                    const SizedBox(height: S.x1),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: S.x2,
                      children: [
                        Text(
                          '${snapshot.bodyAge!.round()}',
                          style: F.n48.copyWith(color: p.ink),
                        ),
                        Text(
                          l?.bioAgeYearsUnit ?? 'yrs',
                          style: F.body.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                    if (deltaText != null) ...[
                      const SizedBox(height: S.x1),
                      Text(
                        deltaText,
                        style: F.cap.copyWith(
                          color: younger ? p.on(C.green) : p.on(C.orange),
                        ),
                      ),
                    ],
                  ],
                ),
              if (snapshot.paceOfAging != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l?.bioAgePaceLabel ?? 'PACE OF AGING',
                      style: F.over.copyWith(color: p.ink3),
                    ),
                    const SizedBox(height: S.x1),
                    Text(
                      '${snapshot.paceOfAging!.toStringAsFixed(2)}×',
                      style: F.t1.copyWith(
                        color: snapshot.paceOfAging! <= 1.0
                            ? p.on(C.green)
                            : p.on(C.orange),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: S.x4),
          Divider(color: p.line, height: 1),
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x5,
            runSpacing: S.x3,
            children: [
              if (snapshot.vitality != null)
                _statTile(
                  p,
                  l?.bioAgeVitalityLabel ?? 'VITALITY',
                  '${snapshot.vitality!.round()} / 100',
                ),
              if (snapshot.fitnessAge != null)
                _statTile(
                  p,
                  l?.bioAgeFitnessAgeLabel ?? 'FITNESS AGE',
                  '${snapshot.fitnessAge!.round()} ${l?.bioAgeYearsUnit ?? 'yrs'}',
                ),
              if (snapshot.vo2max != null)
                _statTile(
                  p,
                  'VO2MAX',
                  '${snapshot.vo2max!.value.toStringAsFixed(1)} ml/kg/min · ${vo2maxTierLabel(snapshot.vo2max!, l)}',
                ),
            ],
          ),
          if (snapshot.helpingMost != null || snapshot.holdingBack != null) ...[
            const SizedBox(height: S.x3),
            Divider(color: p.line, height: 1),
            const SizedBox(height: S.x3),
            if (snapshot.helpingMost != null)
              Text(
                l?.bioAgeHelpingMost(snapshot.helpingMost!) ??
                    'Helping most: ${snapshot.helpingMost}',
                style: F.cap.copyWith(color: p.on(C.green)),
              ),
            if (snapshot.holdingBack != null) ...[
              if (snapshot.helpingMost != null) const SizedBox(height: S.x1),
              Text(
                l?.bioAgeHoldingBack(snapshot.holdingBack!) ??
                    'Holding you back: ${snapshot.holdingBack}',
                style: F.cap.copyWith(color: p.on(C.orange)),
              ),
            ],
          ],
          const SizedBox(height: S.x3),
          Text(
            l?.bioAgeDisclaimer ??
                'Wellness comparison from your habits, not a clinical biological age.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }

  Widget _statTile(P p, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: F.over.copyWith(color: p.ink3)),
          const SizedBox(height: S.x1),
          Text(
            value,
            style: F.body.copyWith(
              color: p.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class BiologicalAgeSummaryRow extends StatelessWidget {
  const BiologicalAgeSummaryRow({
    super.key,
    required this.snapshot,
    this.onTap,
  });

  final LongevitySnapshot snapshot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    if (!snapshot.hasAnyMetric) return const SizedBox.shrink();
    final l = AppLocalizations.of(c);
    final parts = <String>[
      if (snapshot.bodyAge != null)
        '${l?.bioAgeBodyAgeShort ?? 'Body Age'} ${snapshot.bodyAge!.round()}',
      if (snapshot.paceOfAging != null)
        '${l?.bioAgePaceShort ?? 'Pace'} ${snapshot.paceOfAging!.toStringAsFixed(2)}×',
      if (snapshot.vo2max != null)
        'VO2max ${snapshot.vo2max!.value.toStringAsFixed(1)}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Surface(
      onTap: onTap,
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: SetRow(
        LucideIcons.sparkles,
        C.green,
        l?.bioAgeTitle ?? 'Body Age & Fitness',
        sub: parts.join(' · '),
        chevron: onTap != null,
        onTap: onTap,
      ),
    );
  }
}
