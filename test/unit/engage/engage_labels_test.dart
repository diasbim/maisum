import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/engage/domain/engage_labels.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';

/// The Engage vocabulary is stored in English because those are database
/// values. These tests exist so no stored value can reach a Portuguese screen
/// untranslated — the defect that put "Risco YELLOW" and "Needs Promotion" in
/// front of merchants.
void main() {
  group('EngageLabels', () {
    test('translates every risk level', () {
      expect(EngageLabels.riskLevel(EngageRiskLevel.green), 'Saudável');
      expect(EngageLabels.riskLevel(EngageRiskLevel.yellow), 'Atenção');
      expect(EngageLabels.riskLevel(EngageRiskLevel.orange), 'Alerta');
      expect(EngageLabels.riskLevel(EngageRiskLevel.red), 'Crítico');
    });

    test('translates every visit result', () {
      for (final value in VisitResultType.values) {
        expect(
          EngageLabels.visitResult(value),
          isNot(value),
          reason: '$value reaches the merchant untranslated',
        );
      }
      expect(
        EngageLabels.visitResult(VisitResultType.needsPromotion),
        'Só volta com promoção',
      );
    });

    test('translates every recovery action type', () {
      expect(EngageLabels.actionType(RecoveryActionType.call), 'Ligação');
      expect(EngageLabels.actionType(RecoveryActionType.offer), 'Oferta');
      expect(EngageLabels.actionType(RecoveryActionType.visit), 'Visita');
      // WhatsApp is a brand name and stays as it is.
      expect(EngageLabels.actionType(RecoveryActionType.whatsapp), 'WhatsApp');
    });

    test('translates priorities and statuses', () {
      expect(EngageLabels.taskPriority(RecoveryTaskPriority.high), 'alta');
      expect(EngageLabels.taskPriority(RecoveryTaskPriority.medium), 'média');
      expect(EngageLabels.taskPriority(RecoveryTaskPriority.low), 'baixa');
      expect(EngageLabels.taskStatus(RecoveryTaskStatus.open), 'Pendente');
      expect(EngageLabels.taskStatus(RecoveryTaskStatus.completed), 'Concluída');
    });

    test('falls back to Portuguese for an unknown risk level', () {
      expect(EngageLabels.riskLevel('purple'), 'Sem dados');
    });
  });
}
