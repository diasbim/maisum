import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/points_calculator.dart';
import '../../catalog/domain/merchant_item.dart';
import '../../customers/domain/customer.dart';
import '../../sales/data/sale_item_dao.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_item.dart';
import '../../sync/data/sync_projection.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/affiliate_code.dart';
import '../domain/merchant_affiliate_dtos.dart';
import '../domain/offline_referral.dart';
import '../domain/referral_validation.dart';
import '../services/referral_copy.dart';
import 'affiliate_dao.dart';
import 'affiliate_repository.dart';
import 'affiliate_sale_api.dart';

/// The queue operation types this feature owns.
const String affiliateSyncEntityType = 'affiliate';
const String referralSaleSyncEntityType = 'referral_sale';

/// What the till decided offline, and what it wrote down.
class OfflineReferralSaleResult {
  const OfflineReferralSaleResult({
    required this.sale,
    required this.customer,
    required this.decision,
  });

  final Sale sale;
  final Customer customer;
  final OfflineReferralDecision decision;

  bool get benefitApplied => decision.appliesBenefit;
}

/// What the screens are allowed to ask of the offline path.
///
/// Narrower than [AffiliateLocalRepository] on purpose: a screen has no
/// business projecting a sync answer or refreshing a cache, and a test that
/// wants to say "this till has this code" should not have to stand up SQLite
/// inside a widget pump to say it.
abstract interface class AffiliateOfflineGateway {
  /// What a typed code is worth here and now, from this device's cache alone.
  Future<OfflineReferralDecision> previewOfflineReferral({
    required String code,
    required double grossAmount,
    required bool customerIsNew,
    String? customerPhoneE164,
  });

  /// Writes the sale and queues the one authoritative operation for it.
  Future<OfflineReferralSaleResult> recordOfflineReferralSale({
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    required String localSaleId,
    List<SaleItemInput> items,
    OfflineReferralDecision? decision,
  });

  /// Registers an affiliate locally and queues the real registration.
  Future<ProvisionalAffiliate> createAffiliateOffline(AffiliateDraft draft);

  /// The affiliates still waiting to be registered, or refused.
  Future<List<ProvisionalAffiliate>> provisionalAffiliates();
}

