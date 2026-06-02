import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/engage_models.dart';
import '../services/engage_risk_service.dart';

class EngageDao {
  EngageDao(this._db, {this.merchantId, EngageRiskService? riskService})
    : _riskService = riskService ?? const EngageRiskService();

  final AppDatabase _db;
  final String? merchantId;
  final EngageRiskService _riskService;
  static const _uuid = Uuid();

  Future<List<CustomerRiskScore>> recalculateRiskScores({DateTime? now}) async {
    final db = await _db.database;
    final nowDate = now ?? DateTime.now();

    final rows = await db.rawQuery(
      merchantId == null
          ? '''
            SELECT c.id AS customer_id,
                   MAX(s.created_at) AS last_visit_at,
                   COALESCE(SUM(s.amount), 0) AS total_spent,
                   c.total_points AS total_points,
                   c.created_at AS customer_created_at
            FROM customers c
            LEFT JOIN sales s ON s.customer_id = c.id
            GROUP BY c.id, c.total_points, c.created_at
          '''
          : '''
            SELECT c.id AS customer_id,
                   MAX(s.created_at) AS last_visit_at,
                   COALESCE(SUM(s.amount), 0) AS total_spent,
                   c.total_points AS total_points,
                   c.created_at AS customer_created_at
            FROM customers c
            LEFT JOIN sales s
              ON s.customer_id = c.id AND s.merchant_id = c.merchant_id
            WHERE c.merchant_id = ?
            GROUP BY c.id, c.total_points, c.created_at
          ''',
      merchantId == null ? const [] : [merchantId],
    );

    final scores = <CustomerRiskScore>[];
    for (final row in rows) {
      final customerId = (row['customer_id'] as String?) ?? '';
      if (customerId.isEmpty) continue;

      final lastVisitAt =
          _toDateTime(row['last_visit_at']) ??
          _toDateTime(row['customer_created_at']) ??
          nowDate;
      final daysSinceVisit = _riskService.daysSinceVisit(lastVisitAt, nowDate);
      final riskLevel = _riskService.riskLevelFromDays(daysSinceVisit);
      final totalSpent = (row['total_spent'] as num?)?.toDouble() ?? 0;
      final totalPoints = (row['total_points'] as num?)?.toInt() ?? 0;
      final priority = _riskService.priorityScore(
        riskLevel: riskLevel,
        totalSpent: totalSpent,
        totalPoints: totalPoints,
      );
      final id = merchantId == null ? customerId : '${merchantId}_$customerId';

      final score = CustomerRiskScore(
        id: id,
        customerId: customerId,
        daysSinceVisit: daysSinceVisit,
        riskLevel: riskLevel,
        priority: priority,
        updatedAt: nowDate,
        synced: false,
      );

      await db.insert('customer_risk_scores', {
        ...score.toJson(),
        'merchant_id': merchantId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      scores.add(score);
    }

    return scores;
  }

  Future<EngageDashboardData> getDashboardData() async {
    final db = await _db.database;

    final rows = await db.rawQuery(
      merchantId == null
          ? '''
            SELECT
              SUM(CASE WHEN crs.risk_level = 'green' THEN 1 ELSE 0 END) AS customers_active,
              SUM(CASE WHEN crs.risk_level IN ('yellow', 'orange', 'red') THEN 1 ELSE 0 END) AS customers_at_risk,
              SUM(CASE WHEN crs.risk_level = 'red' THEN 1 ELSE 0 END) AS critical_customers,
              SUM(CASE WHEN crs.risk_level IN ('orange', 'red') THEN COALESCE(rm.total_spent, 0) ELSE 0 END) AS revenue_at_risk,
              SUM(CASE WHEN COALESCE(rm.recovered, 0) = 1 THEN 1 ELSE 0 END) AS recovered_customers
            FROM customer_risk_scores crs
            LEFT JOIN retention_metrics rm ON rm.customer_id = crs.customer_id
          '''
          : '''
            SELECT
              SUM(CASE WHEN crs.risk_level = 'green' THEN 1 ELSE 0 END) AS customers_active,
              SUM(CASE WHEN crs.risk_level IN ('yellow', 'orange', 'red') THEN 1 ELSE 0 END) AS customers_at_risk,
              SUM(CASE WHEN crs.risk_level = 'red' THEN 1 ELSE 0 END) AS critical_customers,
              SUM(CASE WHEN crs.risk_level IN ('orange', 'red') THEN COALESCE(rm.total_spent, 0) ELSE 0 END) AS revenue_at_risk,
              SUM(CASE WHEN COALESCE(rm.recovered, 0) = 1 THEN 1 ELSE 0 END) AS recovered_customers
            FROM customer_risk_scores crs
            LEFT JOIN retention_metrics rm
              ON rm.customer_id = crs.customer_id AND rm.merchant_id = crs.merchant_id
            WHERE crs.merchant_id = ?
          ''',
      merchantId == null ? const [] : [merchantId],
    );

    final row = rows.isNotEmpty ? rows.first : const <String, Object?>{};
    return EngageDashboardData(
      customersActive: (row['customers_active'] as num?)?.toInt() ?? 0,
      customersAtRisk: (row['customers_at_risk'] as num?)?.toInt() ?? 0,
      criticalCustomers: (row['critical_customers'] as num?)?.toInt() ?? 0,
      revenueAtRisk: (row['revenue_at_risk'] as num?)?.toDouble() ?? 0,
      recoveredCustomers: (row['recovered_customers'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<RecoveryQueueItem>> getRecoveryQueue({int limit = 20}) async {
    final db = await _db.database;

    final rows = await db.rawQuery(
      merchantId == null
          ? '''
            SELECT crs.customer_id,
                   c.name AS customer_name,
                   crs.days_since_visit,
                   crs.risk_level,
                   crs.priority,
                   COALESCE(rm.total_spent, 0) AS total_spent,
                   COALESCE(c.total_points, 0) AS total_points,
                   rm.last_visit_at
            FROM customer_risk_scores crs
            INNER JOIN customers c ON c.id = crs.customer_id
            LEFT JOIN retention_metrics rm ON rm.customer_id = crs.customer_id
            WHERE crs.risk_level IN ('yellow', 'orange', 'red')
            ORDER BY COALESCE(rm.total_spent, 0) DESC,
                     crs.priority DESC,
                     COALESCE(c.total_points, 0) DESC
            LIMIT ?
          '''
          : '''
            SELECT crs.customer_id,
                   c.name AS customer_name,
                   crs.days_since_visit,
                   crs.risk_level,
                   crs.priority,
                   COALESCE(rm.total_spent, 0) AS total_spent,
                   COALESCE(c.total_points, 0) AS total_points,
                   rm.last_visit_at
            FROM customer_risk_scores crs
            INNER JOIN customers c
              ON c.id = crs.customer_id AND c.merchant_id = crs.merchant_id
            LEFT JOIN retention_metrics rm
              ON rm.customer_id = crs.customer_id AND rm.merchant_id = crs.merchant_id
            WHERE crs.merchant_id = ?
              AND crs.risk_level IN ('yellow', 'orange', 'red')
            ORDER BY COALESCE(rm.total_spent, 0) DESC,
                     crs.priority DESC,
                     COALESCE(c.total_points, 0) DESC
            LIMIT ?
          ''',
      merchantId == null ? [limit] : [merchantId, limit],
    );

    return rows.map((row) {
      final priorityScore = (row['priority'] as num?)?.toInt() ?? 0;
      return RecoveryQueueItem(
        customerId: (row['customer_id'] as String?) ?? '',
        customerName: (row['customer_name'] as String?) ?? 'Cliente',
        daysSinceVisit: (row['days_since_visit'] as num?)?.toInt() ?? 0,
        riskLevel: (row['risk_level'] as String?) ?? EngageRiskLevel.yellow,
        priorityScore: priorityScore,
        totalSpent: (row['total_spent'] as num?)?.toDouble() ?? 0,
        totalPoints: (row['total_points'] as num?)?.toInt() ?? 0,
        recommendedPriority: _riskService.taskPriorityFromScore(priorityScore),
        lastVisitAt: _toDateTime(row['last_visit_at']),
      );
    }).toList();
  }

  Future<RecoveryTask> createRecoveryTask({
    required String customerId,
    required String priority,
    DateTime? dueAt,
    String? notes,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final task = RecoveryTask(
      id: _uuid.v4(),
      customerId: customerId,
      priority: RecoveryTaskPriority.values.contains(priority)
          ? priority
          : RecoveryTaskPriority.medium,
      status: RecoveryTaskStatus.open,
      dueAt: dueAt,
      notes: notes,
      createdAt: now,
      updatedAt: now,
      synced: false,
    );

    await db.insert('recovery_tasks', {
      ...task.toJson(),
      'merchant_id': merchantId,
    });

    return task;
  }

  Future<RecoveryTask> upsertRecoveryTask(RecoveryTask task) async {
    final db = await _db.database;
    await db.insert('recovery_tasks', {
      ...task.toJson(),
      'merchant_id': merchantId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return task;
  }

  Future<RecoveryTask?> completeRecoveryTask(String taskId) async {
    final db = await _db.database;
    await db.update(
      'recovery_tasks',
      {
        'status': RecoveryTaskStatus.completed,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
      },
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([taskId]),
    );

    final rows = await db.query(
      'recovery_tasks',
      where: _withMerchantScope('id = ?'),
      whereArgs: _withMerchantArgs([taskId]),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RecoveryTask.fromJson(rows.first);
  }

  Future<RecoveryActionLog> insertRecoveryAction({
    required String customerId,
    required String actionType,
    String? taskId,
    Map<String, dynamic>? payload,
    bool synced = false,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final action = RecoveryActionLog(
      id: _uuid.v4(),
      customerId: customerId,
      actionType: actionType,
      taskId: taskId,
      payload: payload,
      createdAt: now,
      updatedAt: now,
      synced: synced,
    );

    await db.insert('recovery_actions', {
      ...action.toJson(),
      'merchant_id': merchantId,
    });
    return action;
  }

  Future<RecoveryActionLog> upsertRecoveryAction(
    RecoveryActionLog action,
  ) async {
    final db = await _db.database;
    await db.insert('recovery_actions', {
      ...action.toJson(),
      'merchant_id': merchantId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return action;
  }

  Future<VisitReport> insertVisitReport({
    required String customerId,
    required String result,
    required DateTime visitedAt,
    String? taskId,
    String? notes,
    bool synced = false,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final report = VisitReport(
      id: _uuid.v4(),
      customerId: customerId,
      result: result,
      visitedAt: visitedAt,
      createdAt: now,
      updatedAt: now,
      taskId: taskId,
      notes: notes,
      synced: synced,
    );

    await db.insert('visit_reports', {
      ...report.toJson(),
      'merchant_id': merchantId,
    });
    return report;
  }

  Future<VisitReport> upsertVisitReport(VisitReport report) async {
    final db = await _db.database;
    await db.insert('visit_reports', {
      ...report.toJson(),
      'merchant_id': merchantId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return report;
  }

  Future<List<EngageSurvey>> getActiveSurveys() async {
    final db = await _db.database;
    final surveyRows = await db.query(
      'surveys',
      where: _withMerchantScope('is_active = 1'),
      whereArgs: _withMerchantArgs(const []),
      orderBy: 'updated_at DESC',
    );

    if (surveyRows.isEmpty) return const [];

    final surveys = <EngageSurvey>[];
    for (final row in surveyRows) {
      final surveyId = (row['id'] as String?) ?? '';
      final questionRows = await db.query(
        'survey_questions',
        where: _withMerchantScope('survey_id = ?'),
        whereArgs: _withMerchantArgs([surveyId]),
        orderBy: 'sort_order ASC',
      );

      surveys.add(
        EngageSurvey(
          id: surveyId,
          title: (row['title'] as String?) ?? '',
          description: row['description'] as String?,
          isActive: (row['is_active'] as int? ?? 0) == 1,
          createdAt: _toDateTime(row['created_at']) ?? DateTime.now(),
          updatedAt: _toDateTime(row['updated_at']) ?? DateTime.now(),
          synced: (row['synced'] as int? ?? 0) == 1,
          questions: questionRows
              .map(
                (question) => EngageSurveyQuestion.fromJson({
                  ...question,
                  'options_payload': _decodeOptions(
                    question['options_payload'],
                  ),
                }),
              )
              .toList(),
        ),
      );
    }

    return surveys;
  }

  Future<int> countActiveSurveys() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) AS total FROM surveys WHERE is_active = 1'
          : 'SELECT COUNT(*) AS total FROM surveys WHERE merchant_id = ? AND is_active = 1',
      merchantId == null ? const [] : [merchantId],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<EngageSurvey> createSurvey({
    required String title,
    String? description,
    required List<EngageSurveyQuestion> questions,
    bool synced = false,
    String? forcedId,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final id = forcedId ?? _uuid.v4();

    final survey = EngageSurvey(
      id: id,
      title: title,
      description: description,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      synced: synced,
      questions: questions
          .asMap()
          .entries
          .map(
            (entry) => EngageSurveyQuestion(
              id: entry.value.id.isEmpty ? _uuid.v4() : entry.value.id,
              surveyId: id,
              questionText: entry.value.questionText,
              questionType: entry.value.questionType,
              sortOrder: entry.key,
              isRequired: entry.value.isRequired,
              options: entry.value.options,
              createdAt: now,
              updatedAt: now,
              synced: synced,
            ),
          )
          .toList(),
    );

    await db.transaction((txn) async {
      await txn.insert('surveys', {
        'id': survey.id,
        'merchant_id': merchantId,
        'title': survey.title,
        'description': survey.description,
        'is_active': survey.isActive ? 1 : 0,
        'created_at': survey.createdAt.millisecondsSinceEpoch,
        'updated_at': survey.updatedAt.millisecondsSinceEpoch,
        'synced': survey.synced ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final question in survey.questions) {
        await txn.insert('survey_questions', {
          'id': question.id,
          'merchant_id': merchantId,
          'survey_id': survey.id,
          'question_text': question.questionText,
          'question_type': question.questionType,
          'sort_order': question.sortOrder,
          'is_required': question.isRequired ? 1 : 0,
          'options_payload': jsonEncode(question.options),
          'created_at': question.createdAt.millisecondsSinceEpoch,
          'updated_at': question.updatedAt.millisecondsSinceEpoch,
          'synced': question.synced ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    return survey;
  }

  Future<String> submitSurveyResponse(
    SurveySubmissionInput submission, {
    bool synced = false,
    String? forcedResponseId,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final responseId = forcedResponseId ?? _uuid.v4();

    await db.transaction((txn) async {
      await txn.insert('survey_responses', {
        'id': responseId,
        'merchant_id': merchantId,
        'survey_id': submission.surveyId,
        'customer_id': submission.customerId,
        'submitted_at': now.millisecondsSinceEpoch,
        'channel': submission.channel,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final answer in submission.answers) {
        await txn.insert('survey_response_answers', {
          'id': _uuid.v4(),
          'merchant_id': merchantId,
          'response_id': responseId,
          'question_id': answer.questionId,
          'answer_text': answer.answerText,
          'answer_numeric': answer.answerNumeric,
          'answer_bool': answer.answerBool == null
              ? null
              : (answer.answerBool! ? 1 : 0),
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
          'synced': synced ? 1 : 0,
        });
      }
    });

    return responseId;
  }

  Future<EngageSurveyAnalytics> getSurveyAnalytics() async {
    final db = await _db.database;
    final merchantArgs = merchantId == null
        ? const <Object?>[]
        : <Object?>[merchantId];

    final surveysRows = await db.rawQuery(
      merchantId == null
          ? 'SELECT COUNT(*) AS total FROM surveys WHERE is_active = 1'
          : 'SELECT COUNT(*) AS total FROM surveys WHERE merchant_id = ? AND is_active = 1',
      merchantArgs,
    );
    final activeSurveys = surveysRows.isEmpty
        ? 0
        : ((surveysRows.first['total'] as num?)?.toInt() ?? 0);

    final responsesRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM survey_responses ${merchantId == null ? '' : 'WHERE merchant_id = ?'}',
      merchantArgs,
    );
    final responsesTotal = responsesRows.isEmpty
        ? 0
        : ((responsesRows.first['total'] as num?)?.toInt() ?? 0);

    final ratingRows = await db.rawQuery('''
      SELECT AVG(sra.answer_numeric) AS avg_rating
      FROM survey_response_answers sra
      ${merchantId == null ? '' : 'WHERE sra.merchant_id = ?'}
      ''', merchantArgs);
    final avgRating = ratingRows.isEmpty
        ? 0.0
        : ((ratingRows.first['avg_rating'] as num?)?.toDouble() ?? 0.0);

    final reasonsRows = await db.rawQuery('''
      SELECT COALESCE(answer_text, '') AS answer_text, COUNT(*) AS c
      FROM survey_response_answers
      ${merchantId == null ? '' : 'WHERE merchant_id = ?'}
      GROUP BY answer_text
      ORDER BY c DESC
      LIMIT 3
      ''', merchantArgs);

    final responseRate = activeSurveys == 0
        ? 0.0
        : (responsesTotal / activeSurveys) * 100;

    final topReasons = reasonsRows
        .map((row) => (row['answer_text'] as String?) ?? '')
        .where((text) => text.trim().isNotEmpty)
        .toList();

    return EngageSurveyAnalytics(
      responseRate: responseRate,
      customerSatisfaction: avgRating,
      responsesTotal: responsesTotal,
      topChurnReasons: topReasons,
      topRecoveryIncentives: topReasons,
      staffRatings: topReasons,
    );
  }

  String _withMerchantScope(String clause) {
    if (merchantId == null) return clause;
    return 'merchant_id = ? AND ($clause)';
  }

  List<Object?> _withMerchantArgs(List<Object?> args) {
    if (merchantId == null) return args;
    return [merchantId, ...args];
  }

  DateTime? _toDateTime(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    if (raw is String) {
      final asInt = int.tryParse(raw);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(raw);
    }
    return null;
  }

  List<String> _decodeOptions(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList();
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }
}
