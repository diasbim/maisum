import 'feature_keys.dart';
import 'plan.dart';

class PlanDefinition {
  const PlanDefinition({
    required this.plan,
    required this.features,
    required this.whatsappMonthlyLimit,
  });

  final Plan plan;
  final Set<String> features;
  final int? whatsappMonthlyLimit;

  String get displayName => plan.displayName;

  bool allowsFeature(String featureKey) => features.contains(featureKey);
}

class PlanCatalog {
  static const Map<Plan, PlanDefinition> _definitions = {
    Plan.launchAccess: PlanDefinition(
      plan: Plan.launchAccess,
      features: {
        FeatureKeys.whatsappAutomation,
        FeatureKeys.campaigns,
        FeatureKeys.analytics,
        FeatureKeys.multiDevice,
        FeatureKeys.cloudBackup,
      },
      whatsappMonthlyLimit: 20000,
    ),
    Plan.free: PlanDefinition(
      plan: Plan.free,
      features: {
        FeatureKeys.whatsappAutomation,
      },
      whatsappMonthlyLimit: 150,
    ),
    Plan.starter: PlanDefinition(
      plan: Plan.starter,
      features: {
        FeatureKeys.whatsappAutomation,
        FeatureKeys.campaigns,
        FeatureKeys.analytics,
      },
      whatsappMonthlyLimit: 1200,
    ),
    Plan.growth: PlanDefinition(
      plan: Plan.growth,
      features: {
        FeatureKeys.whatsappAutomation,
        FeatureKeys.campaigns,
        FeatureKeys.analytics,
        FeatureKeys.multiDevice,
        FeatureKeys.cloudBackup,
      },
      whatsappMonthlyLimit: 6000,
    ),
  };

  static PlanDefinition forPlan(Plan plan) =>
      _definitions[plan] ?? _definitions[Plan.free]!;

  static PlanDefinition fromCode(String? planCode) =>
      forPlan(Plan.fromCode(planCode));
}
