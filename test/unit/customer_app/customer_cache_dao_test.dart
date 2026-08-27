import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/database/app_migrations.dart';
import 'package:maisum/features/customer_app/data/customer_cache_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('cache is partitioned by Firebase account and can be cleared', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 26,
        singleInstance: false,
        onCreate: (db, version) => AppMigrations.migrate(
          db,
          fromVersion: 0,
          toVersion: version,
        ),
      ),
    );
    AppDatabase.instance.useForTest(db);
    final cache = CustomerCacheDao(AppDatabase.instance);
    await cache.write('uid-a', 'home', {'businesses': []});
    await cache.write('uid-b', 'home', {
      'businesses': [
        {'business_id': 'm1'}
      ]
    });

    expect((await cache.read('uid-a', 'home'))!.payload['businesses'], isEmpty);
    expect(
        (await cache.read('uid-b', 'home'))!.payload['businesses'], isNotEmpty);
    await cache.clearAccount('uid-a');
    expect(await cache.read('uid-a', 'home'), isNull);
    expect(await cache.read('uid-b', 'home'), isNotNull);
    await AppDatabase.instance.close();
  });
}
