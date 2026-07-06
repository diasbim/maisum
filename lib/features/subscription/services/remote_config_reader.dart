import '../data/remote_config_repository.dart';
import '../domain/remote_config_defaults.dart';
import '../domain/remote_config_keys.dart';

class PricingOverride {
  const PricingOverride({
    this.priceCents,
    this.currency,
    this.billingInterval,
    this.planVersion,
    this.pricingVersion,
    this.validFrom,
    this.validUntil,
  });

  final int? priceCents;
  final String? currency;
  final String? billingInterval;
  final String? planVersion;
  final String? pricingVersion;
  final DateTime? validFrom;
  final DateTime? validUntil;
}

class QuotaOverride {
  const QuotaOverride({this.limit, this.softLimit});

  final int? limit;
  final bool? softLimit;
}

class UpsellWhatsAppConfig {
  const UpsellWhatsAppConfig({required this.number, required this.message});

  final String number;
  final String message;
}

class RemoteConfigReader {
  RemoteConfigReader(this._repository);

  final RemoteConfigRepository _repository;

  Future<bool?> getBool(String key) async {
    final payload = await _payload(key);
    if (payload == null) return null;
    final value = payload['value'] ?? payload['enabled'] ?? payload['flag'];
    return _asBool(value);
  }

  Future<int?> getInt(String key) async {
    final payload = await _payload(key);
    if (payload == null) return null;
    final value = payload['value'] ?? payload['limit'] ?? payload['amount'];
    return _asInt(value);
  }

  Future<String?> getString(String key) async {
    final payload = await _payload(key);
    if (payload == null) return null;
    final value = payload['value'] ?? payload['text'] ?? payload['message'];
    if (value == null) return null;
    return value.toString();
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    return _payload(key);
  }

  Future<int> getTrialDays() async {
    return await getInt(RemoteConfigKeys.trialDays) ??
        RemoteConfigDefaults.trialDays;
  }

  Future<UpsellWhatsAppConfig> getUpsellWhatsAppConfig() async {
    final payload = await _payload(RemoteConfigKeys.upsellWhatsApp);
    final number = _normalizePhone(
      _asString(payload?['number'] ?? payload?['phone'] ?? payload?['value']),
    );
    final message = _asString(payload?['message'] ?? payload?['text']);
    return UpsellWhatsAppConfig(
      number:
          number.isEmpty ? RemoteConfigDefaults.upsellWhatsAppNumber : number,
      message: (message == null || message.trim().isEmpty)
          ? RemoteConfigDefaults.upsellWhatsAppMessage
          : message.trim(),
    );
  }

  Future<PricingOverride?> getPricingOverride(String planCode) async {
    final payload = await _payload(RemoteConfigKeys.pricingPlan(planCode));
    if (payload == null) return null;
    return PricingOverride(
      priceCents: _asInt(payload['priceCents'] ?? payload['amount']),
      currency: _asString(payload['currency']),
      billingInterval:
          _asString(payload['interval'] ?? payload['billingInterval']),
      planVersion: _asString(payload['planVersion']),
      pricingVersion: _asString(payload['pricingVersion']),
      validFrom: _asDate(payload['validFrom']),
      validUntil: _asDate(payload['validUntil']),
    );
  }

  Future<QuotaOverride?> getQuotaOverride(String metricKey) async {
    final payload = await _payload(RemoteConfigKeys.quotaMetric(metricKey));
    if (payload == null) return null;
    return QuotaOverride(
      limit: _asInt(payload['limit'] ?? payload['value']),
      softLimit: _asBool(payload['softLimit'] ?? payload['soft_limit']),
    );
  }

  Future<Map<String, dynamic>?> _payload(String key) async {
    final entry = await _repository.getConfig(key);
    return entry?.payload;
  }

  String? _asString(Object? value) {
    if (value == null) return null;
    return value.toString();
  }

  String _normalizePhone(String? value) {
    if (value == null) return '';
    return value.replaceAll(RegExp(r'\D'), '');
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  bool? _asBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    final lowered = value.toString().toLowerCase();
    if (lowered == 'true') return true;
    if (lowered == 'false') return false;
    return null;
  }

  DateTime? _asDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    return DateTime.tryParse(value.toString());
  }
}
