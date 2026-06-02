enum Plan {
  launchAccess,
  free,
  starter,
  pro,
  business,
  // Legacy plan kept for compatibility with already-synced records.
  growth;

  String get code => switch (this) {
    Plan.launchAccess => 'launch_access',
    Plan.free => 'free',
    Plan.starter => 'starter',
    Plan.pro => 'pro',
    Plan.business => 'business',
    Plan.growth => 'growth',
  };

  String get displayName => switch (this) {
    Plan.launchAccess => 'Launch Access',
    Plan.free => 'Free',
    Plan.starter => 'Starter',
    Plan.pro => 'Pro',
    Plan.business => 'Business',
    Plan.growth => 'Growth',
  };

  static Plan fromCode(String? value) {
    switch (value?.toLowerCase()) {
      case 'launch_access':
        return Plan.launchAccess;
      case 'starter':
        return Plan.starter;
      case 'pro':
        return Plan.pro;
      case 'business':
        return Plan.business;
      case 'growth':
        return Plan.business;
      case 'free':
      default:
        return Plan.free;
    }
  }
}
