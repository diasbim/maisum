class EngageRiskLevel {
  static const String green = 'green';
  static const String yellow = 'yellow';
  static const String orange = 'orange';
  static const String red = 'red';

  static const Set<String> values = {green, yellow, orange, red};

  static const Set<String> atRisk = {yellow, orange, red};
}

class RecoveryTaskPriority {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';

  static const Set<String> values = {low, medium, high};
}

class RecoveryTaskStatus {
  static const String open = 'open';
  static const String completed = 'completed';
}

class RecoveryActionType {
  static const String whatsapp = 'WHATSAPP';
  static const String call = 'CALL';
  static const String offer = 'OFFER';
  static const String visit = 'VISIT';

  static const List<String> values = [whatsapp, call, offer, visit];
}

class VisitResultType {
  static const String returned = 'Returned';
  static const String interested = 'Interested';
  static const String needsPromotion = 'Needs Promotion';
  static const String wrongNumber = 'Wrong Number';
  static const String lostCustomer = 'Lost Customer';

  static const List<String> values = [
    returned,
    interested,
    needsPromotion,
    wrongNumber,
    lostCustomer,
  ];
}

class CustomerRiskScore {
  const CustomerRiskScore({
    required this.id,
    required this.customerId,
    required this.daysSinceVisit,
    required this.riskLevel,
    required this.priority,
    required this.updatedAt,
    this.synced = false,
  });

  final String id;
  final String customerId;
  final int daysSinceVisit;
  final String riskLevel;
  final int priority;
  final DateTime updatedAt;
  final bool synced;

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'days_since_visit': daysSinceVisit,
    'risk_level': riskLevel,
    'priority': priority,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'synced': synced ? 1 : 0,
  };

  factory CustomerRiskScore.fromJson(Map<String, dynamic> json) {
    return CustomerRiskScore(
      id: (json['id'] as String?) ?? '',
      customerId: (json['customer_id'] as String?) ?? '',
      daysSinceVisit: _readInt(json['days_since_visit']),
      riskLevel: (json['risk_level'] as String?) ?? EngageRiskLevel.green,
      priority: _readInt(json['priority']),
      updatedAt: _readDateTime(json['updated_at']) ?? DateTime.now(),
      synced: _readBool(json['synced']),
    );
  }
}

class RecoveryTask {
  const RecoveryTask({
    required this.id,
    required this.customerId,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.dueAt,
    this.notes,
    this.synced = false,
  });

  final String id;
  final String customerId;
  final String priority;
  final String status;
  final DateTime? dueAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'priority': priority,
    'status': status,
    'due_at': dueAt?.millisecondsSinceEpoch,
    'notes': notes,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'synced': synced ? 1 : 0,
  };

  factory RecoveryTask.fromJson(Map<String, dynamic> json) {
    return RecoveryTask(
      id: (json['id'] as String?) ?? '',
      customerId: (json['customer_id'] as String?) ?? '',
      priority: (json['priority'] as String?) ?? RecoveryTaskPriority.medium,
      status: (json['status'] as String?) ?? RecoveryTaskStatus.open,
      dueAt: _readDateTime(json['due_at']),
      notes: json['notes'] as String?,
      createdAt: _readDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updated_at']) ?? DateTime.now(),
      synced: _readBool(json['synced']),
    );
  }
}

class RecoveryQueueItem {
  const RecoveryQueueItem({
    required this.customerId,
    required this.customerName,
    required this.daysSinceVisit,
    required this.riskLevel,
    required this.priorityScore,
    required this.totalSpent,
    required this.totalPoints,
    required this.recommendedPriority,
    this.lastVisitAt,
  });

  final String customerId;
  final String customerName;
  final int daysSinceVisit;
  final String riskLevel;
  final int priorityScore;
  final double totalSpent;
  final int totalPoints;
  final String recommendedPriority;
  final DateTime? lastVisitAt;
}

class RecoveryActionLog {
  const RecoveryActionLog({
    required this.id,
    required this.customerId,
    required this.actionType,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.payload,
    this.synced = false,
  });

