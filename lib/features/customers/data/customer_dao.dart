import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/moz_phone_utils.dart';
import '../domain/customer.dart';

class CustomerDao {
  CustomerDao(this._db, {this.merchantId});

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();

  Future<List<Customer>> search(String query) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('phone LIKE ? OR name LIKE ?'),
      whereArgs: _withMerchantArgs(['%$query%', '%$query%']),
      orderBy: 'name ASC',
      limit: 20,
    );
    return rows.map(customerFromMap).toList();
  }

  Future<List<Customer>> searchForSale(String query) async {
    final db = await _db.database;
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      return const <Customer>[];
    }

    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    final isPhoneSearch =
        digitsOnly.isNotEmpty && digitsOnly.length == trimmed.length;
    final normalizedPhoneQuery = _normalizeSearchDigits(digitsOnly);

    final rows = await db.query(
      'customers',
      where: _withMerchantScope(
        isPhoneSearch ? 'phone LIKE ?' : 'name LIKE ? COLLATE NOCASE',
      ),
      whereArgs: _withMerchantArgs([
        '${isPhoneSearch ? normalizedPhoneQuery : trimmed}%',
      ]),
      orderBy: 'name COLLATE NOCASE ASC',
      limit: 20,
    );
    return rows.map(customerFromMap).toList();
  }

  String _normalizeSearchDigits(String digitsOnly) {
    if (digitsOnly.length == 12 && digitsOnly.startsWith('258')) {
      return digitsOnly.substring(3);
    }
    if (digitsOnly.length == 13 && digitsOnly.startsWith('0258')) {
      return digitsOnly.substring(4);
    }
    return digitsOnly;
  }

  Future<Customer?> findByPhone(String phone) async {
    String normalizedPhone;
    try {
      normalizedPhone = MozPhoneUtils.normalizeToLocal(phone);
    } on FormatException {
      return null;
    }
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('phone = ?'),
      whereArgs: _withMerchantArgs([normalizedPhone]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return customerFromMap(rows.first);
  }

  Future<Customer?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return customerFromMap(rows.first);
  }

  Future<List<Customer>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: merchantId == null ? null : 'merchant_id = ?',
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'name ASC',
    );
    return rows.map(customerFromMap).toList();
  }

  Future<List<Customer>> getRecent({int limit = 6}) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: merchantId == null ? null : 'merchant_id = ?',
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'updated_at DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(customerFromMap).toList();
  }

  Future<Customer> create({required String name, required String phone}) async {
    final db = await _db.database;
    final now = DateTime.now();
    final normalizedPhone = MozPhoneUtils.normalizeToLocal(phone);
    final customer = Customer(
      id: _uuid.v4(),
      name: name.isNotEmpty ? name : phone,
      phone: normalizedPhone,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('customers', {
      ...customer.toDbMap(),
      'merchant_id': merchantId,
    });
    return customer;
  }

  Future<void> updatePoints(String id, int newTotalPoints) async {
    final db = await _db.database;
    await db.update(
      'customers',
      {
        'total_points': newTotalPoints,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
      },
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
  }

  Future<void> update(
    String id, {
    required String name,
    required String phone,
  }) async {
    final db = await _db.database;
    final normalizedPhone = MozPhoneUtils.normalizeToLocal(phone);
    await db.update(
      'customers',
      {
        'name': name,
        'phone': normalizedPhone,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
      },
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
  }

  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      'customers',
      {'synced': 1},
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
  }

  Future<int> getCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) as count FROM customers'
          : 'SELECT COUNT(*) as count FROM customers WHERE merchant_id = ?',
      merchantId == null ? const [] : [merchantId],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<Customer>> getUnsynced() async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('synced = 0'),
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'created_at ASC',
    );
    return rows.map(customerFromMap).toList();
  }

  String _withMerchantScope(String clause) {
    if (merchantId == null) {
      return clause;
    }
    return 'merchant_id = ? AND ($clause)';
  }

  List<Object?> _withMerchantArgs(List<Object?> args) {
    if (merchantId == null) {
      return args;
    }
    return [merchantId, ...args];
  }
}