/// Everything the app does about affiliates without a server.
///
/// Three jobs, and they are one class because they are one decision seen from
/// three sides: what this device is allowed to believe about a code it has not
/// just checked.
///
///   It keeps a cache of the business's live codes, refreshed on every sync, so
///   a sale during an outage can be priced from terms the server published
///   rather than from terms a cashier typed.
///
///   It writes a sale that carried a code as one local row with one queued
///   authoritative operation â€” never an ordinary sale plus a second referral
///   record, which would be two purchases for one basket.
///
///   It projects the server's answer back over both, including the answers
///   nobody wants: a code that was refused after the discount was already given
///   keeps the discount, records the refusal, and pays the affiliate nothing.
///
/// What it never does is decide a referral succeeded. Attribution and reward
/// are the server's, and every local row this writes says so until the queue
/// has been told otherwise.
class AffiliateLocalRepository
    implements SyncProjection, AffiliateOfflineGateway {
  AffiliateLocalRepository(
    this._database,
    this._dao, {
    required this.merchantId,
    required this.deviceId,
    this.appUserId,
    AffiliateGateway? gateway,
    SaleItemDao? saleItemDao,
    int pointsPerMzn = 100,
    DateTime Function()? clock,
  })  : _gateway = gateway,
        _saleItemDao =
            saleItemDao ?? SaleItemDao(_database, merchantId: merchantId),
        _points = PointsCalculator(pointsPerMzn: pointsPerMzn),
        _clock = clock ?? DateTime.now {
    if (merchantId.trim().isEmpty) {
      throw ArgumentError.value(merchantId, 'merchantId', 'must not be empty');
    }
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'must not be empty');
    }
  }

  final AppDatabase _database;
  final AffiliateDao _dao;
  final AffiliateGateway? _gateway;
  final SaleItemDao _saleItemDao;
  final PointsCalculator _points;
  final DateTime Function() _clock;
  final String merchantId;
  final String deviceId;
  final String? appUserId;

  static const _uuid = Uuid();

  AffiliateDao get dao => _dao;

  @override
  Set<String> get entityTypes =>
      const {affiliateSyncEntityType, referralSaleSyncEntityType};

  /* ------------------------------------------------------------- code cache */

  @override
  Future<void> refreshReadCaches() => refreshActiveCodeCache();

  /// Pulls the business's affiliates and rewrites the offline code cache.
  ///
  /// Read through the merchant API rather than Firestore on purpose: the rules
  /// deny a client any direct read of `affiliate_codes`, and they should â€” a
  /// till that could read the collection could enumerate every affiliate of the
  /// business. The API answers the same question with the caller's own
  /// authorisation applied.
  Future<void> refreshActiveCodeCache() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final page = await gateway.listAffiliates(status: 'ACTIVE');
    await _dao.replaceActiveCodeCache(page.items, now: _clock());
  }

  /* --------------------------------------------------------------- preview */

  /// What a code is worth here and now, using only what this device holds.
  ///
  /// An unknown code is not an error: it resolves to a decision with no benefit
  /// and the typed code preserved, because the server may still be able to
  /// attribute it and discarding it would be an affiliate never paid.
  @override
  Future<OfflineReferralDecision> previewOfflineReferral({
    required String code,
    required double grossAmount,
    required bool customerIsNew,
    String? customerPhoneE164,
  }) async {
    final normalized = normalizeReferralCodeInput(code);
    if (normalized.isEmpty) {
      return OfflineReferralDecision(normalizedCode: normalized);
    }
    // A provisional code is this device's own guess and is never honoured,
    // including by the device that invented it.
    if (isProvisionalAffiliateCode(normalized)) {
      return OfflineReferralDecision(
        normalizedCode: normalized,
        errorCode: ReferralValidationErrorCode.codeNotFound,
      );
    }

    final cache = await _dao.findCachedCode(normalized);
    if (cache == null) {
      return OfflineReferralDecision(normalizedCode: normalized);
    }

    final error = validateCachedReferralCode(
      cache: cache,
      merchantId: merchantId,
      now: _clock(),
      customerIsNew: customerIsNew,
      saleAmount: grossAmount,
      affiliateStatus: cache.affiliateStatus,
      linkStatus: cache.linkStatus,
      customerPhoneHash: referralPhoneHash(customerPhoneE164),
    );
    if (error != null) {
      return OfflineReferralDecision(
        normalizedCode: normalized,
        cache: cache,
        errorCode: error,
      );
    }

    return OfflineReferralDecision(
      normalizedCode: normalized,
      cache: cache,
      benefit: calculateOfflineReferralBenefit(
        benefitType: cache.benefitType,
        benefitValue: cache.benefitValue,
        grossAmount: grossAmount,
      ),
    );
  }

  /* ------------------------------------------------------------------ sale */

  /// Writes one sale, applies whatever the cache allowed, and queues one
  /// authoritative operation.
  ///
  /// The sale id is the one the server will derive from the device and the
  /// local sale id, so the canonical document and this row are the same row
  /// from the first moment rather than after a rename.
  ///
  /// `amount` keeps its meaning â€” what the customer actually paid â€” so the
  /// loyalty points this sale earns are computed on the net, exactly as the
  /// online commit computes them. A POINTS benefit is recorded but its points
  /// are not added to the customer's balance here: those are a server-owned
  /// ledger entry, and a till that added them would be inventing a confirmed
  /// promotion for a code the server has not agreed to.
  @override
  Future<OfflineReferralSaleResult> recordOfflineReferralSale({
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    required String localSaleId,
    List<SaleItemInput> items = const <SaleItemInput>[],
    OfflineReferralDecision? decision,
  }) async {
    final customerIsNew = await _customerLooksNew(customerId);
    final resolved = decision ??
        await previewOfflineReferral(
          code: code,
          grossAmount: grossAmount,
          customerIsNew: customerIsNew,
          customerPhoneE164: customerPhone,
        );

    final now = _clock();
    final saleId = referralSaleDocumentId(
      deviceId: deviceId,
      localSaleId: localSaleId,
    );
    final idempotencyKey = referralSaleIdempotencyKey(
      deviceId: deviceId,
      localSaleId: localSaleId,
    );
    final benefit = resolved.benefit;
    final netAmount = benefit?.netAmount ?? grossAmount;
    final points = _points.calculate(netAmount);

    final db = await _database.database;
    return db.transaction((txn) async {
      final customerRows = await txn.query(
        'customers',
        where: 'id = ? AND merchant_id = ? AND archived_at IS NULL',
        whereArgs: [customerId, merchantId],
        limit: 1,
      );
      if (customerRows.isEmpty) {
        throw StateError('Active customer not found for sale');
      }

      var sale = Sale(
        id: saleId,
        customerId: customerId,
        amount: netAmount,
        points: points,
        createdAt: now,
        updatedAt: now,
        grossAmount: grossAmount,
        referralBenefitType: benefit?.type,
        referralBenefitValue: benefit?.value,
        referralBenefitAmount: benefit?.storedBenefitAmount,
        affiliateCodeId: resolved.cache?.codeId,
        referralStatus: ReferralSaleStatus.pendingSync,
      );

      await txn.insert('sales', {
        ...sale.toDbMap(),
        'merchant_id': merchantId,
        'device_id': deviceId,
        'created_by_app_user_id': appUserId,
        'updated_by_app_user_id': appUserId,
        'referral_code_input': resolved.normalizedCode,
        'affiliate_id': resolved.cache?.affiliateId,
        'referral_local_benefit_applied': benefit == null ? 0 : 1,
        'referral_idempotency_key': idempotencyKey,
      });

      final itemIds = <String>[
        for (var index = 0; index < items.length; index++)
          referralSaleItemId(deviceId, localSaleId, index),
      ];
      final saleItems = <SaleItem>[];
      for (var index = 0; index < items.length; index++) {
        final input = items[index];
        final quantity = input.quantity.clamp(1, 999).toInt();
        final saleItem = SaleItem(
          id: itemIds[index],
          merchantId: merchantId,
          saleId: saleId,
          merchantItemId: input.merchantItemId,
          nameSnapshot: input.nameSnapshot,
          typeSnapshot: input.typeSnapshot,
          quantity: quantity,
          unitPrice: input.unitPrice,
          subtotal:
              input.unitPrice == null ? null : input.unitPrice! * quantity,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert(
          'sale_items',
          _saleItemDao.rowForSync(saleItem, appUserId: appUserId),
        );
        saleItems.add(saleItem);
      }
      sale = sale.copyWith(items: saleItems);

      final customer = customerFromMap(customerRows.first);
      final updatedCustomer = customer.copyWith(
        totalPoints: customer.totalPoints + points,
        updatedAt: now,
        synced: false,
      );
      await txn.update(
        'customers',
        {...updatedCustomer.toDbMap(), 'merchant_id': merchantId},
        where: 'id = ? AND merchant_id = ?',
        whereArgs: [customerId, merchantId],
      );

      // One authoritative operation for the whole referral. There is no
      // ordinary `sale` create beside it: two operations for one basket is how
      // a purchase gets written twice.
      await _enqueue(
        txn,
        operation: 'create',
        entityType: referralSaleSyncEntityType,
        entityId: saleId,
        localId: localSaleId,
        idempotencyKey: idempotencyKey,
        createdAt: now,
        payload: <String, Object?>{
          'merchant_id': merchantId,
          'device_id': deviceId,
          'local_sale_id': localSaleId,
          'sale_id': saleId,
          'customer_id': customerId,
          'customer_phone': customerPhone,
          'gross_amount': grossAmount,
          'net_amount': netAmount,
          'code': resolved.normalizedCode,
          'created_at': now.millisecondsSinceEpoch,
          'idempotency_key': idempotencyKey,
          // What the till actually gave the customer, so the server can tell a
          // discount it has to honour from one it may still refuse.
          'offline_benefit_applied': benefit != null,
          if (benefit != null)
            'applied_benefit': <String, Object?>{
              'type': benefit.type.storageValue,
              'value': benefit.value,
              'discount_amount': benefit.discountAmount,
              'points_awarded': benefit.pointsAwarded,
            },
          'cached_code_id': resolved.cache?.codeId,
          'items': <Map<String, Object?>>[
            for (var index = 0; index < items.length; index++)
              <String, Object?>{
                'id': itemIds[index],
                'merchant_item_id': items[index].merchantItemId,
                'name_snapshot': items[index].nameSnapshot,
                'type_snapshot': items[index].typeSnapshot.dbValue,
                'quantity': items[index].quantity.clamp(1, 999).toInt(),
                'unit_price': items[index].unitPrice,
                'subtotal': items[index].unitPrice == null
                    ? null
                    : items[index].unitPrice! *
                        items[index].quantity.clamp(1, 999).toInt(),
              },
          ],
        },
      );

      await _enqueue(
        txn,
        operation: 'update',
        entityType: 'customer',
        entityId: customerId,
        localId: customerId,
        idempotencyKey: _uuid.v4(),
        createdAt: now.add(const Duration(milliseconds: 1)),
        payload: <String, Object?>{
          ...updatedCustomer.toClientSyncMap(),
          'merchant_id': merchantId,
        },
      );

      return OfflineReferralSaleResult(
        sale: sale,
        customer: updatedCustomer,
        decision: resolved,
      );
    });
  }

  /* -------------------------------------------------------------- affiliate */

  /// Registers an affiliate this device cannot reach the server to register.
  ///
  /// The person is usable immediately â€” they appear in the list with a code
  /// marked provisional â€” and shareable by nobody. A code invented here is not
  /// unique across the platform, so handing it out would produce a customer at
  /// a counter with a code that does not exist.
  @override
  Future<ProvisionalAffiliate> createAffiliateOffline(
    AffiliateDraft draft,
  ) async {
    final now = _clock();
    final localId = _uuid.v4();
    final affiliateId = 'local_$localId';
    final trimmedName = draft.name.trim();
    final parts = trimmedName.split(RegExp(r'\s+'));
    final firstName = parts.first;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : null;
    final normalizedPhone = draft.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final benefitType = ReferralBenefitType.fromStorage(draft.benefitType);
    final provisionalCode = buildProvisionalAffiliateCode(
      firstName: firstName,
      localId: localId,
    );
    final idempotencyKey = 'affiliate:$deviceId:$localId';

    final db = await _database.database;
    await db.transaction((txn) async {
      await _dao.insertProvisionalAffiliate(
        txn,
        affiliateId: affiliateId,
        localId: localId,
        phoneE164: draft.phone,
        normalizedPhone: normalizedPhone,
        firstName: firstName,
        lastName: lastName,
        displayName: trimmedName,
        provisionalCode: provisionalCode,
        benefitType: benefitType,
        benefitValue: draft.benefitValue,
        usageLimit: draft.usageLimit,
        firstVisitOnly: draft.firstVisitOnly,
        expiresAt: draft.expiresAt,
        now: now,
      );

      await _enqueue(
        txn,
        operation: 'create',
        entityType: affiliateSyncEntityType,
        entityId: affiliateId,
        localId: localId,
        idempotencyKey: idempotencyKey,
        createdAt: now,
        payload: <String, Object?>{
          'merchant_id': merchantId,
          'device_id': deviceId,
          'local_id': localId,
          'local_affiliate_id': affiliateId,
          'idempotency_key': idempotencyKey,
          'created_at': now.millisecondsSinceEpoch,
          'name': trimmedName,
          'phone': draft.phone,
          'benefit_type': draft.benefitType,
          'benefit_value': draft.benefitValue,
          'usage_limit': draft.usageLimit,
          'first_visit_only': draft.firstVisitOnly,
          'expires_at': draft.expiresAt?.millisecondsSinceEpoch,
          'provisional_code': provisionalCode,
        },
      );
    });

    return ProvisionalAffiliate(
      affiliateId: affiliateId,
      localId: localId,
      displayName: trimmedName,
      firstName: firstName,
      phone: draft.phone,
      provisionalCode: provisionalCode,
      syncStatus: AffiliateSyncStatus.pending,
      createdAt: now,
    );
  }

  @override
  Future<List<ProvisionalAffiliate>> provisionalAffiliates() =>
      _dao.provisionalAffiliates();

  /* ------------------------------------------------------------ projection */

  @override
  Future<String?> applyCanonical(
    SyncItem item,
    Map<String, dynamic> canonical,
  ) async {
    if (item.entityType == affiliateSyncEntityType) {
      return _applyAffiliateAnswer(item, canonical);
    }
    if (item.entityType == referralSaleSyncEntityType) {
      return _applyReferralSaleAnswer(item, canonical);
    }
    return null;
  }

  @override
  Future<void> applyFailure(SyncItem item, {required String reason}) async {
    final now = _clock();
    final db = await _database.database;
    await db.transaction((txn) async {
      if (item.entityType == affiliateSyncEntityType) {
        await _dao.markProvisionalAffiliateRejected(
          txn,
          localAffiliateId: item.entityId,
          reason: reason,
          now: now,
        );
        return;
      }
      if (item.entityType != referralSaleSyncEntityType) return;
      // The sale stays exactly as it was charged. Only the referral is closed,
      // and it is closed as refused rather than left pending forever, because
      // "a pendente" that will never resolve is the one state a merchant cannot
      // act on.
      await txn.update(
        'sales',
        {
          'referral_status': ReferralSaleStatus.rejected.storageValue,
          'referral_status_message': reason,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'id = ? AND merchant_id = ?',
        whereArgs: [item.entityId, merchantId],
      );
    });
  }

  Future<String?> _applyAffiliateAnswer(
    SyncItem item,
    Map<String, dynamic> canonical,
  ) async {
    final affiliateMap = _asMap(canonical['affiliate']) ?? canonical;
    final outcome = (canonical['outcome'] as String?)?.toLowerCase();
    final now = _clock();
    final db = await _database.database;

    if (outcome == 'rejected') {
      await db.transaction((txn) async {
        await _dao.markProvisionalAffiliateRejected(
          txn,
          localAffiliateId: item.entityId,
          reason: canonical['message'] as String? ?? 'Pedido recusado.',
          now: now,
        );
      });
      return null;
    }

    final MerchantAffiliate affiliate;
    try {
      affiliate = MerchantAffiliate.fromMap(affiliateMap);
    } on Object {
      return null;
    }

    await db.transaction((txn) async {
      await _dao.reconcileProvisionalAffiliate(
        txn,
        localAffiliateId: item.entityId,
        canonical: affiliate,
        now: now,
      );
    });
    return affiliate.id;
  }

  /// Writes the server's verdict over the sale this device already wrote.
  ///
  /// Four verdicts, and the difference between them is money:
  ///
  ///   accepted, with the benefit the till had already applied â€” the sale is
  ///   confirmed and the attribution and reward arrive with it;
  ///
  ///   accepted, for a code this till could not price â€” the acquisition and any
  ///   POINTS benefit are created server-side, and the monetary discount is
  ///   *not* applied retroactively, because the customer has already paid and
  ///   the sale is not reopened;
  ///
  ///   refused, with a benefit already given â€” the sale and the discount stand,
  ///   the refusal is recorded as a rejected attribution with its reason, and
  ///   the affiliate is paid nothing;
  ///
  ///   refused, with nothing given â€” only the refusal is recorded.
  Future<String?> _applyReferralSaleAnswer(
    SyncItem item,
    Map<String, dynamic> canonical,
  ) async {
    final now = _clock();
    final saleMap = _asMap(canonical['sale']);
    final referral = _asMap(canonical['referral']) ?? const <String, dynamic>{};
    final attribution = _asMap(referral['attribution']);
    final outcome = (canonical['outcome'] as String?)?.toLowerCase() ?? '';
    final attributionStatus =
        ((referral['attribution_status'] ?? attribution?['status']) as String?)
            ?.toUpperCase();
    final rejected = outcome == 'rejected' || attributionStatus == 'REJECTED';
    final canonicalSaleId =
        (saleMap?['id'] as String?)?.trim().isNotEmpty == true
            ? saleMap!['id'] as String
            : item.entityId;

    final db = await _database.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'sales',
        where: 'id = ? AND merchant_id = ?',
        whereArgs: [item.entityId, merchantId],
        limit: 1,
      );
      if (existing.isEmpty) return;
      final local = saleFromMap(existing.first);

      final patch = <String, Object?>{
        'updated_at': now.millisecondsSinceEpoch,
        'synced': 1,
      };

      if (rejected) {
        final rejectionReason = canonical['reason'] ??
            referral['rejection_reason'] ??
            attribution?['rejection_reason'] ??
            attribution?['rejection_code'];
        patch['referral_status'] = ReferralSaleStatus.rejected.storageValue;
        patch['referral_rejection_code'] = rejectionReason;
        patch['referral_status_message'] = canonical['message'] ??
            referralErrorMessage(
              _errorCodeOf(rejectionReason),
            );
        // The benefit is not taken back. Whatever the customer was charged is
        // what the customer paid, and reversing it now would be a debt owed by
        // someone who has left the shop.
      } else {
        patch['referral_status'] =
            (referral['attribution_status'] as String?)?.toUpperCase() ==
                    'CONFIRMED'
                ? ReferralSaleStatus.attributed.storageValue
                : ReferralSaleStatus.pending.storageValue;
        patch['referral_status_message'] = null;
        patch['referral_rejection_code'] = null;
        patch['affiliate_code_id'] =
            referral['affiliate_code_id'] ?? local.affiliateCodeId;
        patch['affiliate_id'] = referral['affiliate_id'];

        // A benefit the till never applied is not written into `amount`: the
        // sale was charged in full and stays charged in full. Only a POINTS
        // benefit can still be honoured, and it is honoured by the server's
        // ledger entry, not by this row.
        final appliedLocally =
            (existing.first['referral_local_benefit_applied'] as int? ?? 0) ==
                1;
        if (!appliedLocally) {
          final benefit = _asMap(referral['benefit']);
          final type = benefit == null ? null : benefit['type'] as String?;
          if (type != null && type.toUpperCase() == 'POINTS') {
            patch['referral_benefit_type'] = 'POINTS';
            patch['referral_benefit_value'] =
                (benefit!['value'] as num?)?.toDouble();
            patch['referral_benefit_amount'] =
                (benefit['points_awarded'] as num?)?.toDouble();
          }
        }
      }

      await txn.update(
        'sales',
        patch,
        where: 'id = ? AND merchant_id = ?',
        whereArgs: [item.entityId, merchantId],
      );

      if (attribution != null) {
        await _dao.ensureAttributionReferences(
          txn,
          referral,
          attribution,
          now: now,
        );
        await _dao.upsertAttribution(txn, attribution, now: now);
      }
      final reward = _asMap(referral['reward_record']);
      if (reward != null) {
        await _dao.upsertReward(txn, reward, now: now);
      }
      final events = canonical['events'];
      if (events is List) {
        for (final event in events) {
          final map = _asMap(event);
          if (map != null) await _dao.insertEventIfAbsent(txn, map, now: now);
        }
      }
    });

    return canonicalSaleId == item.entityId ? null : canonicalSaleId;
  }

  /* ---------------------------------------------------------------- helpers */

  /// The local half of "is this customer new to the business".
  ///
  /// Only ever used to decide whether to *offer* a benefit. The server decides
  /// the acquisition, because this device cannot see a sale another till made
  /// this morning.
  Future<bool> _customerLooksNew(String customerId) async {
    final db = await _database.database;
    final rows = await db.query(
      'customers',
      columns: const [
        'total_visits',
        'first_visit_at',
        'last_visit_at',
        'total_spent'
      ],
      where: 'id = ? AND merchant_id = ?',
      whereArgs: [customerId, merchantId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    return ((row['total_visits'] as num?)?.toInt() ?? 0) <= 0 &&
        row['first_visit_at'] == null &&
        row['last_visit_at'] == null &&
        ((row['total_spent'] as num?)?.toDouble() ?? 0) <= 0;
  }

  Future<void> _enqueue(
    DatabaseExecutor txn, {
    required String operation,
    required String entityType,
    required String entityId,
    required String localId,
    required String idempotencyKey,
    required DateTime createdAt,
    required Map<String, Object?> payload,
  }) async {
    await txn.insert('sync_queue', {
      ...SyncItem(
        id: _uuid.v4(),
        operation: operation,
        entityType: entityType,
        entityId: entityId,
        payload: jsonEncode(payload),
        createdAt: createdAt,
      ).toDbMap(),
      'merchant_id': merchantId,
      'device_id': deviceId,
      'local_id': localId,
      'idempotency_key': idempotencyKey,
      'last_error': null,
      'last_sync_error': null,
    });
  }

  ReferralValidationErrorCode? _errorCodeOf(Object? value) {
    if (value == null) return null;
    try {
      return ReferralValidationErrorCode.fromStorage(value);
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return null;
  }
}