  final String id;
  final String customerId;
  final String actionType;
  final String? taskId;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'task_id': taskId,
    'action_type': actionType,
    'payload': payload,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'synced': synced ? 1 : 0,
  };

  factory RecoveryActionLog.fromJson(Map<String, dynamic> json) {
    return RecoveryActionLog(
      id: (json['id'] as String?) ?? '',
      customerId: (json['customer_id'] as String?) ?? '',
      taskId: json['task_id'] as String?,
      actionType: (json['action_type'] as String?) ?? RecoveryActionType.call,
      payload: _readMap(json['payload']),
      createdAt: _readDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updated_at']) ?? DateTime.now(),
      synced: _readBool(json['synced']),
    );
  }
}

class VisitReport {
  const VisitReport({
    required this.id,
    required this.customerId,
    required this.result,
    required this.visitedAt,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.notes,
    this.synced = false,
  });

  final String id;
  final String customerId;
  final String result;
  final DateTime visitedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? taskId;
  final String? notes;
  final bool synced;

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'task_id': taskId,
    'result': result,
    'notes': notes,
    'visited_at': visitedAt.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'synced': synced ? 1 : 0,
  };

  factory VisitReport.fromJson(Map<String, dynamic> json) {
    return VisitReport(
      id: (json['id'] as String?) ?? '',
      customerId: (json['customer_id'] as String?) ?? '',
      taskId: json['task_id'] as String?,
      result: (json['result'] as String?) ?? VisitResultType.interested,
      notes: json['notes'] as String?,
      visitedAt:
          _readDateTime(json['visited_at']) ??
          _readDateTime(json['created_at']) ??
          DateTime.now(),
      createdAt: _readDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updated_at']) ?? DateTime.now(),
      synced: _readBool(json['synced']),
    );
  }
}

class EngageDashboardData {
  const EngageDashboardData({
    required this.customersActive,
    required this.customersAtRisk,
    required this.criticalCustomers,
    required this.revenueAtRisk,
    required this.recoveredCustomers,
  });

  final int customersActive;
  final int customersAtRisk;
  final int criticalCustomers;
  final double revenueAtRisk;
  final int recoveredCustomers;
}

class SurveyQuestionType {
  static const String multipleChoice = 'MULTIPLE_CHOICE';
  static const String yesNo = 'YES_NO';
  static const String rating = 'RATING';
  static const String shortText = 'SHORT_TEXT';

  static const Set<String> values = {multipleChoice, yesNo, rating, shortText};
}

class EngageSurveyQuestion {
  const EngageSurveyQuestion({
    required this.id,
    required this.surveyId,
    required this.questionText,
    required this.questionType,
    required this.sortOrder,
    required this.isRequired,
    required this.createdAt,
    required this.updatedAt,
    this.options = const [],
    this.synced = false,
  });

  final String id;
  final String surveyId;
  final String questionText;
  final String questionType;
  final int sortOrder;
  final bool isRequired;
  final List<String> options;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  Map<String, dynamic> toJson() => {
    'id': id,
    'survey_id': surveyId,
    'question_text': questionText,
    'question_type': questionType,
    'sort_order': sortOrder,
    'is_required': isRequired ? 1 : 0,
    'options_payload': options,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'synced': synced ? 1 : 0,
  };

  factory EngageSurveyQuestion.fromJson(Map<String, dynamic> json) {
    return EngageSurveyQuestion(
      id: (json['id'] as String?) ?? '',
      surveyId: (json['survey_id'] as String?) ?? '',
      questionText: (json['question_text'] as String?) ?? '',
      questionType:
          (json['question_type'] as String?) ?? SurveyQuestionType.shortText,
      sortOrder: _readInt(json['sort_order']),
      isRequired: _readBool(json['is_required']),
      options: _readStringList(json['options_payload']),
      createdAt: _readDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updated_at']) ?? DateTime.now(),
      synced: _readBool(json['synced']),
    );
  }
}

