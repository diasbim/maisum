enum Plan {
  launchAccess,
  free,
  starter,
  growth;

  String get code => switch (this) {
        Plan.launchAccess => 'launch_access',
        Plan.free => 'free',
        Plan.starter => 'starter',
        Plan.growth => 'growth',
      };

  String get displayName => switch (this) {
        Plan.launchAccess => 'Launch Access',
        Plan.free => 'Free',
        Plan.starter => 'Starter',
        Plan.growth => 'Growth',
      };

  static Plan fromCode(String? value) {
    switch (value?.toLowerCase()) {
      case 'launch_access':
        return Plan.launchAccess;
      case 'starter':
        return Plan.starter;
      case 'growth':
        return Plan.growth;
      case 'free':
      default:
        return Plan.free;
    }
  }
}
