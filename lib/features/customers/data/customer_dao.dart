import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/moz_phone_utils.dart';
import '../domain/customer.dart';

class CustomerDao {
  CustomerDao(this._db, {required this.merchantId});

  CustomerDao.unscoped(this._db) : merchantId = null;

  final AppDatabase _db;
  final String? merchantId;
  static const _uuid = Uuid();

  Future<List<Customer>> search(String query) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope(
        '(phone LIKE ? OR name LIKE ?) AND archived_at IS NULL',
      ),
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
        '${isPhoneSearch ? 'phone LIKE ?' : 'name LIKE ? COLLATE NOCASE'} '
        'AND archived_at IS NULL',
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

  Future<Customer?> findByCanonicalCustomerId(
      String canonicalCustomerId) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('canonical_customer_id = ?'),
      whereArgs: _withMerchantArgs([canonicalCustomerId]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return customerFromMap(rows.first);
  }

  /// Local read cache only: looks up a customer by the last NFC card UID
  /// resolved for this merchant. The backend (customer_nfc_cards) remains
  /// the source of truth; this enables fast offline recognition of repeat
  /// taps but must not be relied on for authorization decisions.
  Future<Customer?> findByNfcCardUid(String cardUid) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('nfc_card_uid = ? AND archived_at IS NULL'),
      whereArgs: _withMerchantArgs([cardUid]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return customerFromMap(rows.first);
  }

  Future<List<Customer>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('archived_at IS NULL'),
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'name ASC',
    );
    return rows.map(customerFromMap).toList();
  }

  Future<List<Customer>> getArchived() async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('archived_at IS NOT NULL'),
      whereArgs: merchantId == null ? null : [merchantId],
      orderBy: 'archived_at DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(customerFromMap).toList();
  }

  Future<List<Customer>> getRecent({int limit = 6}) async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: _withMerchantScope('archived_at IS NULL'),
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
      merchantId: merchantId,
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

  Future<void> updateConsent(
    String id, {
    required CustomerConsentStatus marketing,
    required CustomerConsentStatus whatsapp,
  }) async {
    final db = await _db.database;
    final updated = await db.update(
      'customers',
      {
        'marketing_consent_status': marketing.storageValue,
        'whatsapp_consent_status': whatsapp.storageValue,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
      },
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
    if (updated != 1) {
      throw StateError('Customer not found in the active merchant');
    }
  }

  Future<Customer> setArchived(
    String id, {
    required bool archived,
    required String? appUserId,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final updated = await db.update(
      'customers',
      {
        'archived_at': archived ? now.millisecondsSinceEpoch : null,
        'archived_by_app_user_id': archived ? appUserId : null,
        'updated_at': now.millisecondsSinceEpoch,
        'synced': 0,
      },
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([id]),
    );
    if (updated != 1) {
      throw StateError('Customer not found in the active merchant');
    }
    final customer = await getById(id);
    if (customer == null) {
      throw StateError('Customer not found after archive update');
    }
    return customer;
  }

  /// Caches the resolved NFC card UID on the local customer row (see
  /// [findByNfcCardUid]). Clearing an existing UID from another customer at
  /// this merchant first avoids the unique index rejecting a reassignment
  /// after the backend confirms a card was moved (e.g. reissued).
  Future<void> setNfcCardUidCache(String customerId, String? cardUid) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      if (cardUid != null) {
        await txn.update(
          'customers',
          {'nfc_card_uid': null},
          where: _withMerchantScope('nfc_card_uid = ? AND id != ?'),
          whereArgs: _withMerchantArgs([cardUid, customerId]),
        );
      }
      final updated = await txn.update(
        'customers',
        {
          'nfc_card_uid': cardUid,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: _withMerchantScope('id = ?'),
        whereArgs: _withMerchantArgs([customerId]),
      );
      if (updated != 1) {
        throw StateError('Customer not found in the active merchant');
      }
    });
  }

  /// Upserts a customer record that is already authoritative on the
  /// backend (e.g. resolved via an NFC card tap that auto-created the
  /// business customer server-side on first visit). Marked as synced since
  /// the server is the source of truth for this data. Reuses an existing
  /// local row by id or by phone instead of blindly overwriting, to avoid
  /// orphaning sales/history tied to a pre-existing local customer id.
  Future<Customer> upsertFromServer(Customer customer) async {
    final db = await _db.database;
    final existingById = await getById(customer.id);
    if (existingById != null) {
      await db.update(
        'customers',
        {
          'name': customer.name,
          'phone': customer.phone,
          'total_points': customer.totalPoints,
          'canonical_customer_id': customer.canonicalCustomerId,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'synced': 1,
        },
        where: _withMerchantScope('id = ?'),
        whereArgs: _withMerchantArgs([customer.id]),
      );
      return (await getById(customer.id))!;
    }

    final existingByPhone = await findByPhone(customer.phone);
    if (existingByPhone != null) {
      // A local record already represents this phone under a different
      // (locally created) id; reuse it instead of inserting a duplicate.
      return existingByPhone;
    }

    await db.insert('customers', customer.copyWith(synced: true).toDbMap());
    final saved = await getById(customer.id);
    if (saved == null) {
      throw StateError('Customer not found after server upsert');
    }
    return saved;
  }

  Future<Map<String, int>> getDeleteDependencies(String id) async {
    final db = await _db.database;
    const tables = <String>[
      'sales',
      'redemptions',
      'appointments',
      'retention_metrics',
      'customer_risk_scores',
      'recovery_tasks',
      'recovery_actions',
      'visit_reports',
      'survey_responses',
      'loyalty_ledger',
      'redemption_requests',
    ];
    final counts = <String, int>{};
    for (final table in tables) {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $table WHERE customer_id = ?',
        [id],
      );
      final count = (rows.first['count'] as num?)?.toInt() ?? 0;
      if (count > 0) counts[table] = count;
    }
    return counts;
  }

  Future<void> deletePermanently(String id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      const tables = <String>[
        'sales',
        'redemptions',
        'appointments',
        'retention_metrics',
        'customer_risk_scores',
        'recovery_tasks',
        'recovery_actions',
        'visit_reports',
        'survey_responses',
        'loyalty_ledger',
        'redemption_requests',
      ];
      for (final table in tables) {
        final rows = await txn.rawQuery(
          'SELECT 1 FROM $table WHERE customer_id = ? LIMIT 1',
          [id],
        );
        if (rows.isNotEmpty) {
          throw StateError('Customer has dependent records in $table');
        }
      }
      final deleted = await txn.delete(
        'customers',
        where: _withMerchantScope('id = ?'),
        whereArgs: _withMerchantArgs([id]),
      );
      if (deleted != 1) {
        throw StateError('Customer not found in the active merchant');
      }
    });
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
          ? 'SELECT COUNT(*) as count FROM customers WHERE archived_at IS NULL'
          : 'SELECT COUNT(*) as count FROM customers '
              'WHERE merchant_id = ? AND archived_at IS NULL',
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
