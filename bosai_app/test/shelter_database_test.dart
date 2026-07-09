import 'dart:io';

import 'package:bosai_app/db/shelter_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = File('assets/shelters.db').absolute.path;

  test('GSI shelters.db can be opened and queried', () async {
    final db = await ShelterDatabase.open(databasePath: dbPath);

    expect(await db.countAll(), 2179);
    expect(await db.countEarthquake(), 632);

    final edogawa = await db.queryByCityCode('13123', limit: 5);
    expect(edogawa, isNotEmpty);
    expect(edogawa.first.cityCode, '13123');
  });
}
