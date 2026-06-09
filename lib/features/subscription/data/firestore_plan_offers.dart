import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/feature_keys.dart';
import '../domain/plan.dart';
import '../domain/plan_catalog.dart';

class PlanOffer {
  const PlanOffer({
    required this.plan,
    required this.code,
    required this.displayName,
    required this.priceCents,
    required this.currency,
    required this.billingInterval,
    required this.features,
    required this.whatsappMonthlyLimit,
    required this.sortOrder,
  });

  final Plan plan;
  final String code;
  final String displayName;
  final int? priceCents;
  final String currency;
  final String billingInterval;
  final Set<String> features;
  final int? whatsappMonthlyLimit;
  final int sortOrder;

  bool get supportsFullEngage =>
      features.contains(FeatureKeys.engageViewRisk) &&
      features.contains(FeatureKeys.engageManageRecovery) &&
      features.contains(FeatureKeys.engageManageVisits) &&
      features.contains(FeatureKeys.engageManageSurveys);

  factory PlanOffer.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawCode =
        _readString(data, const ['plan_code', 'code', 'planCode']) ?? doc.id;
    final normalizedCode = rawCode.trim().toLowerCase();

    final knownPlanCodes = Plan.values.map((plan) => plan.code).toSet();
    if (!knownPlanCodes.contains(normalizedCode)) {
      throw const FormatException('Unknown plan code in plans collection.');
    }

    final plan = Plan.fromCode(normalizedCode);
    if (plan == Plan.growth) {
      throw const FormatException('Legacy growth plan is not selectable.');
    }

    final definition = PlanCatalog.forPlan(plan);

    final displayName = _readString(
          data,
          const ['display_name', 'name', 'plan_name', 'displayName'],
        ) ??
        definition.displayName;

    final features = _readStringList(data, const ['features']).toSet();

    return PlanOffer(
      plan: plan,
      code: normalizedCode,
      displayName: displayName,
      priceCents: _readInt(
        data,
        const [
          'price_cents',
          'priceCents',
          'amount_cents',
          'amountCents',
          'price',
        ],
      ),
      currency: (_readString(data, const ['currency']) ?? 'BRL').toUpperCase(),
      billingInterval:
          _readString(data, const ['billing_interval', 'billingInterval']) ??
              'monthly',
      features: features.isEmpty ? definition.features : features,
      whatsappMonthlyLimit: _readInt(
            data,
            const ['whatsapp_monthly_limit', 'whatsappMonthlyLimit'],
          ) ??
          definition.whatsappMonthlyLimit,
      sortOrder:
          _readInt(data, const ['sort_order', 'order', 'position']) ?? 999,
    );
  }
}

Future<List<PlanOffer>> fetchActivePlanOffers(
    FirebaseFirestore firestore) async {
  final snapshot = await firestore.collection('plans').get();
  final offers = <PlanOffer>[];

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final isActive = _readBool(data, const ['is_active', 'active']) ?? true;
    if (!isActive) {
      continue;
    }

    try {
      final offer = PlanOffer.fromFirestore(doc);
      if (offer.priceCents != null) {
        offers.add(offer);
      }
    } on FormatException {
      // Ignore invalid documents and keep loading other plans.
    }
  }

  offers.sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) {
      return byOrder;
    }
    final aPrice = a.priceCents ?? (1 << 30);
    final bPrice = b.priceCents ?? (1 << 30);
    final byPrice = aPrice.compareTo(bPrice);
    if (byPrice != 0) {
      return byPrice;
    }
    return a.displayName.compareTo(b.displayName);
  });

  return offers;
}

String? _readString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

int? _readInt(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

bool? _readBool(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
  }
  return null;
}

List<String> _readStringList(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is Iterable) {
      return value
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
    }
  }
  return const [];
}
