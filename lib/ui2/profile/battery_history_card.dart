import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../notify/battery_forecast.dart';
import '../../state/clock_format.dart' show formatClockOf;
import '../onboarding/profile_setup.dart' show formatDay;
import '../ui2.dart';

enum BatteryHistoryRange {
  h24(24 * 3600, 48),
  d7(7 * 86400, 84),
  d30(30 * 86400, 120);

  const BatteryHistoryRange(this.spanSec, this.buckets);

  final int spanSec;
  final int buckets;
}

class BatteryHistoryBuilt {
  const BatteryHistoryBuilt({
    required this.series,
    required this.chargeMarks,
    required this.start,
    required this.mid,
    required this.end,
  });

  final List<double?> series;
  final List<double> chargeMarks;
  final DateTime start;
  final DateTime mid;
  final DateTime end;

  bool get hasAnyValue => series.any((v) => v != null && v.isFinite);
}

/// Pure bucketer turning irregular `band_battery` samples into a dense,
/// index-ordered series for [LineChart] + [ChartFrame].
///
/// Unmeasured buckets stay `null` so Bluetooth / off-wrist gaps break the
/// polyline honestly instead of interpolating a straight line across missing
/// hours. Charge markers are emitted once per rising transition into
/// `charging == true` (or an unflagged >= 5% rise between populated buckets).
BatteryHistoryBuilt buildBatteryHistorySeries({
  required List<BatterySample> samples,
  required BatteryHistoryRange range,
  required DateTime now,
}) {
  final endSec = now.millisecondsSinceEpoch ~/ 1000;
  final spanSec = range.spanSec;
  final startSec = endSec - spanSec;
  final n = range.buckets;
  final bucketSec = spanSec / n;

  final sums = List<double>.filled(n, 0.0);
  final counts = List<int>.filled(n, 0);
  final bucketCharging = List<bool>.filled(n, false);

  for (final s in samples) {
    if (s.tsSec < startSec || s.tsSec > endSec) continue;
    if (!s.pct.isFinite) continue;
    final rawIdx = ((s.tsSec - startSec) / bucketSec).floor();
    final idx = rawIdx.clamp(0, n - 1);
    sums[idx] += s.pct.clamp(0.0, 100.0);
    counts[idx] += 1;
    if (s.charging) bucketCharging[idx] = true;
  }

  final series = List<double?>.generate(
    n,
    (i) => counts[i] > 0 ? sums[i] / counts[i] : null,
    growable: false,
  );

  final chargeMarks = <double>[];
  var wasCharging = false;
  double? lastSeenPct;
  for (var i = 0; i < n; i++) {
    final pct = series[i];
    final unflaggedJump =
        pct != null && lastSeenPct != null && (pct - lastSeenPct) >= 5.0;
    final isChargingNow = bucketCharging[i] || unflaggedJump;
    if (isChargingNow && !wasCharging && n > 1) {
      chargeMarks.add((i / (n - 1)).clamp(0.0, 1.0));
    }
    if (pct != null) {
      wasCharging = isChargingNow;
      lastSeenPct = pct;
    } else if (!bucketCharging[i]) {
      wasCharging = false;
    }
  }

  final start = DateTime.fromMillisecondsSinceEpoch(startSec * 1000);
  final mid = DateTime.fromMillisecondsSinceEpoch(
    ((startSec + endSec) ~/ 2) * 1000,
  );
  return BatteryHistoryBuilt(
    series: series,
    chargeMarks: chargeMarks,
    start: start,
    mid: mid,
    end: now,
  );
}

String? formatBatteryTimeLeft(
  BatteryForecast? f,
  AppLocalizations? l, {
  DateTime? now,
}) {
  final empty = f?.predictedEmptyAt;
  if (empty == null) return null;
  final anchor = now ?? DateTime.now();
  final left = empty.difference(anchor);
  if (left.isNegative) return null;
  final h = left.inHours;
  if (h < 1) return l?.devicesBatteryUnderAnHourLeft ?? 'under an hour left';
  if (h < 36) return l?.devicesBatteryHoursLeft(h) ?? 'about $h h left';
  final d = (h / 24).round();
  return l?.devicesBatteryDaysLeft(d) ?? 'about $d days left';
}

