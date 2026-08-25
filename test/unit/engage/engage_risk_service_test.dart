import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/business_profile/domain/business_profile.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/engage/services/engage_risk_service.dart';

void main() {
  const service = EngageRiskService();

  group('EngageRiskService risk thresholds', () {
    test('maps day boundaries to GREEN/YELLOW/ORANGE/RED', () {
      expect(service.riskLevelFromDays(0), EngageRiskLevel.green);
      expect(service.riskLevelFromDays(30), EngageRiskLevel.green);
      expect(service.riskLevelFromDays(31), EngageRiskLevel.yellow);
      expect(service.riskLevelFromDays(60), EngageRiskLevel.yellow);
      expect(service.riskLevelFromDays(61), EngageRiskLevel.orange);
      expect(service.riskLevelFromDays(90), EngageRiskLevel.orange);
      expect(service.riskLevelFromDays(91), EngageRiskLevel.red);
    });

    test('uses thresholds supplied by the business profile', () {
      final barberService = EngageRiskService(
        retentionDefaults: BusinessProfiles.resolve('barbershop').retention,
      );

      expect(barberService.riskLevelFromDays(14), EngageRiskLevel.green);
      expect(barberService.riskLevelFromDays(15), EngageRiskLevel.yellow);
      expect(barberService.riskLevelFromDays(31), EngageRiskLevel.orange);
      expect(barberService.riskLevelFromDays(61), EngageRiskLevel.red);
    });

    test('computes priority score with risk, spend, and points weights', () {
      final score = service.priorityScore(
        riskLevel: EngageRiskLevel.red,
        totalSpent: 5200,
        totalPoints: 5100,
      );
      expect(score, 65);
    });

    test('maps priority score to task priority', () {
      expect(service.taskPriorityFromScore(10), RecoveryTaskPriority.low);
      expect(service.taskPriorityFromScore(30), RecoveryTaskPriority.medium);
      expect(service.taskPriorityFromScore(50), RecoveryTaskPriority.high);
    });
  });
}
