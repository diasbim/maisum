import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../sync/data/sync_dao.dart';
import '../../sync/domain/sync_item.dart';
import '../domain/engage_models.dart';
import 'engage_api.dart';
import 'engage_dao.dart';

enum EngageSaveStatus { saved, queued }

class EngageSaveResult<T> {
  const EngageSaveResult.saved(this.value) : status = EngageSaveStatus.saved;

  const EngageSaveResult.queued(this.value) : status = EngageSaveStatus.queued;

  final T value;
  final EngageSaveStatus status;

  bool get isSaved => status == EngageSaveStatus.saved;
  bool get isQueued => status == EngageSaveStatus.queued;
}

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

  Future<List<RecoveryTaskQueueItem>> getOpenRecoveryTasks({
    int limit = 50,
  }) =>
      _dao.getOpenRecoveryTasks(limit: limit);

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
    return (await createRecoveryTaskWithResult(
      customerId: customerId,
      priority: priority,
      dueAt: dueAt,
      notes: notes,
    ))
        .task;
  }

  Future<RecoveryTaskCreationResult> createRecoveryTaskWithResult({
    required String customerId,
    required String priority,
    DateTime? dueAt,
    String? notes,
  }) async {
    final taskId = _uuid.v4();
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remoteResult = await api.createTask(
          taskId: taskId,
          customerId: customerId,
          priority: priority,
          dueAt: dueAt,
          notes: notes,
        );
        final remoteTask = remoteResult.task;
        final task = await _dao.upsertRecoveryTask(
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
        return RecoveryTaskCreationResult(
          task: task,
          outcome: remoteResult.outcome,
        );
      } catch (error) {
        if (!_shouldQueueAfterRemoteFailure(error)) rethrow;
      }
    }

    if (await _dao.hasOpenRecoveryTask(customerId)) {
      throw const RecoveryTaskAlreadyOpenException();
    }
    final task = await _dao.createRecoveryTask(
      taskId: taskId,
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

    return RecoveryTaskCreationResult(
      task: task,
      outcome: RecoveryTaskCreationOutcome.created,
    );
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
    String? actionId,
    required String customerId,
    required String actionType,
    String? taskId,
    Map<String, dynamic>? payload,
  }) async {
    return (await logRecoveryActionWithResult(
      actionId: actionId,
      customerId: customerId,
      actionType: actionType,
      taskId: taskId,
      payload: payload,
    ))
        .value;
  }

  Future<EngageSaveResult<RecoveryActionLog>> logRecoveryActionWithResult({
    String? actionId,
    required String customerId,
    required String actionType,
    String? taskId,
    Map<String, dynamic>? payload,
  }) async {
    final stableActionId = _stableId(actionId);
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remoteAction = await api.logAction(
          actionId: stableActionId,
          customerId: customerId,
          actionType: actionType,
          taskId: taskId,
          payload: payload,
        );
        if (remoteAction.id.isEmpty) {
          throw StateError('A resposta da ação de recuperação é inválida.');
        }
        return EngageSaveResult.saved(await _dao.upsertRecoveryAction(
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
        ));
      } catch (error) {
        if (!_shouldQueueAfterRemoteFailure(error)) rethrow;
      }
    }

    final action = await _dao.insertRecoveryAction(
      forcedId: stableActionId,
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

    return EngageSaveResult.queued(action);
  }

  Future<VisitReport> submitVisitReport({
    String? reportId,
    required String customerId,
    required String result,
    required DateTime visitedAt,
    String? taskId,
    String? notes,
  }) async {
    return (await submitVisitReportWithResult(
      reportId: reportId,
      customerId: customerId,
      result: result,
      visitedAt: visitedAt,
      taskId: taskId,
      notes: notes,
    ))
        .value;
  }

  Future<EngageSaveResult<VisitReport>> submitVisitReportWithResult({
    String? reportId,
    required String customerId,
    required String result,
    required DateTime visitedAt,
    String? taskId,
    String? notes,
  }) async {
    final stableReportId = _stableId(reportId);
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final remoteReport = await api.submitVisitReport(
          reportId: stableReportId,
          customerId: customerId,
          result: result,
          visitedAt: visitedAt,
          taskId: taskId,
          notes: notes,
        );
        if (remoteReport.id.isEmpty) {
          throw StateError('A resposta do relatório de visita é inválida.');
        }
        return EngageSaveResult.saved(await _dao.upsertVisitReport(
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
        ));
      } catch (error) {
        if (!_shouldQueueAfterRemoteFailure(error)) rethrow;
      }
    }

    final report = await _dao.insertVisitReport(
      forcedId: stableReportId,
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

    return EngageSaveResult.queued(report);
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
      throw StateError('Cada questionário suporta no máximo 5 perguntas.');
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
    return (await submitSurveyResponseWithResult(submission)).value;
  }

  Future<EngageSaveResult<String>> submitSurveyResponseWithResult(
    SurveySubmissionInput submission,
  ) async {
    final stableSubmission = _withStableSurveyIds(submission);
    final api = _api;
    if (_useRemote && api != null) {
      try {
        final responseId = await api.submitSurveyResponse(stableSubmission);
        if (responseId.isEmpty) {
          throw StateError('A resposta do questionário é inválida.');
        }
        await _dao.submitSurveyResponse(
          stableSubmission,
          synced: true,
          forcedResponseId: responseId,
        );
        return EngageSaveResult.saved(responseId);
      } catch (error) {
        if (!_shouldQueueAfterRemoteFailure(error)) rethrow;
      }
    }

    final responseId = await _dao.submitSurveyResponse(
      stableSubmission,
      synced: false,
      forcedResponseId: stableSubmission.responseId,
    );
    await _syncDao.enqueue(
      SyncItem(
        id: _uuid.v4(),
        operation: 'create',
        entityType: 'survey_response',
        entityId: responseId,
        payload: jsonEncode({
          ...stableSubmission.toJson(),
          'id': responseId,
          'merchant_id': _dao.merchantId,
          ..._actorFields(),
        }),
        createdAt: DateTime.now(),
      ),
    );
    return EngageSaveResult.queued(responseId);
  }

  bool _shouldQueueAfterRemoteFailure(Object error) {
    return error is NetworkException ||
        error is UnknownException ||
        error is ServerException && error.statusCode >= 500;
  }

  String _stableId(String? id) {
    final normalized = id?.trim();
    return normalized == null || normalized.isEmpty ? _uuid.v4() : normalized;
  }

  SurveySubmissionInput _withStableSurveyIds(
    SurveySubmissionInput submission,
  ) {
    return SurveySubmissionInput(
      responseId: _stableId(submission.responseId),
      surveyId: submission.surveyId,
      customerId: submission.customerId,
      channel: submission.channel,
      answers: submission.answers
          .map(
            (answer) => SurveyAnswerInput(
              id: _stableId(answer.id),
              questionId: answer.questionId,
              answerText: answer.answerText,
              answerNumeric: answer.answerNumeric,
              answerBool: answer.answerBool,
            ),
          )
          .toList(),
    );
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
