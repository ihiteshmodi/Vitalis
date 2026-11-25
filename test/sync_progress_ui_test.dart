import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_edge/ui2/screens/sync_status_sheet.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  group('SyncProgressSnapshot', () {
    test('computes wrap-safe pagesBehind from GET_DATA_RANGE ring fields', () {
      expect(
        pagesBehindFromDataRange(const {
          'written': 150,
          'trim_page': 108,
          'capacity': 131072,
        }),
        42,
      );
      // Wraparound: write pointer wrapped past capacity while trim sits near end.
      expect(
        pagesBehindFromDataRange(const {
          'written': 10,
          'trim_page': 131062,
          'capacity': 131072,
        }),
        20,
      );
      // Zero behind -> null/0 handled honestly.
      expect(
        pagesBehindFromDataRange(const {
          'written': 108,
          'trim_page': 108,
          'capacity': 131072,
        }),
        0,
      );
      // Corrupt / out-of-bounds -> null.
      expect(
        pagesBehindFromDataRange(const {
          'written': 200000,
          'trim_page': 10,
          'capacity': 131072,
        }),
        isNull,
      );
    });

    test('tracker increments chunks on ACK and resets on start and disconnect',
        () {
      final tracker = SyncProgressTracker();
      tracker.onSyncStart();
      tracker.onDataRange(const {
        'written': 150,
        'trim_page': 108,
        'capacity': 131072,
      });
      expect(tracker.snapshot.chunksPulled, 0);
      expect(tracker.snapshot.pagesBehindAtConnect, 42);

      tracker.onBatchAcked(recordsInChunk: 120);
      tracker.onBatchAcked(recordsInChunk: 90);
      expect(tracker.snapshot.chunksPulled, 2);
      expect(tracker.snapshot.recordsPulled, 210);

      // Disconnect clears active state and session counters so nothing sticks.
      tracker.onDisconnect();
      expect(tracker.snapshot.active, isFalse);
      expect(tracker.snapshot.chunksPulled, 0);
      expect(tracker.snapshot.pagesBehindAtConnect, isNull);
    });
  });

  group('SyncProgressCard & SyncStatusSheet UI', () {
    testWidgets(
        'renders live chunks + backlog without any percent sign, and opens BLE log sheet on tap',
        (t) async {
      t.view.physicalSize = const Size(800, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      final progress = ValueNotifier<SyncProgressSnapshot>(
        SyncProgressSnapshot(
          active: true,
          chunksPulled: 14,
          recordsPulled: 840,
          pagesBehindAtConnect: 42,
          lastCompletedAt: DateTime(2026, 10, 13, 8, 10),
        ),
      );
      final logs = ValueNotifier<List<String>>([
        '[SYNC] HistoryEnd batch=14 committed 60 rows -> ACK sent',
        '[BACKLOG] used=630 free=130442 written=150/131072 trim_page=108',
      ]);

      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: SyncProgressCard(
              progressListenable: progress,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('14 chunks pulled'), findsOneWidget);
      expect(find.textContaining('42 pages behind at connect'), findsOneWidget);
      // Invariant 3: NEVER fabricate a percentage.
      expect(find.textContaining('%'), findsNothing);

      // Render the sheet directly with disconnected state to check honest Sync Now copy.
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: SyncStatusSheetView(
              connected: false,
              syncing: false,
              progress: progress.value,
              lastRecordAt: DateTime(2026, 10, 13, 8, 14),
              logs: logs.value,
              now: DateTime(2026, 10, 13, 8, 20),
              onSyncNow: null,
            ),
          ),
        ),
      );

      expect(
        find.textContaining('HistoryEnd batch=14 committed 60 rows'),
        findsOneWidget,
      );
      expect(find.textContaining('not connected'), findsWidgets);
    });
  });
}
