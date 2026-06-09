import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/engage_models.dart';
import 'engage_api.dart';
import 'engage_dao.dart';

class EngageRepository {
  EngageRepository(
    this._dao,
    this._syncDao, {
    this.appUserId,
    EngageApi? api,
    bool useRemote = false,
  })  : _api = api,
        _useRemote = useRemote;

  final EngageDao _dao;
  final SyncDao _syncDao;
  final String? appUserId;
  final EngageApi? _api;
  final bool _useRemote;
  static const _uuid = Uuid();

  Map<String, dynamic> _actorFields({bool includeCreated = true}) {
    final actor = appUserId?.trim();
    if (actor == null || actor.isEmpty) {
      return const {};
    }
    return {
      if (includeCreated) 'created_by_app_user_id': actor,
      'updated_by_app_user_id': actor,
    };
  }

  Future<EngageDashboardData> loadDashboard({
    bool refreshRiskScores = true,
  }) async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        return await api.getDashboard();
      } catch (_) {
        // Falls back to local calculations when backend is unavailable.
      }
    }
    if (refreshRiskScores) {
      await recalculateRiskScores();
    }
    return _dao.getDashboardData();
  }

  Future<List<RecoveryQueueItem>> getRecoveryQueue({
    int limit = 20,
    bool refreshRiskScores = false,
  }) async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        return await api.getRecoveryQueue(limit: limit);
      } catch (_) {
        // Falls back to local queue when backend is unavailable.
      }
    }
    if (refreshRiskScores) {
      await recalculateRiskScores();
    }
    return _dao.getRecoveryQueue(limit: limit);
  }

  Future<List<CustomerRiskScore>> recalculateRiskScores() async {
    final scores = await _dao.recalculateRiskScores();
    for (final score in scores) {
      await _syncDao.enqueue(
        SyncItem(
          id: _uuid.v4(),
          operation: 'update',
          entityType: 'customer_risk_score',
          entityId: score.id,
          payload: jsonEncode({
            ...score.toJson(),
            'merchant_id': _dao.merchantId,
            ..._actorFields(),
          }),
          createdAt: DateTime.now(),
        ),
      );
    }
    return scores;
  }

  Future<RecoveryTask> createRecoveryTask({
    required String customerId,
    required String priority,
    DateTime? dueAt,
    String? notes,
  }) async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remoteTask = await api.createTask(
          customerId: customerId,
          priority: priority,
          dueAt: dueAt,
          notes: notes,
        );
        return _dao.upsertRecoveryTask(
          RecoveryTask(
            id: remoteTask.id,
            customerId: remoteTask.customerId,
            priority: remoteTask.priority,
            status: remoteTask.status,
            dueAt: remoteTask.dueAt,
            notes: remoteTask.notes,
            createdAt: remoteTask.createdAt,
            updatedAt: remoteTask.updatedAt,
            synced: true,
          ),
        );
      } catch (_) {
        // Falls back to local queue mode.
      }
    }

    final task = await _dao.createRecoveryTask(
      customerId: customerId,
      priority: priority,
      dueAt: dueAt,
      notes: notes,
    );

    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'recovery_task',
        entityId: task.id,
        payload: jsonEncode({
          ...task.toJson(),
          'merchant_id': _dao.merchantId,
          ..._actorFields(),
        }),
        createdAt: DateTime.now(),
      ),
    );

    return task;
  }

  Future<RecoveryTask?> completeRecoveryTask(String taskId) async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remoteTask = await api.completeTask(taskId);
        if (remoteTask == null) return null;
        return _dao.upsertRecoveryTask(
          RecoveryTask(
            id: remoteTask.id,
            customerId: remoteTask.customerId,
            priority: remoteTask.priority,
            status: remoteTask.status,
            dueAt: remoteTask.dueAt,
            notes: remoteTask.notes,
            createdAt: remoteTask.createdAt,
            updatedAt: remoteTask.updatedAt,
            synced: true,
          ),
        );
      } catch (_) {
        // Falls back to local queue mode.
      }
    }

    final task = await _dao.completeRecoveryTask(taskId);
    if (task == null) return null;

    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'update',
        entityType: 'recovery_task',
        entityId: task.id,
        payload: jsonEncode({
          ...task.toJson(),
          'merchant_id': _dao.merchantId,
          ..._actorFields(includeCreated: false),
        }),
        createdAt: DateTime.now(),
      ),
    );

    return task;
  }

  Future<RecoveryActionLog> logRecoveryAction({
    required String customerId,
    required String actionType,
    String? taskId,
    Map<String, dynamic>? payload,
  }) async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remoteAction = await api.logAction(
          customerId: customerId,
          actionType: actionType,
          taskId: taskId,
          payload: payload,
        );
        return _dao.upsertRecoveryAction(
          RecoveryActionLog(
            id: remoteAction.id,
            customerId: remoteAction.customerId,
            actionType: remoteAction.actionType,
            taskId: remoteAction.taskId,
            payload: remoteAction.payload,
            createdAt: remoteAction.createdAt,
            updatedAt: remoteAction.updatedAt,
            synced: true,
          ),
        );
      } catch (_) {
        // Falls back to local queue mode.
      }
    }

    final action = await _dao.insertRecoveryAction(
      customerId: customerId,
      actionType: actionType,
      taskId: taskId,
      payload: payload,
      synced: false,
    );

    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'recovery_action',
        entityId: action.id,
        payload: jsonEncode({
          ...action.toJson(),
          'merchant_id': _dao.merchantId,
          ..._actorFields(),
        }),
        createdAt: DateTime.now(),
      ),
    );

    return action;
  }

  Future<VisitReport> submitVisitReport({
    required String customerId,
    required String result,
    required DateTime visitedAt,
    String? taskId,
    String? notes,
  }) async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remoteReport = await api.submitVisitReport(
          customerId: customerId,
          result: result,
          visitedAt: visitedAt,
          taskId: taskId,
          notes: notes,
        );
        return _dao.upsertVisitReport(
          VisitReport(
            id: remoteReport.id,
            customerId: remoteReport.customerId,
            result: remoteReport.result,
            visitedAt: remoteReport.visitedAt,
            createdAt: remoteReport.createdAt,
            updatedAt: remoteReport.updatedAt,
            taskId: remoteReport.taskId,
            notes: remoteReport.notes,
            synced: true,
          ),
        );
      } catch (_) {
        // Falls back to local queue mode.
      }
    }

    final report = await _dao.insertVisitReport(
      customerId: customerId,
      result: result,
      visitedAt: visitedAt,
      taskId: taskId,
      notes: notes,
      synced: false,
    );

    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'visit_report',
        entityId: report.id,
        payload: jsonEncode({
          ...report.toJson(),
          'merchant_id': _dao.merchantId,
          ..._actorFields(),
        }),
        createdAt: DateTime.now(),
      ),
    );

    return report;
  }

  Future<List<EngageSurvey>> getSurveys() async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remote = await api.getSurveys();
        for (final survey in remote) {
          await _dao.createSurvey(
            title: survey.title,
            description: survey.description,
            questions: survey.questions,
            synced: true,
            forcedId: survey.id,
          );
        }
        return remote;
      } catch (_) {
        // Falls back to local cached surveys when backend is unavailable.
      }
    }
    return _dao.getActiveSurveys();
  }

  Future<EngageSurvey> createSurvey({
    required String title,
    String? description,
    required List<EngageSurveyQuestion> questions,
  }) async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remote = await api.createSurvey(
          title: title,
          description: description,
          questions: questions,
        );
        await _dao.createSurvey(
          title: remote.title,
          description: remote.description,
          questions: remote.questions,
          synced: true,
          forcedId: remote.id,
        );
        return remote;
      } catch (_) {
        // Falls back to local queue mode.
      }
    }

    final activeCount = await _dao.countActiveSurveys();
    if (activeCount >= 10) {
      throw StateError('Limite de 10 surveys ativos atingido.');
    }
    if (questions.length > 5) {
      throw StateError('Cada survey suporta no maximo 5 perguntas.');
    }

    final survey = await _dao.createSurvey(
      title: title,
      description: description,
      questions: questions,
      synced: false,
    );

    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'survey',
        entityId: survey.id,
        payload: jsonEncode({
          ...survey.toJson(),
          'merchant_id': _dao.merchantId,
          ..._actorFields(),
          'questions': null,
        }),
        createdAt: DateTime.now(),
      ),
    );

    for (final question in survey.questions) {
      await _syncDao.enqueue(
        SyncItem(
          id: _uuid.v4(),
          operation: 'create',
          entityType: 'survey_question',
          entityId: question.id,
          payload: jsonEncode({
            ...question.toJson(),
            'merchant_id': _dao.merchantId,
            ..._actorFields(),
          }),
          createdAt: DateTime.now(),
        ),
      );
    }

    return survey;
  }

  Future<String> submitSurveyResponse(SurveySubmissionInput submission) async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final responseId = await api.submitSurveyResponse(submission);
        if (responseId.isNotEmpty) {
          await _dao.submitSurveyResponse(
            submission,
            synced: true,
            forcedResponseId: responseId,
          );
        }
        return responseId;
      } catch (_) {
        // Falls back to local queue mode.
      }
    }

    final responseId = await _dao.submitSurveyResponse(
      submission,
      synced: false,
    );
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'survey_response',
        entityId: responseId,
        payload: jsonEncode({
          ...submission.toJson(),
          'id': responseId,
          'merchant_id': _dao.merchantId,
          ..._actorFields(),
        }),
        createdAt: DateTime.now(),
      ),
    );
    return responseId;
  }

  Future<EngageSurveyAnalytics> getSurveyAnalytics() async {
    final api = _api;
    if (_useRemote && api != null) {
      try {
        return await api.getSurveyAnalytics();
      } catch (_) {
        // Falls back to local analytics when backend is unavailable.
      }
    }
    return _dao.getSurveyAnalytics();
  }
}
