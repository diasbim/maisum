import 'engage_models.dart';

/// Portuguese labels for the Engage vocabulary.
///
/// Risk levels, priorities, action types and visit results are stored as
/// English database values. Screens must render them through this file — a
/// merchant should never read "YELLOW", "high" or "Needs Promotion" on a
/// Portuguese screen.
class EngageLabels {
  const EngageLabels._();

  /// Risk levels are stored as colour names ('green'…'red'), which say nothing
  /// to the merchant and repeat information the colour already carries. These
  /// labels say what the level *means* instead.
  static String riskLevel(String level) => switch (level) {
        EngageRiskLevel.red => 'Crítico',
        EngageRiskLevel.orange => 'Alerta',
        EngageRiskLevel.yellow => 'Atenção',
        EngageRiskLevel.green => 'Saudável',
        _ => 'Sem dados',
      };

  static String taskPriority(String priority) => switch (priority) {
        RecoveryTaskPriority.high => 'alta',
        RecoveryTaskPriority.low => 'baixa',
        _ => 'média',
      };

  static String taskStatus(String status) => switch (status) {
        RecoveryTaskStatus.completed => 'Concluída',
        _ => 'Pendente',
      };

  static String actionType(String action) => switch (action) {
        RecoveryActionType.whatsapp => 'WhatsApp',
        RecoveryActionType.call => 'Ligação',
        RecoveryActionType.offer => 'Oferta',
        RecoveryActionType.visit => 'Visita',
        _ => action,
      };

  /// Question types are stored as 'SHORT_TEXT', 'YES_NO'… Named here in terms
  /// of the answer the merchant will get back, not the storage format.
  static String questionType(String type) => switch (type) {
        SurveyQuestionType.multipleChoice => 'Escolha entre opções',
        SurveyQuestionType.yesNo => 'Sim ou não',
        SurveyQuestionType.rating => 'Nota de 1 a 5',
        SurveyQuestionType.shortText => 'Resposta escrita',
        _ => type,
      };

  static String surveyChannel(String channel) => switch (channel) {
        SurveyChannel.whatsapp => 'WhatsApp',
        SurveyChannel.sms => 'SMS',
        SurveyChannel.inApp => 'Na aplicação',
        SurveyChannel.manual => 'Presencial',
        _ => channel,
      };

  static String visitResult(String result) => switch (result) {
        VisitResultType.returned => 'Voltou à loja',
        VisitResultType.interested => 'Mostrou interesse',
        VisitResultType.needsPromotion => 'Só volta com promoção',
        VisitResultType.wrongNumber => 'Contacto errado',
        VisitResultType.lostCustomer => 'Cliente perdido',
        _ => result,
      };
}
