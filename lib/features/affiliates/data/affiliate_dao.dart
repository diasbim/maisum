import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/affiliate.dart';
import '../domain/affiliate_code.dart';
import '../domain/merchant_affiliate_dtos.dart';
import '../domain/offline_referral.dart';

/// One provisional affiliate, as the screens read it back.
class ProvisionalAffiliate {
  const ProvisionalAffiliate({
    required this.affiliateId,
    required this.localId,
    required this.displayName,
    required this.firstName,
    required this.phone,
    required this.provisionalCode,
    required this.syncStatus,
    required this.createdAt,
    this.lastSyncError,
  });

  final String affiliateId;
  final String localId;
  final String displayName;
  final String firstName;
  final String phone;
  final String provisionalCode;
  final AffiliateSyncStatus syncStatus;
  final DateTime createdAt;
  final String? lastSyncError;

  bool get isRejected => syncStatus == AffiliateSyncStatus.rejected;
}

/// The affiliate projection SQLite holds for this business.
///
/// Every table it touches is server-owned in Firestore; nothing written here is
/// ever pushed as-is. Two kinds of row live in them:
///
///   a cache, refreshed from the API on every sync, which is what lets a till
///   price a referral during an outage; and
///
///   a provisional record, invented by this device while offline and marked as
///   such, which exists so an owner can add an affiliate without a connection
///   and is replaced by the server's answer the moment there is one.
///
/// Keeping both in the v30 tables rather than in a parallel set is deliberate:
/// the list screen, the code lookup and the reconciliation all read one place,
/// and a provisional row that was never reconciled shows up in the same query
/// as a confirmed one instead of being invisible until someone goes looking.
class AffiliateDao {
  AffiliateDao(this._database, {required this.merchantId});

  final AppDatabase _database;
  final String merchantId;

  /// Rewrites the cache of codes this business can honour offline.
  ///
  /// A full replace rather than a merge: a code that has been disabled, expired
  /// or unlinked disappears from the API answer, and a merge would leave the
  /// till still granting its discount. Provisional rows are left alone — they
  /// are not the server's to withdraw.
  Future<void> replaceActiveCodeCache(
    List<MerchantAffiliate> affiliates, {
    DateTime? now,
  }) async {
    final db = await _database.database;
    final stamp = now ?? DateTime.now();
    final stampMs = stamp.millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final keep = <String>[];
      for (final affiliate in affiliates) {
        final code = affiliate.code;
        if (code == null) continue;
        if (code.merchantId != merchantId &&
            affiliate.merchantId != merchantId) {
          continue;
        }
        if (isProvisionalAffiliateCode(code.code)) continue;

        await _upsertAffiliateIdentity(txn, affiliate, stampMs);
        await _upsertLink(txn, affiliate, stampMs);
        await _upsertCode(txn, code, stampMs);

        final normalized = code.normalizedCode.trim().toUpperCase();
        keep.add(normalized);
        await txn.insert(
          'affiliate_code_lookup_cache',
          AffiliateCodeLookupCache(
            normalizedCode: normalized,
            codeId: code.id,
            merchantId: merchantId,
            affiliateId: affiliate.id,
            code: code.code,
            status: code.status,
            benefitType: code.benefitType,
            benefitValue: code.benefitValue,
            startsAt: code.startsAt,
            expiresAt: code.expiresAt,
            usageLimit: code.usageLimit,
            usageCount: code.usageCount,
            firstVisitOnly: code.firstVisitOnly,
            cachedAt: stamp,
            updatedAt: code.updatedAt ?? stamp,
            affiliateDisplayName: affiliate.name,
            affiliateFirstName: affiliate.firstName,
            affiliateStatus: affiliate.status.storageValue,
            linkStatus: affiliate.linkStatus.storageValue,
            refreshedAt: stamp,
          ).toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (keep.isEmpty) {
        await txn.delete(
          'affiliate_code_lookup_cache',
          where: 'merchant_id = ?',
          whereArgs: [merchantId],
        );
        return;
      }
      final placeholders = List.filled(keep.length, '?').join(', ');
      await txn.delete(
        'affiliate_code_lookup_cache',
        where: 'merchant_id = ? AND normalized_code NOT IN ($placeholders)',
        whereArgs: [merchantId, ...keep],
      );
    });
  }

