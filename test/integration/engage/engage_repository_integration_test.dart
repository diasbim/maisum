import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/errors/app_exception.dart';
import 'package:maisum/core/network/json_api_client.dart';
import 'package:maisum/features/engage/data/engage_api.dart';
import 'package:maisum/features/engage/data/engage_dao.dart';
import 'package:maisum/features/engage/data/engage_repository.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

import '../../helpers/test_database.dart';

void main() {
  late EngageRepository repository;
  late EngageDao engageDao;
  late SyncDao syncDao;

  setUp(() async {
    await setUpTestDatabase();
    syncDao = SyncDao(AppDatabase.instance, merchantId: 'merchant-1');
    engageDao = EngageDao(AppDatabase.instance, merchantId: 'merchant-1');
    repository = EngageRepository(
      engageDao,
      syncDao,
    );
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test(
    'recovery queue keeps ordering: value, then risk priority, then points',
    () async {
      final db = await AppDatabase.instance.database;
      final now = DateTime.now();

      Future<void> seedCustomer({
        required String id,
        required String name,
        required int points,
        required int daysAgo,
        required double totalSpent,
      }) async {
        final createdAt =
            now.subtract(const Duration(days: 120)).millisecondsSinceEpoch;
        final saleAt =
            now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch;

        await db.insert('customers', {
          'id': id,
          'merchant_id': 'merchant-1',
          'name': name,
          'phone': '84$id',
          'total_points': points,
          'created_at': createdAt,
          'updated_at': createdAt,
          'synced': 1,
        });

        await db.insert('sales', {
          'id': 'sale_$id',
          'merchant_id': 'merchant-1',
          'customer_id': id,
          'amount': totalSpent,
          'points': 10,
          'created_at': saleAt,
          'synced': 1,
        });

        await db.insert('retention_metrics', {
          'id': 'metric_$id',
          'merchant_id': 'merchant-1',
          'customer_id': id,
          'last_visit_at': saleAt,
          'days_inactive': daysAgo,
          'risk_level': 'risk',
          'total_visits': 1,
          'average_visit_interval': 0,
          'total_spent': totalSpent,
          'is_recurring': 0,
          'recovered': 0,
          'updated_at': saleAt,
          'synced': 1,
        });
      }

      await seedCustomer(
        id: 'a',
        name: 'Cliente A',
        points: 100,
        daysAgo: 45,
        totalSpent: 5000,
      );
      await seedCustomer(
        id: 'b',
        name: 'Cliente B',
        points: 9999,
        daysAgo: 100,
        totalSpent: 2000,
      );
      await seedCustomer(
        id: 'c',
        name: 'Cliente C',
        points: 100,
        daysAgo: 100,
        totalSpent: 1000,
      );
      await seedCustomer(
        id: 'd',
        name: 'Cliente D',
        points: 7000,
        daysAgo: 45,
        totalSpent: 1000,
      );

      await repository.recalculateRiskScores();
      final queue = await repository.getRecoveryQueue(limit: 10);

      expect(queue.map((item) => item.customerId).toList(), [
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(queue.first.riskLevel, EngageRiskLevel.yellow);
      expect(queue[1].riskLevel, EngageRiskLevel.red);
    },
  );

  test(
    'task lifecycle creates and completes task with sync queue entries',
    () async {
      final db = await AppDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert('customers', {
        'id': 'cust-1',
        'merchant_id': 'merchant-1',
        'name': 'Cliente 1',
        'phone': '841111111',
        'total_points': 500,
        'created_at': now,
        'updated_at': now,
        'synced': 1,
      });

      final created = await repository.createRecoveryTask(
        customerId: 'cust-1',
        priority: RecoveryTaskPriority.high,
        notes: 'Ligar ainda hoje',
      );

      expect(created.status, RecoveryTaskStatus.open);
      final openTasks = await repository.getOpenRecoveryTasks();
      expect(openTasks, hasLength(1));
      expect(openTasks.single.customerName, 'Cliente 1');
      expect(openTasks.single.task.priority, RecoveryTaskPriority.high);
      expect(openTasks.single.task.status, RecoveryTaskStatus.open);

      await expectLater(
        repository.createRecoveryTask(
          customerId: 'cust-1',
          priority: RecoveryTaskPriority.low,
        ),
        throwsA(isA<RecoveryTaskAlreadyOpenException>()),
      );

      final action = await repository.logRecoveryAction(
        customerId: 'cust-1',
        actionType: RecoveryActionType.call,
        taskId: created.id,
        payload: const {'notes': 'Cliente contactado'},
      );
      expect(action.taskId, created.id);
      final actionRows = await db.query(
        'recovery_actions',
        where: 'id = ?',
        whereArgs: [action.id],
      );
      expect(actionRows.single['payload'], isA<String>());
      expect(
        RecoveryActionLog.fromJson(actionRows.single).payload?['notes'],
        'Cliente contactado',
      );

      final completed = await repository.completeRecoveryTask(created.id);

      expect(completed, isNotNull);
      expect(completed!.status, RecoveryTaskStatus.completed);
      expect(await repository.getOpenRecoveryTasks(), isEmpty);

      final recreated = await repository.createRecoveryTaskWithResult(
        customerId: 'cust-1',
        priority: RecoveryTaskPriority.medium,
      );
      expect(recreated.outcome, RecoveryTaskCreationOutcome.created);
      expect(recreated.task.id, isNot(created.id));

      final pending = await syncDao.getAllItems();
      final recoveryItems =
          pending.where((item) => item.entityType == 'recovery_task').toList();
      expect(recoveryItems.length, 3);
      expect(recoveryItems.any((item) => item.operation == 'create'), isTrue);
      expect(recoveryItems.any((item) => item.operation == 'update'), isTrue);
      expect(
        pending.any((item) => item.entityType == 'recovery_action'),
        isTrue,
      );
    },
  );

  test('visit reports and survey responses report queued saves', () async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('customers', {
      'id': 'cust-1',
      'merchant_id': 'merchant-1',
      'name': 'Cliente 1',
      'phone': '841111111',
      'total_points': 0,
      'created_at': now,
      'updated_at': now,
      'synced': 1,
    });

    final visitResult = await repository.submitVisitReportWithResult(
      customerId: 'cust-1',
      result: VisitResultType.interested,
      visitedAt: DateTime.now(),
      notes: 'Cliente pediu uma promoção.',
    );

    expect(visitResult.isQueued, isTrue);
    expect(visitResult.value.synced, isFalse);

    final survey = await engageDao.createSurvey(
      title: 'Satisfação',
      questions: [
        EngageSurveyQuestion(
          id: 'question-1',
          surveyId: '',
          questionText: 'Gostou do atendimento?',
          questionType: SurveyQuestionType.yesNo,
          sortOrder: 0,
          isRequired: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
    );
    final responseResult = await repository.submitSurveyResponseWithResult(
      SurveySubmissionInput(
        surveyId: survey.id,
        channel: 'manual',
        answers: const [
          SurveyAnswerInput(questionId: 'question-1', answerBool: true),
        ],
      ),
    );

    expect(responseResult.isQueued, isTrue);
    expect(responseResult.value, isNotEmpty);

    final queued = await syncDao.getAllItems();
    expect(
      queued.map((item) => item.entityType),
      containsAll(['visit_report', 'survey_response']),
    );
  });

  test('remote failure queues the same generated Engage entity IDs', () async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('customers', {
      'id': 'cust-idempotent',
      'merchant_id': 'merchant-1',
      'name': 'Cliente',
      'phone': '841111111',
      'total_points': 0,
      'created_at': now,
      'updated_at': now,
      'synced': 1,
    });
    final survey = await engageDao.createSurvey(
      title: 'Satisfação',
      questions: [
        EngageSurveyQuestion(
          id: 'question-idempotent',
          surveyId: '',
          questionText: 'Gostou?',
          questionType: SurveyQuestionType.yesNo,
          sortOrder: 0,
          isRequired: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
    );
    final api = _FailAfterCommitEngageApi();
    repository = EngageRepository(
      engageDao,
      syncDao,
      api: api,
      useRemote: true,
    );

    final action = await repository.logRecoveryActionWithResult(
      customerId: 'cust-idempotent',
      actionType: RecoveryActionType.call,
    );
    final report = await repository.submitVisitReportWithResult(
      customerId: 'cust-idempotent',
      result: VisitResultType.interested,
      visitedAt: DateTime.now(),
    );
    final response = await repository.submitSurveyResponseWithResult(
      SurveySubmissionInput(
        surveyId: survey.id,
        answers: const [
          SurveyAnswerInput(
            questionId: 'question-idempotent',
            answerBool: true,
          ),
        ],
      ),
    );

    final queued = await syncDao.getAllItems();
    Map<String, dynamic> payloadFor(String entityType) => jsonDecode(
          queued.singleWhere((item) => item.entityType == entityType).payload,
        ) as Map<String, dynamic>;

    expect(action.isQueued, isTrue);
    expect(action.value.id, api.actionId);
    expect(payloadFor('recovery_action')['id'], api.actionId);
    expect(report.isQueued, isTrue);
    expect(report.value.id, api.reportId);
    expect(payloadFor('visit_report')['id'], api.reportId);
    expect(response.isQueued, isTrue);
    expect(response.value, api.responseId);
    final responsePayload = payloadFor('survey_response');
    expect(responsePayload['id'], api.responseId);
    expect(
      (responsePayload['answers'] as List<dynamic>).single['id'],
      api.answerId,
    );

    await repository.logRecoveryActionWithResult(
      actionId: action.value.id,
      customerId: 'cust-idempotent',
      actionType: RecoveryActionType.call,
    );
    await repository.submitVisitReportWithResult(
      reportId: report.value.id,
      customerId: 'cust-idempotent',
      result: VisitResultType.interested,
      visitedAt: DateTime.now(),
    );
    await repository.submitSurveyResponseWithResult(
      SurveySubmissionInput(
        responseId: response.value,
        surveyId: survey.id,
        answers: [
          SurveyAnswerInput(
            id: api.answerId,
            questionId: 'question-idempotent',
            answerBool: true,
          ),
        ],
      ),
    );

    expect(
      (await db.query(
        'recovery_actions',
        where: 'id = ?',
        whereArgs: [action.value.id],
      )),
      hasLength(1),
    );
    expect(
      (await db.query(
        'visit_reports',
        where: 'id = ?',
        whereArgs: [report.value.id],
      )),
      hasLength(1),
    );
    expect(
      (await db.query(
        'survey_responses',
        where: 'id = ?',
        whereArgs: [response.value],
      )),
      hasLength(1),
    );
    expect(
      (await db.query(
        'survey_response_answers',
        where: 'response_id = ?',
        whereArgs: [response.value],
      )),
      hasLength(1),
    );
  });
}

class _FailAfterCommitEngageApi extends EngageApi {
  _FailAfterCommitEngageApi()
      : super(
          JsonApiClient(baseUrl: 'https://example.test'),
          () async => 'token',
        );

  String? actionId;
  String? reportId;
  String? responseId;
  String? answerId;

  @override
  Future<RecoveryActionLog> logAction({
    required String actionId,
    required String customerId,
    required String actionType,
    String? taskId,
    Map<String, dynamic>? payload,
  }) async {
    this.actionId = actionId;
    throw const NetworkException('Response lost');
  }

  @override
  Future<VisitReport> submitVisitReport({
    required String reportId,
    required String customerId,
    required String result,
    required DateTime visitedAt,
    String? taskId,
    String? notes,
  }) async {
    this.reportId = reportId;
    throw const NetworkException('Response lost');
  }

  @override
  Future<String> submitSurveyResponse(SurveySubmissionInput submission) async {
    responseId = submission.responseId;
    answerId = submission.answers.single.id;
    throw const NetworkException('Response lost');
  }
}
