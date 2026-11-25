// Live sync progress leaf card + tappable Sync Status & Live BLE Log sheet.
//
// Honours AGENTS.md invariants:
//   - Invariant 3 (honesty): never fabricates a percentage — the strap never
//     reveals a total pending record count, so only ACKed chunk count,
//     records pulled, and the connect-time pages-behind snapshot are shown.
//   - Section 4.4 (perf): subscribes to `BleEngine.syncProgress` inside a leaf
//     `ValueListenableBuilder` so chunk ticks never rebuild HomeScreen.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../ble/ble_state.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart' show formatClockOf;
import '../profile/devices.dart' show formatDayTime;
import '../ui2.dart';

/// Leaf progress card shown on Home while the band is syncing.
class SyncProgressCard extends StatelessWidget {
  final ValueListenable<SyncProgressSnapshot> progressListenable;
  final VoidCallback? onTap;

  const SyncProgressCard({
    super.key,
    required this.progressListenable,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    return ValueListenableBuilder<SyncProgressSnapshot>(
      valueListenable: progressListenable,
      builder: (c, snap, _) {
        final spinner = SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: p.ink3),
        );
        final chunks = snap.chunksPulled;
        final behind = snap.pagesBehindAtConnect;
        final title = chunks > 0
            ? (l?.syncProgressTitleChunks(chunks) ??
                'Syncing with your band · $chunks ${chunks == 1 ? 'chunk' : 'chunks'} pulled')
            : (l?.homeSyncingTitle ?? 'Syncing with your band');
        final parts = <String>[
          if (behind != null && behind > 0)
            l?.syncProgressPagesBehind(behind) ??
                '$behind ${behind == 1 ? 'page' : 'pages'} behind at connect',
          if (snap.recordsPulled > 0)
            l?.syncProgressRecordsPulled(snap.recordsPulled) ??
                '${snap.recordsPulled} records saved',
          if (behind == null && snap.recordsPulled == 0)
            l?.homeSyncingBody ??
                'Pulling data now — this can take a few minutes on a full backlog.',
        ];
        return StatusCard(
          title,
          parts.join(' · '),
          fix: onTap != null
              ? (l?.syncProgressOpenSheet ?? 'Live sync status and log')
              : '',
          onFix: onTap,
          leading: spinner,
        );
      },
    );
  }
}

/// Open the live Sync Status & BLE Log modal sheet.
Future<void> showSyncStatusSheet(BuildContext c) {
  final p = P.of(c);
  return showModalBottomSheet<void>(
    context: c,
    backgroundColor: p.card,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: sheetMotion(c),
    builder: (_) => const SyncStatusSheet(),
  );
}

class SyncStatusSheet extends StatelessWidget {
  const SyncStatusSheet({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    return ValueListenableBuilder<SyncProgressSnapshot>(
      valueListenable: app.engine.syncProgress,
      builder: (c, snap, _) => ValueListenableBuilder<int>(
        valueListenable: app.logRevision,
        builder: (c, _, _) => SyncStatusSheetView(
          connected: app.isConnected,
          syncing: app.syncingNow,
          progress: snap,
          lastRecordAt: app.lastRecordAt,
          logs: List<String>.unmodifiable(app.logLines),
          now: DateTime.now(),
          onSyncNow: app.isConnected && !app.syncingNow
              ? () {
                  app.syncNow();
                }
              : null,
        ),
      ),
    );
  }
}

/// Pure, Provider-free view for tests and modal presentation.
class SyncStatusSheetView extends StatelessWidget {
  final bool connected;
  final bool syncing;
  final SyncProgressSnapshot progress;
  final DateTime? lastRecordAt;
  final List<String> logs;
  final DateTime now;
  final VoidCallback? onSyncNow;

  const SyncStatusSheetView({
    super.key,
    required this.connected,
    required this.syncing,
    required this.progress,
    required this.lastRecordAt,
    required this.logs,
    required this.now,
    this.onSyncNow,
  });