class BatteryHistoryCard extends StatefulWidget {
  const BatteryHistoryCard({
    super.key,
    required this.samples,
    this.forecast,
    this.now,
    this.initialRange = BatteryHistoryRange.h24,
  });

  final List<BatterySample> samples;
  final BatteryForecast? forecast;
  final DateTime? now;
  final BatteryHistoryRange initialRange;

  @override
  State<BatteryHistoryCard> createState() => _BatteryHistoryCardState();
}

class _BatteryHistoryCardState extends State<BatteryHistoryCard> {
  late BatteryHistoryRange _range = widget.initialRange;

  static const _axis = AxisSpec(
    min: 0,
    max: 100,
    ticks: 3,
    format: axisInt,
  );

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final anchor = widget.now ?? DateTime.now();
    final built = buildBatteryHistorySeries(
      samples: widget.samples,
      range: _range,
      now: anchor,
    );

    final xLabels = _range == BatteryHistoryRange.h24
        ? [
            formatClockOf(built.start),
            formatClockOf(built.mid),
            formatClockOf(built.end),
          ]
        : [
            formatDay(built.start, l),
            formatDay(built.mid, l),
            formatDay(built.end, l),
          ];

    final drainLine = _drainHeadline(widget.forecast, l, anchor);
    final chargeFootnote = built.chargeMarks.isNotEmpty
        ? (l?.batteryHistoryChargeMarksFootnote ??
            'Dotted lines mark when the band went on the charger.')
        : null;

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubTabs(
            [
              l?.batteryHistoryRange24h ?? '24h',
              l?.batteryHistoryRange7d ?? '7d',
              l?.batteryHistoryRange30d ?? '30d',
            ],
            _range.index,
            (i) => setState(() => _range = BatteryHistoryRange.values[i]),
            color: C.green,
          ),
          const SizedBox(height: S.x4),
          ChartFrame(
            title: l?.batteryHistoryTitle ?? 'Battery history',
            unit: '%',
            height: 120,
            yAxis: _axis,
            xLabels: xLabels,
            series: built.series,
            xMarks: built.chargeMarks,
            footnote: chargeFootnote,
            empty: built.hasAnyValue
                ? null
                : NoData(
                    message: l?.batteryHistoryEmpty ??
                        'No battery readings in this window yet',
                  ),
            child: CustomPaint(
              size: Size.infinite,
              painter: LineChart(
                built.series,
                p.on(C.green),
                axis: _axis,
                dotInk: p.card,
              ),
            ),
          ),
          if (drainLine != null) ...[
            const SizedBox(height: S.x3),
            Text(
              drainLine,
              style: F.cap.copyWith(color: p.ink2),
            ),
          ],
        ],
      ),
    );
  }

  String? _drainHeadline(
    BatteryForecast? f,
    AppLocalizations? l,
    DateTime anchor,
  ) {
    if (f == null) return null;
    if (f.isUsable && f.drainPctPerHour != null) {
      final perHr = f.drainPctPerHour!.toStringAsFixed(2);
      final perDay = (f.drainPctPerHour! * 24).toStringAsFixed(1);
      final rate = l?.batteryHistoryDrainSummary(perHr, perDay) ??
          '~$perHr%/hr · ~$perDay%/day';
      final left = formatBatteryTimeLeft(f, l, now: anchor);
      return left == null ? rate : '$rate · $left';
    }
    if (f.note == ForecastNote.charging) {
      return l?.batteryHistoryChargingNow ?? 'Charging now';
    }
    if (f.note != null &&
        (f.note!.startsWith('need_history:') ||
            f.note!.startsWith('need_span:'))) {
      return l?.batteryHistoryNeedSpan ??
          'Drain rate appears after 2 hours off the charger';
    }
    return null;
  }
}
