import '../../../core/network/json_api_client.dart';
import '../domain/engage_models.dart';

class EngageApi {
  const EngageApi(this._client, this._resolveAccessToken);

  final JsonApiClient _client;
  final Future<String?> Function() _resolveAccessToken;

  Future<EngageDashboardData> getDashboard() async {
    final token = await _requireToken();
    final response = await _client.get('/engage/dashboard', bearerToken: token);
    final row = _asMap(response.data) ?? <String, dynamic>{};
    return EngageDashboardData(
      customersActive: _asInt(row['customers_active']),
      customersAtRisk: _asInt(row['customers_at_risk']),
      criticalCustomers: _asInt(row['critical_customers']),
      revenueAtRisk: _asDouble(row['revenue_at_risk']),
      recoveredCustomers: _asInt(row['recovered_customers']),
    );
  }

  Future<List<RecoveryQueueItem>> getRecoveryQueue({int limit = 20}) async {
    final token = await _requireToken();
    final response = await _client.get(
      '/engage/recovery-queue',
      bearerToken: token,
      queryParameters: {'limit': limit},
    );

    final rows = _asMapList(response.data);
    return rows
        .map(
          (row) => RecoveryQueueItem(
            customerId: (row['customer_id'] as String?) ?? '',
            customerName: (row['customer_name'] as String?) ?? 'Cliente',
            daysSinceVisit: _asInt(row['days_since_visit']),
            riskLevel: (row['risk_level'] as String?) ?? EngageRiskLevel.yellow,
            priorityScore: _asInt(row['priority']),
            totalSpent: _asDouble(row['total_spent']),
            totalPoints: _asInt(row['total_points']),
            recommendedPriority: _asInt(row['priority']) >= 45
                ? RecoveryTaskPriority.high
                : _asInt(row['priority']) >= 25
                ? RecoveryTaskPriority.medium
                : RecoveryTaskPriority.low,
            lastVisitAt: _asDateTime(row['last_visit_at']),
          ),
        )
        .toList();
  }

  Future<RecoveryTask> createTask({
    required String customerId,
    required String priority,
    DateTime? dueAt,
    String? notes,
  }) async {
    final token = await _requireToken();
    final response = await _client.post(
      '/engage/task',
      bearerToken: token,
      body: {
        'customer_id': customerId,
        'priority': priority,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'notes': notes,
      },
    );
    return RecoveryTask.fromJson(_asMap(response.data) ?? {});
  }

  Future<RecoveryTask?> completeTask(String taskId) async {
    final token = await _requireToken();
    final response = await _client.post(
      '/engage/task/complete',
      bearerToken: token,
      body: {'task_id': taskId},
    );
    final data = _asMap(response.data);
    if (data == null || data.isEmpty) return null;
    return RecoveryTask.fromJson(data);
  }

  Future<RecoveryActionLog> logAction({
    required String customerId,
    required String actionType,
    String? taskId,
    Map<String, dynamic>? payload,
  }) async {
    final token = await _requireToken();
    final response = await _client.post(
      '/engage/action',
      bearerToken: token,
      body: {
        'customer_id': customerId,
        'task_id': taskId,
        'action_type': actionType,
        'payload': payload,
      },
    );
    return RecoveryActionLog.fromJson(_asMap(response.data) ?? {});
  }

  Future<VisitReport> submitVisitReport({
    required String customerId,
    required String result,
    required DateTime visitedAt,
    String? taskId,
    String? notes,
  }) async {
    final token = await _requireToken();
    final response = await _client.post(
      '/engage/visit-report',
      bearerToken: token,
      body: {
        'customer_id': customerId,
        'task_id': taskId,
        'result': result,
        'visited_at': visitedAt.millisecondsSinceEpoch,
        'notes': notes,
      },
    );
    return VisitReport.fromJson(_asMap(response.data) ?? {});
  }

  Future<List<EngageSurvey>> getSurveys() async {
    final token = await _requireToken();
    final response = await _client.get('/engage/surveys', bearerToken: token);
    final rows = _asMapList(response.data);
    return rows.map((row) {
      final withQuestions = Map<String, dynamic>.from(row);
      final rawQuestions = row['questions'];
      if (rawQuestions is List) {
        withQuestions['questions'] = rawQuestions
            .whereType<Map>()
            .map(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList();
      }
      return EngageSurvey.fromJson(withQuestions);
    }).toList();
  }

  Future<EngageSurvey> createSurvey({
    required String title,
    String? description,
    required List<EngageSurveyQuestion> questions,
  }) async {
    final token = await _requireToken();
    final response = await _client.post(
      '/engage/surveys',
      bearerToken: token,
      body: {
        'title': title,
        'description': description,
        'questions': questions
            .map(
              (question) => {
                'question_text': question.questionText,
                'question_type': question.questionType,
                'is_required': question.isRequired,
                'sort_order': question.sortOrder,
                'options_payload': question.options,
              },
            )
            .toList(),
      },
    );
    return EngageSurvey.fromJson(_asMap(response.data) ?? {});
  }

  Future<String> submitSurveyResponse(SurveySubmissionInput submission) async {
    final token = await _requireToken();
    final response = await _client.post(
      '/engage/survey-response',
      bearerToken: token,
      body: submission.toJson(),
    );
    final data = _asMap(response.data) ?? const <String, dynamic>{};
    return (data['response_id'] as String?) ?? '';
  }

  Future<EngageSurveyAnalytics> getSurveyAnalytics() async {
    final token = await _requireToken();
    final response = await _client.get('/engage/analytics', bearerToken: token);
    return EngageSurveyAnalytics.fromJson(_asMap(response.data) ?? {});
  }

  Future<String> _requireToken() async {
    final token = await _resolveAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Missing access token for Engage API');
    }
    return token;
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  DateTime? _asDateTime(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String) {
      final ms = int.tryParse(value);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime.tryParse(value);
    }
    return null;
  }
}