  static String _relativeAgo(DateTime at, DateTime now, AppLocalizations? l) {
    final diff = now.difference(at);
    if (diff.inSeconds < 60) {
      return l?.syncRelativeJustNow ?? 'just now';
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return l?.syncRelativeMinutesAgo(m) ?? '${m}m ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return l?.syncRelativeHoursAgo(h) ?? '${h}h ago';
    }
    return formatDayTime(at, l);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final behind = progress.pagesBehindAtConnect;
    final lastDone = progress.lastCompletedAt;
    final syncedWhen = lastRecordAt == null
        ? (l?.homeSyncedNever ?? 'No band data yet')
        : (lastRecordAt!.year == now.year &&
                lastRecordAt!.month == now.month &&
                lastRecordAt!.day == now.day
            ? formatClockOf(lastRecordAt!)
            : formatDayTime(lastRecordAt!, l));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (c, scrollCtl) => ListView(
        controller: scrollCtl,
        padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x8),
        children: [
          Text(
            l?.syncSheetTitle ?? 'Sync status & Bluetooth log',
            style: F.t2.copyWith(color: p.ink),
          ),
          const SizedBox(height: S.x1),
          Text(
            syncing
                ? (l?.syncSheetActiveSub ??
                    'Receiving history chunks from your band')
                : connected
                    ? (l?.syncSheetIdleConnectedSub ??
                        'Connected and listening for band data')
                    : (l?.syncSheetDisconnectedSub ??
                        'Your band is not connected — bring it close to sync'),
            style: F.cap.copyWith(color: p.ink2),
          ),
          const SizedBox(height: S.x4),
          Surface(
            color: p.card2,
            elevation: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: S.x2,
                  runSpacing: S.x2,
                  children: [
                    Pill(
                      syncing
                          ? (l?.devicesSyncing ?? 'Syncing')
                          : connected
                              ? (l?.devicesConnected ?? 'Connected')
                              : (l?.devicesNotConnected ?? 'Not connected'),
                      syncing
                          ? C.blue
                          : connected
                              ? C.green
                              : C.orange,
                      icon: syncing
                          ? LucideIcons.refreshCw
                          : connected
                              ? LucideIcons.bluetoothConnected
                              : LucideIcons.bluetoothOff,
                    ),
                    Pill(
                      l?.syncSheetChunksPill(progress.chunksPulled) ??
                          '${progress.chunksPulled} chunks pulled',
                      C.indigo,
                      icon: LucideIcons.layers,
                    ),
                    if (behind != null && behind > 0)
                      Pill(
                        l?.syncProgressPagesBehind(behind) ??
                            '$behind pages behind at connect',
                        C.purple,
                        icon: LucideIcons.database,
                      ),
                  ],
                ),
                const SizedBox(height: S.x3),
                Text(
                  l?.homeSyncedThrough(syncedWhen) ??
                      'Synced through $syncedWhen',
                  style: F.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (lastDone != null) ...[
                  const SizedBox(height: S.x1),
                  Text(
                    l?.syncSheetLastCompleted(
                          _relativeAgo(lastDone, now, l),
                        ) ??
                        'History synced ${_relativeAgo(lastDone, now, l)}',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                ],
                const SizedBox(height: S.x4),
                BigButton(
                  syncing
                      ? (l?.devicesSyncing ?? 'Syncing…')
                      : (l?.devicesSyncNow ?? 'Sync now'),
                  icon: LucideIcons.refreshCw,
                  color: C.blue,
                  busy: syncing,
                  onTap: onSyncNow,
                ),
                if (!connected) ...[
                  const SizedBox(height: S.x2),
                  Text(
                    l?.syncSheetDisabledReason ??
                        'Sync now is unavailable while the band is not connected.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: S.x5),
          Text(
            l?.syncSheetLogHeading ?? 'LIVE BLUETOOTH LOG',
            style: F.over.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x2),
          Surface(
            color: p.card2,
            elevation: 0,
            child: logs.isEmpty
                ? Text(
                    l?.syncSheetLogEmpty ?? 'No Bluetooth events logged yet.',
                    style: F.cap.copyWith(color: p.ink3),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0;
                          i < (logs.length < 80 ? logs.length : 80);
                          i++) ...[
                        if (i > 0) ...[
                          const SizedBox(height: S.x1),
                          Divider(color: p.line, height: 1),
                          const SizedBox(height: S.x1),
                        ],
                        Text(
                          logs[i],
                          style: F.cap.copyWith(
                            color: p.ink2,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