  /// The cached terms for a typed code, or null when this till has never been
  /// told about it.
  Future<AffiliateCodeLookupCache?> findCachedCode(
      String normalizedCode) async {
    final code = normalizedCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    final db = await _database.database;
    final rows = await db.query(
      'affiliate_code_lookup_cache',
      where: 'merchant_id = ? AND normalized_code = ?',
      whereArgs: [merchantId, code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AffiliateCodeLookupCache.fromMap(rows.first);
  }

  Future<int> cachedCodeCount() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM affiliate_code_lookup_cache '
      'WHERE merchant_id = ?',
      [merchantId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  /// Writes the local affiliate, the link and the one provisional code.
  ///
  /// All three in one transaction because a link with no code cannot be worked
  /// with and an affiliate with no link is not this business's. The caller
  /// queues the authoritative operation in the same transaction, which is what
  /// makes "the row exists" and "the server will be asked" one fact.
  Future<void> insertProvisionalAffiliate(
    DatabaseExecutor txn, {
    required String affiliateId,
    required String localId,
    required String phoneE164,
    required String normalizedPhone,
    required String firstName,
    required String? lastName,
    required String displayName,
    required String provisionalCode,
    required ReferralBenefitType benefitType,
    required double benefitValue,
    required int? usageLimit,
    required bool firstVisitOnly,
    required DateTime? expiresAt,
    required DateTime now,
  }) async {
    final nowMs = now.millisecondsSinceEpoch;
    await txn.insert('affiliates', {
      'id': affiliateId,
      'phone': phoneE164,
      'normalized_phone': normalizedPhone,
      'first_name': firstName,
      'last_name': lastName,
      'display_name': displayName,
      'status': 'ACTIVE',
      'created_at': nowMs,
      'updated_at': nowMs,
      'synced': 0,
      'provisional': 1,
      'local_id': localId,
      'sync_status': AffiliateSyncStatus.pending.storageValue,
      'last_sync_error': null,
    });
    await txn.insert('affiliate_merchants', {
      'id': 'aml_$localId',
      'merchant_id': merchantId,
      'affiliate_id': affiliateId,
      'status': 'ACTIVE',
      'linked_at': nowMs,
      'created_at': nowMs,
      'updated_at': nowMs,
      'synced': 0,
      'provisional': 1,
      'local_id': localId,
      'sync_status': AffiliateSyncStatus.pending.storageValue,
    });
    await txn.insert('affiliate_codes', {
      'id': 'acl_$localId',
      'merchant_id': merchantId,
      'affiliate_id': affiliateId,
      'code': provisionalCode,
      'normalized_code': provisionalCode,
      'benefit_type': benefitType.storageValue,
      'benefit_value': benefitValue,
      'starts_at': nowMs,
      'expires_at': expiresAt?.millisecondsSinceEpoch,
      'usage_limit': usageLimit,
      'usage_count': 0,
      'first_visit_only': firstVisitOnly ? 1 : 0,
      'status': 'ACTIVE',
      'created_at': nowMs,
      'updated_at': nowMs,
      'synced': 0,
      'provisional': 1,
      'local_id': localId,
      'sync_status': AffiliateSyncStatus.pending.storageValue,
    });
  }

  /// The affiliates this device invented and the server has not answered for.
  Future<List<ProvisionalAffiliate>> provisionalAffiliates() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT a.id AS affiliate_id,
             a.local_id AS local_id,
             a.display_name AS display_name,
             a.first_name AS first_name,
             a.phone AS phone,
             a.sync_status AS sync_status,
             a.last_sync_error AS last_sync_error,
             a.created_at AS created_at,
             c.code AS code
      FROM affiliates a
      JOIN affiliate_merchants m ON m.affiliate_id = a.id
      LEFT JOIN affiliate_codes c
        ON c.affiliate_id = a.id AND c.merchant_id = m.merchant_id
      WHERE m.merchant_id = ? AND a.provisional = 1
      ORDER BY a.created_at ASC
      ''',
      [merchantId],
    );
    return rows
        .map(
          (row) => ProvisionalAffiliate(
            affiliateId: row['affiliate_id'] as String,
            localId:
                (row['local_id'] as String?) ?? row['affiliate_id'] as String,
            displayName: (row['display_name'] as String?) ?? '',
            firstName: (row['first_name'] as String?) ?? '',
            phone: (row['phone'] as String?) ?? '',
            provisionalCode: (row['code'] as String?) ?? '',
            syncStatus: AffiliateSyncStatus.fromStorage(row['sync_status']) ??
                AffiliateSyncStatus.pending,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              (row['created_at'] as num?)?.toInt() ?? 0,
            ),
            lastSyncError: row['last_sync_error'] as String?,
          ),
        )
        .toList(growable: false);
  }

  /// Replaces a provisional affiliate with the record the server minted.
  ///
  /// The old rows are deleted rather than updated because the server's id is
  /// derived from the phone and is almost never the local one; an update would
  /// leave the local id in place and let the next list show the person twice.
  /// Any queued operation still naming the local id is rewritten by the sync
  /// service's canonical reconciliation.
  Future<void> reconcileProvisionalAffiliate(
    DatabaseExecutor txn, {
    required String localAffiliateId,
    required MerchantAffiliate canonical,
    required DateTime now,
  }) async {
    final nowMs = now.millisecondsSinceEpoch;
    final code = canonical.code;

    if (localAffiliateId != canonical.id) {
      await txn.delete(
        'affiliate_codes',
        where: 'merchant_id = ? AND affiliate_id = ?',
        whereArgs: [merchantId, localAffiliateId],
      );
      await txn.delete(
        'affiliate_merchants',
        where: 'merchant_id = ? AND affiliate_id = ?',
        whereArgs: [merchantId, localAffiliateId],
      );
      final stillLinked = await txn.query(
        'affiliate_merchants',
        columns: const ['id'],
        where: 'affiliate_id = ?',
        whereArgs: [localAffiliateId],
        limit: 1,
      );
      if (stillLinked.isEmpty) {
        await txn.delete(
          'affiliates',
          where: 'id = ?',
          whereArgs: [localAffiliateId],
        );
      }
    }

    await _upsertAffiliateIdentity(txn, canonical, nowMs, confirmed: true);
    await _upsertLink(txn, canonical, nowMs, confirmed: true);
    if (code != null) {
      await _upsertCode(txn, code, nowMs, confirmed: true);
      await txn.insert(
        'affiliate_code_lookup_cache',
        AffiliateCodeLookupCache(
          normalizedCode: code.normalizedCode.trim().toUpperCase(),
          codeId: code.id,
          merchantId: merchantId,
          affiliateId: canonical.id,
          code: code.code,
          status: code.status,
          benefitType: code.benefitType,
          benefitValue: code.benefitValue,
          startsAt: code.startsAt,
          expiresAt: code.expiresAt,
          usageLimit: code.usageLimit,
          usageCount: code.usageCount,
          firstVisitOnly: code.firstVisitOnly,
          cachedAt: now,
          updatedAt: code.updatedAt ?? now,
          affiliateDisplayName: canonical.name,
          affiliateFirstName: canonical.firstName,
          affiliateStatus: canonical.status.storageValue,
          linkStatus: canonical.linkStatus.storageValue,
          refreshedAt: now,
        ).toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Records that the server refused to register a provisional affiliate.
  ///
  /// The row stays. An owner who added someone offline has to be able to see
  /// what happened to them, and deleting the record would make a failed create
  /// indistinguishable from one that was never attempted.
  Future<void> markProvisionalAffiliateRejected(
    DatabaseExecutor txn, {
    required String localAffiliateId,
    required String? reason,
    required DateTime now,
  }) async {
    final patch = {
      'sync_status': AffiliateSyncStatus.rejected.storageValue,
      'last_sync_error': reason,
      'updated_at': now.millisecondsSinceEpoch,
    };
    await txn.update(
      'affiliates',
      patch,
      where: 'id = ? AND provisional = 1',
      whereArgs: [localAffiliateId],
    );
    await txn.update(
      'affiliate_merchants',
      patch,
      where: 'merchant_id = ? AND affiliate_id = ? AND provisional = 1',
      whereArgs: [merchantId, localAffiliateId],
    );
    await txn.update(
      'affiliate_codes',
      patch,
      where: 'merchant_id = ? AND affiliate_id = ? AND provisional = 1',
      whereArgs: [merchantId, localAffiliateId],
    );
  }

  /// Writes an attribution exactly as the server reported it.
  ///
  /// Keyed by the server's id, so a replay of the same reconciliation converges
  /// instead of adding a second acquisition, and `REJECTED` survives a restart
  /// because it is a row rather than a flag on an in-memory result.
  Future<void> ensureAttributionReferences(
    DatabaseExecutor txn,
    Map<String, dynamic> referral,
    Map<String, dynamic> attribution, {
    required DateTime now,
  }) async {
    final affiliateId = _string(attribution, ['affiliate_id', 'affiliateId']);
    final codeId =
        _string(attribution, ['affiliate_code_id', 'affiliateCodeId']);
    if (affiliateId == null || codeId == null) return;

    final status =
        (_string(attribution, ['status']) ?? 'REJECTED').toUpperCase();
    final confirmed = status == 'CONFIRMED';
    final displayName =
        _string(referral, ['affiliate_name', 'affiliateName']) ?? 'Afiliado';
    final firstName = displayName.split(RegExp(r'\s+')).first;
    final nowMs = now.millisecondsSinceEpoch;
    final affiliate = MerchantAffiliate(
      id: affiliateId,
      merchantId: merchantId,
      name: displayName,
      firstName: firstName,
      status: confirmed ? AffiliateStatus.active : AffiliateStatus.inactive,
      linkStatus: confirmed
          ? AffiliateMerchantStatus.active
          : AffiliateMerchantStatus.inactive,
      createdAt: now,
      updatedAt: now,
    );

    final existingAffiliate = await txn.query(
      'affiliates',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [affiliateId],
      limit: 1,
    );
    if (existingAffiliate.isEmpty) {
      await _upsertAffiliateIdentity(txn, affiliate, nowMs);
    }

    final existingLink = await txn.query(
      'affiliate_merchants',
      columns: const ['id'],
      where: 'merchant_id = ? AND affiliate_id = ?',
      whereArgs: [merchantId, affiliateId],
      limit: 1,
    );
    if (existingLink.isEmpty) {
      await _upsertLink(txn, affiliate, nowMs);
    }

    final existingCode = await txn.query(
      'affiliate_codes',
      columns: const ['id'],
      where: 'id = ? AND merchant_id = ?',
      whereArgs: [codeId, merchantId],
      limit: 1,
    );
    if (existingCode.isNotEmpty) return;

    final benefitRaw = referral['benefit'];
    final benefit = benefitRaw is Map
        ? benefitRaw.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final typeValue =
        (_string(benefit, ['type', 'benefit_type']) ?? 'FIXED_AMOUNT')
            .toUpperCase();
    final benefitType = ReferralBenefitType.values.firstWhere(
      (type) => type.storageValue == typeValue,
      orElse: () => ReferralBenefitType.fixedAmount,
    );
    final normalizedCode =
        (_string(referral, ['normalized_code', 'normalizedCode']) ??
                'SERVER-$codeId')
            .toUpperCase();
    await _upsertCode(
      txn,
      MerchantAffiliateCode(
        id: codeId,
        merchantId: merchantId,
        affiliateId: affiliateId,
        code: normalizedCode,
        normalizedCode: normalizedCode,
        benefitType: benefitType,
        benefitValue: _double(benefit, ['value', 'benefit_value']) ?? 1,
        status: confirmed
            ? AffiliateCodeStatus.active
            : AffiliateCodeStatus.disabled,
        createdAt: now,
        updatedAt: now,
      ),
      nowMs,
    );
  }

  Future<void> upsertAttribution(
    DatabaseExecutor txn,
    Map<String, dynamic> attribution, {
    required DateTime now,
  }) async {
    final id = _string(attribution, ['id']);
    final affiliateId = _string(attribution, ['affiliate_id', 'affiliateId']);
    final codeId =
        _string(attribution, ['affiliate_code_id', 'affiliateCodeId']);
    final customerId = _string(attribution, ['customer_id', 'customerId']);
    if (id == null ||
        affiliateId == null ||
        codeId == null ||
        customerId == null) {
      return;
    }
    final status =
        (_string(attribution, ['status']) ?? 'CONFIRMED').toUpperCase();
    final saleId = _string(attribution, [
      'qualifying_sale_id',
      'first_sale_id',
      'firstSaleId',
    ]);
    final nowMs = now.millisecondsSinceEpoch;

    // The v30 schema keeps one non-rejected attribution per customer. A
    // confirmed one replacing a rejected one must remove the old row first or
    // the partial unique index refuses the write.
    if (status != 'REJECTED') {
      await txn.delete(
        'affiliate_attributions',
        where:
            'merchant_id = ? AND customer_id = ? AND id != ? AND status != ?',
        whereArgs: [merchantId, customerId, id, 'REJECTED'],
      );
    }

    await txn.insert(
      'affiliate_attributions',
      {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'affiliate_code_id': codeId,
        'customer_id': customerId,
        'qualifying_sale_id': saleId,
        'status': status,
        'rejection_code': _string(attribution, [
          'rejection_code',
          'rejection_reason',
          'rejectionReason',
        ]),
        'attributed_at':
            _int(attribution, ['attributed_at', 'attributedAt']) ?? nowMs,
        'first_sale_at': _int(attribution, ['first_sale_at', 'firstSaleAt']),
        'created_at': _int(attribution, ['created_at', 'createdAt']) ?? nowMs,
        'updated_at': _int(attribution, ['updated_at', 'updatedAt']) ?? nowMs,
        'synced': 1,
        'idempotency_key':
            _string(attribution, ['idempotency_key', 'idempotencyKey']),
        'sync_status': AffiliateSyncStatus.synced.storageValue,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertReward(
    DatabaseExecutor txn,
    Map<String, dynamic> reward, {
    required DateTime now,
  }) async {
    final id = _string(reward, ['id']);
    final affiliateId = _string(reward, ['affiliate_id', 'affiliateId']);
    final attributionId = _string(reward, ['attribution_id', 'attributionId']);
    if (id == null || affiliateId == null || attributionId == null) return;
    final nowMs = now.millisecondsSinceEpoch;

    await txn.insert(
      'affiliate_rewards',
      {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'attribution_id': attributionId,
        'reward_type': (_string(reward, ['reward_type', 'type']) ??
                'FIRST_QUALIFYING_SALE')
            .toUpperCase(),
        'value_type': (_string(reward, ['value_type', 'valueType']) ?? 'POINTS')
            .toUpperCase(),
        'reward_value': _double(reward, ['reward_value', 'value']) ?? 0,
        'status': (_string(reward, ['status']) ?? 'PENDING').toUpperCase(),
        'approval_required':
            _bool(reward, ['approval_required', 'approvalRequired']) ? 1 : 0,
        'source_sale_id': _string(reward, [
          'source_sale_id',
          'trigger_sale_id',
          'triggerSaleId',
        ]),
        'approved_at': _int(reward, ['approved_at', 'approvedAt']),
        'approved_by_app_user_id':
            _string(reward, ['approved_by_app_user_id', 'approved_by']),
        'cancelled_at': _int(reward, ['cancelled_at', 'cancelledAt']),
        'paid_at': _int(reward, ['paid_at', 'paidAt']),
        'created_at': _int(reward, ['created_at', 'createdAt']) ?? nowMs,
        'updated_at': _int(reward, ['updated_at', 'updatedAt']) ?? nowMs,
        'synced': 1,
        'idempotency_key':
            _string(reward, ['idempotency_key', 'idempotencyKey']),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Appends one affiliate event, ignoring a repeat of the same id.
  ///
  /// Events are append-only by contract, so a replay that tried to replace one
  /// would rewrite history that the metrics screen has already counted.
  Future<void> insertEventIfAbsent(
    DatabaseExecutor txn,
    Map<String, dynamic> event, {
    required DateTime now,
  }) async {
    final id = _string(event, ['id']);
    final affiliateId = _string(event, ['affiliate_id', 'affiliateId']);
    final eventType = _string(event, ['event_type', 'eventType']);
    if (id == null || affiliateId == null || eventType == null) return;
    final nowMs = now.millisecondsSinceEpoch;

    await txn.insert(
      'affiliate_events',
      {
        'id': id,
        'merchant_id': merchantId,
        'affiliate_id': affiliateId,
        'event_type': eventType.toUpperCase(),
        'attribution_id': _string(event, ['attribution_id', 'attributionId']),
        'reward_id': _string(event, ['reward_id', 'rewardId']),
        'sale_id': _string(event, ['sale_id', 'saleId']),
        'customer_id': _string(event, ['customer_id', 'customerId']),
        'payload': _string(event, ['payload']),
        'occurred_at':
            _int(event, ['occurred_at', 'created_at', 'occurredAt']) ?? nowMs,
        'created_at': _int(event, ['created_at', 'createdAt']) ?? nowMs,
        'schema_version': _int(event, ['schema_version']) ?? 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, Object?>>> attributionsForCustomer(
    String customerId,
  ) async {
    final db = await _database.database;
    return db.query(
      'affiliate_attributions',
      where: 'merchant_id = ? AND customer_id = ?',
      whereArgs: [merchantId, customerId],
      orderBy: 'updated_at DESC',
    );
  }

  Future<void> _upsertAffiliateIdentity(
    DatabaseExecutor txn,
    MerchantAffiliate affiliate,
    int nowMs, {
    bool confirmed = true,
  }) async {
    // `normalized_phone` is uniquely indexed and the API withholds the number
    // from callers who may not see it. Falling back to the affiliate's own id
    // keeps the index honest without inventing a phone number that would then
    // be shown to somebody.
    final phone = affiliate.phone?.trim();
    final normalizedPhone = phone == null || phone.isEmpty
        ? 'id:${affiliate.id}'
        : phone.replaceAll(RegExp(r'[^0-9]'), '');
    final row = {
      'id': affiliate.id,
      'phone': phone ?? '',
      'normalized_phone': normalizedPhone,
      'first_name': affiliate.firstName,
      'last_name': affiliate.lastName,
      'display_name': affiliate.name,
      'status': affiliate.status.storageValue,
      'created_at': affiliate.createdAt?.millisecondsSinceEpoch ?? nowMs,
      'updated_at': affiliate.updatedAt?.millisecondsSinceEpoch ?? nowMs,
      'synced': confirmed ? 1 : 0,
      'provisional': 0,
      'sync_status': confirmed ? AffiliateSyncStatus.synced.storageValue : null,
      'last_sync_error': null,
    };
    final updated = await txn.update(
      'affiliates',
      row,
      where: 'id = ?',
      whereArgs: [affiliate.id],
    );
    if (updated == 0) {
      await txn.insert(
        'affiliates',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _upsertLink(
    DatabaseExecutor txn,
    MerchantAffiliate affiliate,
    int nowMs, {
    bool confirmed = true,
  }) async {
    final existing = await txn.query(
      'affiliate_merchants',
      columns: const ['id'],
      where: 'merchant_id = ? AND affiliate_id = ?',
      whereArgs: [merchantId, affiliate.id],
      limit: 1,
    );
    final id = existing.isEmpty
        ? 'am_${affiliate.id}'
        : existing.first['id'] as String;
    final row = {
      'id': id,
      'merchant_id': merchantId,
      'affiliate_id': affiliate.id,
      'status': affiliate.linkStatus.storageValue,
      'linked_at': affiliate.linkedAt?.millisecondsSinceEpoch ?? nowMs,
      'created_at': affiliate.createdAt?.millisecondsSinceEpoch ?? nowMs,
      'updated_at': affiliate.updatedAt?.millisecondsSinceEpoch ?? nowMs,
      'synced': confirmed ? 1 : 0,
      'provisional': 0,
      'sync_status': confirmed ? AffiliateSyncStatus.synced.storageValue : null,
      'last_sync_error': null,
    };
    await txn.insert(
      'affiliate_merchants',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertCode(
    DatabaseExecutor txn,
    MerchantAffiliateCode code,
    int nowMs, {
    bool confirmed = true,
  }) async {
    // v30 keeps one code per affiliate–merchant pair and one row per
    // normalised code globally. A confirmed code replacing a provisional one
    // has to take both slots, so anything else holding them goes first.
    await txn.delete(
      'affiliate_codes',
      where: 'merchant_id = ? AND affiliate_id = ? AND id != ?',
      whereArgs: [merchantId, code.affiliateId, code.id],
    );
    await txn.delete(
      'affiliate_codes',
      where: 'normalized_code = ? AND id != ?',
      whereArgs: [code.normalizedCode.trim().toUpperCase(), code.id],
    );
    await txn.insert(
      'affiliate_codes',
      {
        'id': code.id,
        'merchant_id': merchantId,
        'affiliate_id': code.affiliateId,
        'code': code.code,
        'normalized_code': code.normalizedCode.trim().toUpperCase(),
        'benefit_type': code.benefitType.storageValue,
        'benefit_value': code.benefitValue,
        'starts_at': code.startsAt?.millisecondsSinceEpoch,
        'expires_at': code.expiresAt?.millisecondsSinceEpoch,
        'usage_limit': code.usageLimit,
        'usage_count': code.usageCount,
        'first_visit_only': code.firstVisitOnly ? 1 : 0,
        'status': code.status.storageValue,
        'created_at': code.createdAt?.millisecondsSinceEpoch ?? nowMs,
        'updated_at': code.updatedAt?.millisecondsSinceEpoch ?? nowMs,
        'synced': confirmed ? 1 : 0,
        'provisional': 0,
        'sync_status':
            confirmed ? AffiliateSyncStatus.synced.storageValue : null,
        'last_sync_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

String? _string(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

int? _int(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? _double(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool _bool(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
  }
  return true;
}
