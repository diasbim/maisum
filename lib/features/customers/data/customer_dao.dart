import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../domain/customer.dart';

class CustomerDao {
  CustomerDao(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<Customer>> search(String query) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: 'phone LIKE ? OR name LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name ASC',
      limit: 20,
    );
    return rows.map(customerFromMap).toList();
  }

  Future<Customer?> findByPhone(String phone) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: 'phone = ?',
      whereArgs: [phone],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return customerFromMap(rows.first);
  }

  Future<Customer?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return customerFromMap(rows.first);
  }

  Future<List<Customer>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('customers', orderBy: 'name ASC');
    return rows.map(customerFromMap).toList();
  }

  Future<Customer> create({required String name, required String phone}) async {
    final db = await _db.database;
    final now = DateTime.now();
    final customer = Customer(
      id: _uuid.v4(),
      name: name.isNotEmpty ? name : phone,
      phone: phone,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('customers', customer.toDbMap());
    return customer;
  }

  Future<void> updatePoints(String id, int newTotalPoints) async {
    final db = await _db.database;
    await db.update(
      'customers',
      {
        'total_points': newTotalPoints,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'customers',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getCount() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM customers');
    return result.first['count'] as int? ?? 0;
  }

  Future<List<Customer>> getUnsynced() async {
    final db = await _db.database;
    final rows =
        await db.query('customers', where: 'synced = 0', orderBy: 'created_at ASC');
    return rows.map(customerFromMap).toList();
  }
}
