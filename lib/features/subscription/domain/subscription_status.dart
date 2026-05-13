enum SubscriptionStatus {
  trial,
  active,
  grace,
  pastDue,
  canceled,
  suspended;

  String get code => switch (this) {
        SubscriptionStatus.trial => 'TRIAL',
        SubscriptionStatus.active => 'ACTIVE',
        SubscriptionStatus.grace => 'GRACE',
        SubscriptionStatus.pastDue => 'PAST_DUE',
        SubscriptionStatus.canceled => 'CANCELED',
        SubscriptionStatus.suspended => 'SUSPENDED',
      };

  String get displayName => switch (this) {
        SubscriptionStatus.trial => 'Trial',
        SubscriptionStatus.active => 'Active',
        SubscriptionStatus.grace => 'Grace',
        SubscriptionStatus.pastDue => 'Past Due',
        SubscriptionStatus.canceled => 'Canceled',
        SubscriptionStatus.suspended => 'Suspended',
      };

  static SubscriptionStatus fromWire(String? value) {
    switch (value?.toUpperCase()) {
      case 'TRIAL':
        return SubscriptionStatus.trial;
      case 'GRACE':
        return SubscriptionStatus.grace;
      case 'PAST_DUE':
        return SubscriptionStatus.pastDue;
      case 'CANCELED':
        return SubscriptionStatus.canceled;
      case 'SUSPENDED':
        return SubscriptionStatus.suspended;
      case 'ACTIVE':
      default:
        return SubscriptionStatus.active;
    }
  }

  bool get isInactive =>
      this == SubscriptionStatus.canceled || this == SubscriptionStatus.suspended;

  bool get isPastDue =>
      this == SubscriptionStatus.pastDue || this == SubscriptionStatus.grace;
}
