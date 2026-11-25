import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/clock_format.dart' show formatClockOf;
import '../ui2.dart';
import 'home_screen.dart' show ChartPoint, pointsOf;

class OvernightHrvData {
  const OvernightHrvData({
    this.timeline = const [],
    this.rmssdMean,
    this.sdnn,
  });

  final List<ChartPoint> timeline;
  final double? rmssdMean;
  final double? sdnn;

  bool get hasAnyData => timeline.isNotEmpty;

  factory OvernightHrvData.fromMap(Map<String, dynamic> m) {
    final pts = pointsOf({'points': m['timeline']});
    final rmssd = (m['rmssd'] as num?)?.toDouble();
    final sdnn = ((m['sdnn_window'] ?? m['sdnn']) as num?)?.toDouble();
    return OvernightHrvData(
      timeline: pts,
      rmssdMean: rmssd,
      sdnn: sdnn,
    );
  }
}

class OvernightHrvStats {
  const OvernightHrvStats({
    required this.denseSeries,
    this.start,
    this.mid,
    this.end,
    this.minMs,
    this.medianMs,
    this.meanMs,
    this.maxMs,
    this.sdnnMs,
  });

  final List<double?> denseSeries;
  final DateTime? start;
  final DateTime? mid;
  final DateTime? end;
  final double? minMs;
  final double? medianMs;
  final double? meanMs;
  final double? maxMs;
  final double? sdnnMs;

  bool get hasValues => denseSeries.any((v) => v != null && v.isFinite);
}

const int _kBucketSec = 300;
const int _kMaxDenseBuckets = 180;

OvernightHrvStats computeOvernightHrvStats(OvernightHrvData data) {
  final valid = [
    for (final p in data.timeline)
      if (p.v.isFinite && p.v > 0) p,
  ]..sort((a, b) => a.t.compareTo(b.t));

  if (valid.isEmpty) {
    return OvernightHrvStats(
      denseSeries: const [],
      meanMs: data.rmssdMean,
      sdnnMs: data.sdnn,
    );
  }

  final t0 = valid.first.t;
  final t1 = valid.last.t;
  final spanSec = t1 - t0;
  final rawBuckets = (spanSec ~/ _kBucketSec) + 1;
  final n = rawBuckets.clamp(1, _kMaxDenseBuckets);
  final stepSec = n <= 1 ? _kBucketSec.toDouble() : spanSec / (n - 1);

  final sums = List<double>.filled(n, 0.0);
  final counts = List<int>.filled(n, 0);
  for (final pt in valid) {
    final idx = stepSec <= 0
        ? 0
        : ((pt.t - t0) / stepSec).floor().clamp(0, n - 1);
    sums[idx] += pt.v;
    counts[idx] += 1;
  }

  final dense = List<double?>.generate(
    n,
    (i) => counts[i] > 0 ? sums[i] / counts[i] : null,
    growable: false,
  );

  final sortedVals = [for (final p in valid) p.v]..sort();
  final minMs = sortedVals.first;
  final maxMs = sortedVals.last;
  final midIdx = sortedVals.length ~/ 2;
  final medianMs = sortedVals.length.isOdd
      ? sortedVals[midIdx]
      : (sortedVals[midIdx - 1] + sortedVals[midIdx]) / 2.0;
  final rawMean =
      sortedVals.reduce((a, b) => a + b) / sortedVals.length.toDouble();

  return OvernightHrvStats(
    denseSeries: dense,
    start: DateTime.fromMillisecondsSinceEpoch(t0 * 1000),
    mid: DateTime.fromMillisecondsSinceEpoch(((t0 + t1) ~/ 2) * 1000),
    end: DateTime.fromMillisecondsSinceEpoch(t1 * 1000),
    minMs: minMs,
    medianMs: medianMs,
    meanMs: data.rmssdMean ?? rawMean,
    maxMs: maxMs,
    sdnnMs: data.sdnn,
  );
}

class OvernightHrvCard extends StatelessWidget {
  const OvernightHrvCard({
    super.key,
    required this.data,
  });

  final OvernightHrvData data;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final stats = computeOvernightHrvStats(data);
    final finiteVals = [
      for (final v in stats.denseSeries)
        if (v != null && v.isFinite) v,
    ];
    final axis = AxisSpec.of(finiteVals, ticks: 3, format: axisInt, floor: 0);
    final xLabels =
        (stats.start != null && stats.mid != null && stats.end != null)
            ? [
                formatClockOf(stats.start!),
                formatClockOf(stats.mid!),
                formatClockOf(stats.end!),
              ]
            : const <String>[];

    final tiles = <(String, String)>[
      if (stats.minMs != null)
        (l?.overnightHrvMin ?? 'Min', '${stats.minMs!.round()} ms'),
      if (stats.medianMs != null)
        (l?.overnightHrvMedian ?? 'Median', '${stats.medianMs!.round()} ms'),
      if (stats.meanMs != null)
        (l?.overnightHrvMean ?? 'Mean', '${stats.meanMs!.round()} ms'),
      if (stats.maxMs != null)
        (l?.overnightHrvMax ?? 'Max', '${stats.maxMs!.round()} ms'),
      if (stats.sdnnMs != null)
        (l?.investigateSdnn ?? 'SDNN', '${stats.sdnnMs!.round()} ms'),
    ];

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChartFrame(
            title: l?.overnightHrvTitle ?? 'Overnight HRV (5-min windows)',
            unit: 'ms',
            height: 130,
            yAxis: axis,
            xLabels: xLabels,
            series: stats.denseSeries,
            empty: stats.hasValues
                ? null
                : NoData(
                    message: l?.overnightHrvEmpty ??
                        'No overnight 5-minute HRV windows recorded yet',
                  ),
            child: CustomPaint(
              size: Size.infinite,
              painter: LineChart(
                stats.denseSeries,
                p.on(C.green),
                axis: axis,
                dotInk: p.card,
              ),
            ),
          ),
          if (stats.hasValues && tiles.isNotEmpty) ...[
            const SizedBox(height: S.x4),
            Divider(color: p.line, height: 1),
            const SizedBox(height: S.x3),
            Wrap(
              spacing: S.x5,
              runSpacing: S.x3,
              children: [
                for (final (label, value) in tiles)
                  Column(
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
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
