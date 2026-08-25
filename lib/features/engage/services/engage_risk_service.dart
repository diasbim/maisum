import '../../business_profile/domain/business_profile.dart';
import '../domain/engage_models.dart';

class EngageRiskService {
  const EngageRiskService({
    this.retentionDefaults = BusinessProfiles.genericRetention,
  });

  final BusinessRetentionDefaults retentionDefaults;

  String riskLevelFromDays(int days) {
    if (days <= retentionDefaults.activeDays) return EngageRiskLevel.green;
    if (days <= retentionDefaults.attentionDays) return EngageRiskLevel.yellow;
    if (days <= retentionDefaults.riskDays) return EngageRiskLevel.orange;
    return EngageRiskLevel.red;
  }

  int priorityScore({
    required String riskLevel,
    required double totalSpent,
    required int totalPoints,
  }) {
    final riskWeight = switch (riskLevel) {
      EngageRiskLevel.red => 40,
      EngageRiskLevel.orange => 30,
      EngageRiskLevel.yellow => 20,
      _ => 10,
    };

    final spentWeight = totalSpent >= 5000
        ? 15
        : totalSpent >= 2000
            ? 10
            : totalSpent >= 500
                ? 5
                : 0;

    final pointsWeight = totalPoints >= 5000
        ? 10
        : totalPoints >= 2000
            ? 6
            : totalPoints >= 500
                ? 3
                : 0;

    return riskWeight + spentWeight + pointsWeight;
  }

  String taskPriorityFromScore(int priorityScore) {
    if (priorityScore >= 45) return RecoveryTaskPriority.high;
    if (priorityScore >= 25) return RecoveryTaskPriority.medium;
    return RecoveryTaskPriority.low;
  }

  int daysSinceVisit(DateTime lastVisitAt, DateTime nowDate) {
    final start = DateTime(
      lastVisitAt.year,
      lastVisitAt.month,
      lastVisitAt.day,
    );
    final end = DateTime(nowDate.year, nowDate.month, nowDate.day);
    return end.difference(start).inDays;
  }
}
