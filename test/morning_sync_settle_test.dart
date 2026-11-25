import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int _sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

void main() {
  const day = '2026-10-13';
  final onset = _sec(DateTime(2026, 10, 12, 23, 30));
  final wake0700 = _sec(DateTime(2026, 10, 13, 7, 0));
  final sync0702 = _sec(DateTime(2026, 10, 13, 7, 2));
  final wake0815 = _sec(DateTime(2026, 10, 13, 8, 15));
  final sync0817 = _sec(DateTime(2026, 10, 13, 8, 17));
  final midSleep0404 = _sec(DateTime(2026, 10, 13, 4, 4));

  group('immediate morning settlement on HISTORY_COMPLETE', () {
    test('settles immediately when drainCompleteEdgeSec is past wake + 60s',
        () {
      expect(
        overnightSettled(
          sleepOffsetSec: wake0700,
          dataEdgeSec: sync0702,
          drainCompleteEdgeSec: sync0702,
        ),
        isTrue,
      );
      expect(
        recoveryStateOf(
          wakeSec: wake0700,
          dataEdgeSec: sync0702,
          drainCompleteEdgeSec: sync0702,
        ),
        RecoveryState.finalReady,
      );
    });

    test('stays nightInProgress if user is still asleep at HISTORY_COMPLETE',
        () {
      // At 04:04 while still sleeping, sleepOffsetSec == dataEdgeSec == 04:04.
      expect(
        overnightSettled(
          sleepOffsetSec: midSleep0404,
          dataEdgeSec: midSleep0404,
          drainCompleteEdgeSec: midSleep0404,
        ),
        isFalse,
      );
      expect(
        recoveryStateOf(
          wakeSec: midSleep0404,
          dataEdgeSec: midSleep0404,
          drainCompleteEdgeSec: midSleep0404,
        ),
        RecoveryState.nightInProgress,
      );
    });

    test('stays unsettled mid-drain when HISTORY_COMPLETE has not covered wake',
        () {
      expect(
        overnightSettled(
          sleepOffsetSec: wake0700,
          dataEdgeSec: sync0702,
          drainCompleteEdgeSec: midSleep0404,
        ),
        isFalse,
      );
    });
  });

  group('sleep-in recalibration (wake moves >= 15 min)', () {
    test('holds 10-min jitter steady, recalibrates when user sleeps another hour',
        () {
      // 07:02 AM: first sync settles and pins 74%.
      var pin = nextFrozenHeadline(
        today: day,
        overnightComplete: overnightSettled(
          sleepOffsetSec: wake0700,
          dataEdgeSec: sync0702,
          drainCompleteEdgeSec: sync0702,
        ),
        liveReadiness: 74,
        current: null,
        wakeSec: wake0700,
        onsetSec: onset,
      );
      expect(pin?.value, 74);
      expect(pin?.wakeSec, wake0700);

      // Minor 10-minute (+600s) wake jitter on a later re-derive -> holds 74%.
      pin = nextFrozenHeadline(
        today: day,
        overnightComplete: true,
        liveReadiness: 71,
        current: pin,
        wakeSec: wake0700 + 600,
        onsetSec: onset,
      );
      expect(pin?.value, 74);

      // User goes back to sleep until 08:15 (+75m >= 15m tolerance) and syncs at 08:17 -> recalibrates to 81%!
      pin = nextFrozenHeadline(
        today: day,
        overnightComplete: overnightSettled(
          sleepOffsetSec: wake0815,
          dataEdgeSec: sync0817,
          drainCompleteEdgeSec: sync0817,
        ),
        liveReadiness: 81,
        current: pin,
        wakeSec: wake0815,
        onsetSec: onset,
      );
      expect(pin?.value, 81);
      expect(pin?.wakeSec, wake0815);
    });

    test('DB refreshComputeFreshness and headlinePinFor honour completed drain and sleep-in',
        () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_morning_settle_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      addTearDown(() async {
        await LocalDb.close();
        await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      });

      final today = LocalDb.localDayLabelNow();
      final now = DateTime.now();
      final wake1 = _sec(DateTime(now.year, now.month, now.day, 7, 0));
      final edge1 = wake1 + 120; // 2 min after wake
      final onset1 = wake1 - 7 * 3600;

      await LocalDb.putDayResult(
        dayId: today,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'data_edge_sec': edge1,
          'scalars': {'readiness': 74, 'rmssd': 58},
          'sleep': {
            'window': {
              'value': {'onset_ms': onset1 * 1000, 'offset_ms': wake1 * 1000},
            },
            'accounting': {
              'value': {'tst_sec': 7 * 3600},
            },
          },
        }),
        windowJson: jsonEncode({
          'onset_ms': onset1 * 1000,
          'offset_ms': wake1 * 1000,
        }),
        readiness: 74,
      );
      final db = await LocalDb.instance;
      await db.insert('decoded_onehz', {
        'ts_ms': edge1 * 1000,
        'rec_ts': edge1,
        'counter': 1,
        'hr': 62,
      });

      // Record HISTORY_COMPLETE at edge1 -> Today immediately settles!
      await LocalDb.setCursor(LocalDb.kHistoryCompleteEdgeCursor, '$edge1');
      await LocalDb.refreshComputeFreshness();
      final freshRow = await LocalDb.computeFreshness('today');
      final fresh = jsonDecode(freshRow!['payload_json'] as String) as Map;
      expect(fresh['overnight_day'], today);
      expect(fresh['overnight_state'], 'ready');
      expect(fresh['recovery_state'], 'final');

      // Pin 74 at wake1, then extend stored window by 45 min (sleep-in) -> old pin invalidated!
      await LocalDb.setFrozenHeadline(today, 74, wakeSec: wake1);
      expect(await LocalDb.headlinePinFor(today), 74);

      final wake2 = wake1 + 45 * 60;
      await LocalDb.putDayResult(
        dayId: today,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'data_edge_sec': wake2 + 120,
          'scalars': {'readiness': 81, 'rmssd': 64},
        }),
        windowJson: jsonEncode({
          'onset_ms': onset1 * 1000,
          'offset_ms': wake2 * 1000,
        }),
        readiness: 81,
      );
      expect(await LocalDb.headlinePinFor(today), isNull,
          reason: 'old 07:00 pin must release once wake moved by 45 min');
    });
  });
}
