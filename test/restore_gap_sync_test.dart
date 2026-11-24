import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/sync/sync_policy.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _createBackupDb(
  String dir,
  String name, {
  Map<String, String> cursors = const {},
  List<Map<String, Object?>> onehz = const [],
  List<Map<String, Object?>> rr = const [],
}) async {
  final path = p.join(dir, name);
  await databaseFactory.deleteDatabase(path);
  final src = await databaseFactory.openDatabase(path);
  await src.execute(
    'CREATE TABLE sync_cursor (name TEXT PRIMARY KEY, value TEXT, updated_at INTEGER NOT NULL)',
  );
  for (final e in cursors.entries) {
    await src.insert('sync_cursor', {
      'name': e.key,
      'value': e.value,
      'updated_at': 1,
    });
  }
  if (onehz.isNotEmpty) {
    await src.execute('''CREATE TABLE decoded_onehz (
      device_id TEXT NOT NULL DEFAULT '',
      ts_ms INTEGER NOT NULL,
      rec_ts INTEGER NOT NULL,
      counter INTEGER NOT NULL,
      hr INTEGER,
      PRIMARY KEY (device_id, ts_ms)
    )''');
    for (final r in onehz) {
      await src.insert('decoded_onehz', r);
    }
  }
  if (rr.isNotEmpty) {
    await src.execute('''CREATE TABLE decoded_rr (
      device_id TEXT NOT NULL DEFAULT '',
      ts_ms INTEGER NOT NULL,
      rec_ts INTEGER NOT NULL,
      beat_index INTEGER NOT NULL,
      rr_ts_ms INTEGER NOT NULL,
      rr_ms INTEGER NOT NULL,
      PRIMARY KEY (device_id, ts_ms, beat_index)
    )''');
    for (final r in rr) {
      await src.insert('decoded_rr', r);
    }
  }
  await src.close();
  return path;
}

void main() {
  late String dbDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbDir = await databaseFactory.getDatabasesPath();
  });

  setUp(() async {
    await LocalDb.close();
    LocalDb.dbName = 'openstrap_restore_gap_sync_test.db';
    await databaseFactory.deleteDatabase(p.join(dbDir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    for (final f in [
      'openstrap_restore_gap_sync_test.db',
      'gap_src.db',
      'corrupt_src.db',
      'zero_rr_src.db',
    ]) {
      try {
        File(p.join(dbDir, f)).deleteSync();
      } catch (_) {}
    }
  });

  test('never imports stale strap_trim and advances rec_ts_hw/counter_hw',
      () async {
    const tLocal = 1760000000;
    const tBackup = 1760100000;
    await LocalDb.setCursor('rec_ts_hw', '$tLocal');
    await LocalDb.setCursor('counter_hw', '100');

    final src = await _createBackupDb(
      dbDir,
      'gap_src.db',
      cursors: {
        'strap_trim': 'ac95000008000000',
        'strap_trim:dev2': '1122334455667788',
        'rec_ts_hw': '$tBackup',
        'counter_hw': '5500',
      },
    );

    await LocalDb.importFromDbFile(src);

    expect(await LocalDb.getCursor('strap_trim'), isNull);
    expect(await LocalDb.getCursor('strap_trim:dev2'), isNull);
    expect(await LocalDb.getCursorInt('rec_ts_hw'), tBackup);
    expect(await LocalDb.getCursorInt('counter_hw'), 5500);
  });

  test('rejects implausible future rec_ts_hw and reconciles to decoded_onehz',
      () async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final goodTs = nowSec - 7200;
    final futureTs = nowSec + 365 * 86400; // 1 year in the future

    final src = await _createBackupDb(
      dbDir,
      'corrupt_src.db',
      cursors: {'rec_ts_hw': '$futureTs'},
      onehz: [
        {
          'device_id': '',
          'ts_ms': goodTs * 1000,
          'rec_ts': goodTs,
          'counter': 42,
          'hr': 62,
        },
      ],
    );

    await LocalDb.importFromDbFile(src);
    expect(await LocalDb.getCursorInt('rec_ts_hw'), goodTs);
  });

  test('clears stale local decoded_rr when backup decoded_onehz has hr=0 '
      '(off-skin) identically on bulk and row-by-row paths', () async {
    const t0 = 1760200000;
    final src = await _createBackupDb(
      dbDir,
      'zero_rr_src.db',
      onehz: [
        {
          'device_id': '',
          'ts_ms': t0 * 1000,
          'rec_ts': t0,
          'counter': 10,
          'hr': 0,
        },
      ],
    );

    for (final rowByRow in [false, true]) {
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dbDir, LocalDb.dbName));
      final db = await LocalDb.instance;
      await db.insert('decoded_onehz', {
        'device_id': '',
        'ts_ms': t0 * 1000,
        'rec_ts': t0,
        'counter': 9,
        'hr': 75,
      });
      await db.insert('decoded_rr', {
        'device_id': '',
        'ts_ms': t0 * 1000,
        'rec_ts': t0,
        'beat_index': 0,
        'rr_ts_ms': t0 * 1000,
        'rr_ms': 810,
      });

      if (rowByRow) {
        await LocalDb.debugMergeRowByRow(src);
      } else {
        await LocalDb.importFromDbFile(src);
      }

      final beats = await (await LocalDb.instance).query(
        'decoded_rr',
        where: 'device_id = ? AND ts_ms = ?',
        whereArgs: ['', t0 * 1000],
      );
      expect(beats, isEmpty, reason: 'rowByRow=$rowByRow');
    }
  });

  test('sync burst continues draining overlap chunks when strapNewest is null '
      'and session has not completed', () {
    // Overlap chunk ACKed (batches=4, records=1200) whose timestamps sit behind
    // the restored backup's rec_ts_hw (frontierAdvanced=false), GET_DATA_RANGE
    // newest not received (strapNewestTs=null), HISTORY_COMPLETE not yet seen.
    expect(
      BackfillContinuation.shouldContinueBurstSession(
        batches: 4,
        records: 1200,
        gateDropsDelta: 0,
        complete: false,
        frontierAdvanced: false,
        strapNewestTs: null,
        frontierAfterTs: 1760100000,
      ),
      isTrue,
    );
    // Once HISTORY_COMPLETE is reported with no known backlog, stop cleanly.
    expect(
      BackfillContinuation.shouldContinueBurstSession(
        batches: 4,
        records: 1200,
        gateDropsDelta: 0,
        complete: true,
        frontierAdvanced: false,
        strapNewestTs: null,
        frontierAfterTs: 1760100000,
      ),
      isFalse,
    );
    // When strapNewest IS known and already caught up (within 300s), stop even
    // if frontier didn't move (pure resend of caught-up tail).
    expect(
      BackfillContinuation.shouldContinueBurstSession(
        batches: 2,
        records: 60,
        gateDropsDelta: 0,
        complete: false,
        frontierAdvanced: false,
        strapNewestTs: 1760100100,
        frontierAfterTs: 1760100000,
      ),
      isFalse,
    );
  });

  test('BleEngine.reseedCursorsFromStore reloads frontier and counter watch',
      () async {
    var cursorMap = <String, int?>{'rec_ts_hw': 1000, 'counter_hw': 50};
    final engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      cursorReader: (k) async => cursorMap[k],
    );
    expect(engine.recordFrontierTs, 0);

    cursorMap = {'rec_ts_hw': 1760100000, 'counter_hw': 9900};
    await engine.reseedCursorsFromStore();
    expect(engine.recordFrontierTs, 1760100000);
  });
}