class EngageSurvey {
  const EngageSurvey({
    required this.id,
    required this.title,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.questions = const [],
    this.synced = false,
  });

  final String id;
  final String title;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<EngageSurveyQuestion> questions;
  final bool synced;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'is_active': isActive ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'synced': synced ? 1 : 0,
    'questions': questions.map((question) => question.toJson()).toList(),
  };

  factory EngageSurvey.fromJson(Map<String, dynamic> json) {
    final rawQuestions = json['questions'];
    final questions = rawQuestions is List
        ? rawQuestions
              .whereType<Map>()
              .map(
                (row) => EngageSurveyQuestion.fromJson(
                  row.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList()
        : const <EngageSurveyQuestion>[];

    return EngageSurvey(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      isActive: _readBool(json['is_active']),
      createdAt: _readDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updated_at']) ?? DateTime.now(),
      questions: questions,
      synced: _readBool(json['synced']),
    );
  }
}

class SurveyAnswerInput {
  const SurveyAnswerInput({
    required this.questionId,
    this.answerText,
    this.answerNumeric,
    this.answerBool,
  });

  final String questionId;
  final String? answerText;
  final double? answerNumeric;
  final bool? answerBool;

  Map<String, dynamic> toJson() => {
    'question_id': questionId,
    'answer_text': answerText,
    'answer_numeric': answerNumeric,
    'answer_bool': answerBool,
  };
}

class SurveySubmissionInput {
  const SurveySubmissionInput({
    required this.surveyId,
    required this.answers,
    this.customerId,
    this.channel,
  });

  final String surveyId;
  final String? customerId;
  final String? channel;
  final List<SurveyAnswerInput> answers;

  Map<String, dynamic> toJson() => {
    'survey_id': surveyId,
    'customer_id': customerId,
    'channel': channel,
    'answers': answers.map((answer) => answer.toJson()).toList(),
  };
}

class EngageSurveyAnalytics {
  const EngageSurveyAnalytics({
    required this.responseRate,
    required this.customerSatisfaction,
    required this.responsesTotal,
    required this.topChurnReasons,
    required this.topRecoveryIncentives,
    required this.staffRatings,
  });

  final double responseRate;
  final double customerSatisfaction;
  final int responsesTotal;
  final List<String> topChurnReasons;
  final List<String> topRecoveryIncentives;
  final List<String> staffRatings;

  factory EngageSurveyAnalytics.fromJson(Map<String, dynamic> json) {
    return EngageSurveyAnalytics(
      responseRate: _readDouble(json['response_rate']),
      customerSatisfaction: _readDouble(json['customer_satisfaction']),
      responsesTotal: _readInt(json['responses_total']),
      topChurnReasons: _readStringList(json['top_churn_reasons']),
      topRecoveryIncentives: _readStringList(json['top_recovery_incentives']),
      staffRatings: _readStringList(json['staff_ratings']),
    );
  }
}

class EngageAccess {
  const EngageAccess({
    required this.canViewRisk,
    required this.canManageRecovery,
    required this.canManageVisits,
    required this.canManageSurveys,
  });

  final bool canViewRisk;
  final bool canManageRecovery;
  final bool canManageVisits;
  final bool canManageSurveys;

  bool get isBlocked => !canViewRisk;

  bool get isReadOnly =>
      canViewRisk &&
      !canManageRecovery &&
      !canManageVisits &&
      !canManageSurveys;
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

bool _readBool(Object? value) {
  if (value is bool) return value;
  if (value is int) return value == 1;
  if (value is num) return value.toInt() == 1;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

DateTime? _readDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is String) {
    final ms = int.tryParse(value);
    if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.tryParse(value);
  }
  return null;
}

Map<String, dynamic>? _readMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

double _readDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

List<String> _readStringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    if (!(trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      return const [];
    }
    final body = trimmed.substring(1, trimmed.length - 1).trim();
    if (body.isEmpty) return const [];
    return body
        .split(',')
        .map((item) => item.trim().replaceAll('"', '').replaceAll("'", ''))
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}
