import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart' show kAlgoVersion;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late String dbDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbDir = await databaseFactory.getDatabasesPath();
  });

  tearDownAll(() async {
    await LocalDb.close();
    try {
      File(p.join(dbDir, 'openstrap_restart_band_test.db')).deleteSync();
    } catch (_) {}
  });

  test('Cmd.rebootStrap stays in dangerousCmds against automatic sends', () {
    expect(dangerousCmds.contains(Cmd.rebootStrap), isTrue);
  });

  test('BleEngine.rebootStrap refuses when disconnected and sends 0x1D when connected',
      () async {
    final sent = <Uint8List>[];
    final engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
    );
    engine.debugWriteHook = (raw) async {
      sent.add(raw);
      return true;
    };

    // Disconnected -> refused, zero bytes sent.
    expect(await engine.rebootStrap(), isFalse);
    expect(sent, isEmpty);

    // Connected WHOOP 5.0 session -> sends opcode 0x1D (29) with empty payload.
    engine.debugInstallFakeLink(
      band: BandProfile.gen5,
      listening: true,
      onWrite: (raw) async {
        sent.add(raw);
        return true;
      },
    );
    expect(await engine.rebootStrap(), isTrue);
    expect(sent, hasLength(1));
    expect(sent.single[10], Cmd.rebootStrap); // Gen5 opcode offset = 10
  });

  test('commitSyncBatch un-finalizes past days overwritten by post-reboot re-sync',
      () async {
    await LocalDb.close();
    LocalDb.dbName = 'openstrap_restart_band_test.db';
    await databaseFactory.deleteDatabase(p.join(dbDir, LocalDb.dbName));
    final db = await LocalDb.instance;

    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
    final noonTs = DateTime(
          threeDaysAgo.year,
          threeDaysAgo.month,
          threeDaysAgo.day,
          12,
        ).millisecondsSinceEpoch ~/
        1000;
    final dayId = dayLabelOf(
      DateTime.fromMillisecondsSinceEpoch(noonTs * 1000),
    );

    await db.insert('day_result', {
      'day_id': dayId,
      'algo_version': kAlgoVersion,
      'payload_json': '{"scalars":{"rhr":55}}',
      'computed_at': noonTs,
      'finalized': 1,
    });
    await LocalDb.putDeriveFingerprint(dayId, 'fp-before-reboot');

    // Simulate post-reboot re-offload of 1 second on that finalized day.
    final raw = RawRecord(
      counter: 1,
      packetType: 0x2F,
      hex: '',
      capturedAt: noonTs * 1000,
      recTs: noonTs,
    );
    final sample = Sample(
      tsEpoch: noonTs,
      counter: 1,
      hr: 64,
      rrIntervalsMs: const [910],
    );
    await LocalDb.commitSyncBatch(
      [raw],
      [sample],
      trimToken: null,
      deviceFamily: 'gen5',
    );

    final row = (await db.query(
      'day_result',
      where: 'day_id = ?',
      whereArgs: [dayId],
    ))
        .single;
    expect(row['finalized'], 0,
        reason: 'overwritten finalized day must reopen for re-derivation');
    expect(await LocalDb.deriveFingerprint(dayId), isNull,
        reason: 'fingerprint must clear so processDay does not skip');
  });

  testWidgets('DeviceDetailView shows Restart band and confirmation callback',
      (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    var restarted = false;
    const band = HealthSource(
      name: 'WHOOP 5.0',
      kind: 'Main band',
      tier: SourceTier.wristOptical,
      icon: LucideIcons.watch,
      connected: true,
      isBand: true,
      family: 'gen5',
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: DeviceDetailView(
          band,
          onRestart: () => restarted = true,
        ),
      ),
    );
    expect(find.text('Restart band'), findsOneWidget);
    await t.tap(find.text('Restart band'));
    expect(restarted, isTrue);
  });
}
