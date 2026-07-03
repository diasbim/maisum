class AdminOperationsSummary {
  const AdminOperationsSummary({
    required this.merchantCount,
    required this.activeSubscriptionCount,
    required this.trialSubscriptionCount,
    required this.attentionSubscriptionCount,
    required this.activeStaffCount,
    required this.usageEvents24h,
    required this.openRecoveryTaskCount,
    required this.visitReports24h,
    required this.surveyResponses24h,
    required this.adminAuditEvents24h,
    this.lastAdminAuditAt,
    this.lastUsageEventAt,
  });

  final int merchantCount;
  final int activeSubscriptionCount;
  final int trialSubscriptionCount;
  final int attentionSubscriptionCount;
  final int activeStaffCount;
  final int usageEvents24h;
  final int openRecoveryTaskCount;
  final int visitReports24h;
  final int surveyResponses24h;
  final int adminAuditEvents24h;
  final DateTime? lastAdminAuditAt;
  final DateTime? lastUsageEventAt;

  factory AdminOperationsSummary.fromJson(Map<String, dynamic> json) {
    return AdminOperationsSummary(
      merchantCount: _readInt(json['merchant_count']),
      activeSubscriptionCount: _readInt(json['active_subscription_count']),
      trialSubscriptionCount: _readInt(json['trial_subscription_count']),
      attentionSubscriptionCount:
          _readInt(json['attention_subscription_count']),
      activeStaffCount: _readInt(json['active_staff_count']),
      usageEvents24h: _readInt(json['usage_events_24h']),
      openRecoveryTaskCount: _readInt(json['open_recovery_task_count']),
      visitReports24h: _readInt(json['visit_reports_24h']),
      surveyResponses24h: _readInt(json['survey_responses_24h']),
      adminAuditEvents24h: _readInt(json['admin_audit_events_24h']),
      lastAdminAuditAt: _readDate(json['last_admin_audit_at']),
      lastUsageEventAt: _readDate(json['last_usage_event_at']),
    );
  }
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

DateTime? _readDate(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.round());
  if (value is String) {
    final millis = int.tryParse(value.trim());
    if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime.tryParse(value);
  }
  return null;
}
