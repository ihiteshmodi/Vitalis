import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/notify/battery_forecast.dart';
import 'package:openstrap_edge/ui2/profile/battery_history_card.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12, 0);
  final nowSec = now.millisecondsSinceEpoch ~/ 1000;

  group('buildBatteryHistorySeries', () {
    test('buckets 24h/7d/30d densely, leaves gaps null, and marks charges', () {
      final startSec = nowSec - 24 * 3600;
      final samples = <BatterySample>[
        // First 3 hours discharging 60% -> 58%
        for (var i = 0; i < 6; i++)
          BatterySample(
            tsSec: startSec + i * 1800 + 300,
            pct: 60.0 - i * 0.4,
            charging: false,
          ),
        // 4-hour Bluetooth gap (buckets 6..13 null)
        // Put on charger at bucket 14 for 2 buckets (55% -> 98%)
        BatterySample(
          tsSec: startSec + 14 * 1800 + 300,
          pct: 72.0,
          charging: true,
        ),
        BatterySample(
          tsSec: startSec + 15 * 1800 + 300,
          pct: 98.0,
          charging: true,
        ),
        // Discharging after charge up to now
        BatterySample(
          tsSec: nowSec - 600,
          pct: 91.0,
          charging: false,
        ),
      ];

      final built24 = buildBatteryHistorySeries(
        samples: samples,
        range: BatteryHistoryRange.h24,
        now: now,
      );
      expect(built24.series.length, 48);
      // Buckets 0..5 populated, buckets 6..13 null (gap preserved!)
      for (var i = 0; i < 6; i++) {
        expect(built24.series[i], isNotNull);
      }
      for (var i = 6; i <= 13; i++) {
        expect(built24.series[i], isNull, reason: 'bucket $i must stay null');
      }
      expect(built24.series.last, closeTo(91.0, 0.01));
      // Exactly one charge mark for the two-bucket charger session
      expect(built24.chargeMarks.length, 1);
      expect(built24.chargeMarks.first, closeTo(14 / 47, 0.03));

      final built7 = buildBatteryHistorySeries(
        samples: samples,
        range: BatteryHistoryRange.d7,
        now: now,
      );
      expect(built7.series.length, 84);

      final built30 = buildBatteryHistorySeries(
        samples: samples,
        range: BatteryHistoryRange.d30,
        now: now,
      );
      expect(built30.series.length, 120);
    });
  });

  group('LocalDb.bandBatterySamplesSince', () {
    test('returns all non-null battery_pct samples >= sinceSec without 400 cap',
        () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_battery_history_test.db';
      final dir = await databaseFactory.getDatabasesPath();
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      addTearDown(() async {
        await LocalDb.close();
        await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
      });

      final db = await LocalDb.instance;
      final baseTs = nowSec - 10 * 86400;
      final batch = db.batch();
      for (var i = 0; i < 650; i++) {
        batch.insert('band_battery', {
          'ts': baseTs + i * 900,
          'battery_pct': 100.0 - (i % 50) * 0.5,
          'charging': i == 300 ? 1 : 0,
          'source': 'test',
        });
      }
      // Also one voltage-only row with null battery_pct that should be skipped
      batch.insert('band_battery', {
        'ts': baseTs + 650 * 900,
        'battery_pct': null,
        'charging': 0,
        'millivolts': 4050,
        'source': 'event',
      });
      await batch.commit(noResult: true);

      final rows = await LocalDb.bandBatterySamplesSince(nowSec - 30 * 86400);
      expect(rows.length, 650);
      expect(rows.first.tsSec, baseTs);
      expect(rows.last.tsSec, baseTs + 649 * 900);
      expect(rows[300].charging, isTrue);
    });
  });

  group('BatteryHistoryCard and DeviceDetailView', () {
    const band = HealthSource(
      name: 'WHOOP 5.0',
      kind: 'Strap',
      icon: LucideIcons.watch,
      connected: true,
      isBand: true,
      batteryPct: 82,
      family: 'gen5',
      tier: SourceTier.wristOptical,
    );

    testWidgets('renders 24h/7d/30d tabs, drain rate, and switches range',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final samples = <BatterySample>[
        for (var i = 0; i < 12; i++)
          BatterySample(
            tsSec: nowSec - (11 - i) * 3600,
            pct: 86.0 - i * 0.35,
            charging: false,
          ),
      ];
      final forecast = BatteryForecast(
        samplesUsed: 12,
        spanUsed: const Duration(hours: 11),
        drainPctPerHour: 0.35,
        currentPct: 82.0,
        predictedPctAtWake: 79.0,
        predictedEmptyAt: now.add(const Duration(hours: 234)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: DeviceDetailView(
            band,
            batterySamples: samples,
            forecast: forecast,
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BatteryHistoryCard), findsOneWidget);
      expect(find.text('24h'), findsOneWidget);
      expect(find.text('7d'), findsOneWidget);
      expect(find.text('30d'), findsOneWidget);
      expect(find.textContaining('0.35%/hr'), findsOneWidget);
      expect(find.textContaining('8.4%/day'), findsOneWidget);

      await tester.tap(find.text('7d'));
      await tester.pumpAndSettle();
      expect(find.byType(BatteryHistoryCard), findsOneWidget);

      await tester.tap(find.text('30d'));
      await tester.pumpAndSettle();
      expect(find.byType(BatteryHistoryCard), findsOneWidget);
    });

    testWidgets('abstains honestly when charging with zero fabricated rates',
        (tester) async {
      final samples = <BatterySample>[
        BatterySample(tsSec: nowSec - 600, pct: 88.0, charging: true),
      ];
      const abstained = BatteryForecast.abstain(ForecastNote.charging);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: BatteryHistoryCard(
              samples: samples,
              forecast: abstained,
              now: now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('%/hr'), findsNothing);
      expect(find.textContaining('%/day'), findsNothing);
      expect(find.textContaining('Charging'), findsOneWidget);
    });
  });
}
