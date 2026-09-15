import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/customers/presentation/customers_controller.dart';
import 'package:maisum/features/engage/data/engage_dao.dart';
import 'package:maisum/features/engage/data/engage_repository.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/engage/presentation/survey_analytics_screen.dart';
import 'package:maisum/features/engage/presentation/survey_builder_screen.dart';
import 'package:maisum/features/engage/presentation/survey_response_screen.dart';
import 'package:maisum/features/engage/presentation/visit_report_screen.dart';
import 'package:maisum/features/engage/providers/engage_providers.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

/// End-to-end smoke of the Business-plan Engage modules, driven through the
/// real screens: build a survey, collect an answer to every question type, and
/// file a visit report.
///
/// The repository is an in-memory stand-in rather than a null-returning stub,
/// so what one screen writes the next screen actually reads — the only way a
/// survey created in the builder can be answered in the response screen.
///
/// These tests also guard the language boundary: Engage stores its vocabulary
/// as English database values, and none of it may reach a merchant's screen.
void main() {
  group('Engage paid modules — end to end', () {
    testWidgets('builds a survey, answers it, then files a visit',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _InMemoryEngageRepository();

      // ── 1. Build a survey from a template, plus one question of our own ──
      await tester.pumpWidget(_wrap(const SurveyBuilderScreen(), repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Porque não voltou?'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();

      // The template leaves two questions; ours is the third.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Texto da pergunta').last,
        'Recomendaria a nossa loja?',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Publicar questionário'));
      await tester.pumpAndSettle();

      expect(repository.surveys, hasLength(1));
      expect(repository.surveys.single.questions, hasLength(3));
      expect(
        repository.surveys.single.title,
        'Porque não voltou?',
        reason: 'the stored survey title is shown to customers',
      );

      // ── 2. Answer every question type through the response screen ──
      await tester.pumpWidget(_wrap(const SurveyResponseScreen(), repository));
      await tester.pumpAndSettle();

      final survey = repository.surveys.single;
      final choice = survey.questions[0];
      final freeText = survey.questions[1];
      final ours = survey.questions[2];

      // Multiple choice.
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preço').last);
      await tester.pumpAndSettle();

      // Two short-text questions.
      await tester.enterText(
        find.widgetWithText(TextFormField, freeText.questionText),
        'Um desconto',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '${ours.questionText} *'),
        'Sim, sem dúvida',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar resposta'));
      await tester.pumpAndSettle();

      expect(repository.submissions, hasLength(1));
      expect(repository.submissions.single.answers, hasLength(3));
      expect(
        repository.submissions.single.answers
            .firstWhere((a) => a.questionId == choice.id)
            .answerText,
        'Preço',
      );

      // ── 3. File a visit report ──
      await tester.pumpWidget(_wrap(const VisitReportScreen(), repository));
      await tester.pumpAndSettle();

      // The customer is chosen by name. Nothing on this screen asks the
      // merchant for the UUID that ends up on the report.
      await tester.tap(find.text('Escolher o cliente visitado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bruno Macamo'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltou à loja').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar relatório'));
      await tester.pumpAndSettle();

      expect(repository.visits, hasLength(1));
      expect(repository.visits.single.result, VisitResultType.returned);
      expect(repository.visits.single.customerId, _customers[1].id);
    });

    testWidgets('no screen leaks a stored English value to the merchant',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _InMemoryEngageRepository();

      await tester.pumpWidget(_wrap(const SurveyBuilderScreen(), repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Porque não voltou?'));
      await tester.pumpAndSettle();

      // Question types are stored as SHORT_TEXT / YES_NO / ...; the merchant
      // must see words instead.
      for (final type in SurveyQuestionType.values) {
        expect(
          find.text(type),
          findsNothing,
          reason: 'raw question type "$type" reached the builder',
        );
      }

      await tester.tap(find.text('Publicar questionário'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const VisitReportScreen(), repository));
      await tester.pumpAndSettle();

      for (final result in VisitResultType.values) {
        expect(
          find.text(result),
          findsNothing,
          reason: 'raw visit result "$result" reached the visit screen',
        );
      }
    });

    testWidgets('a required rating is not treated as answered by its default',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _InMemoryEngageRepository()
        ..surveys.add(_ratingSurvey());

      await tester.pumpWidget(_wrap(const SurveyResponseScreen(), repository));
      await tester.pumpAndSettle();

      // Nothing is picked yet, so the send must be refused — and must say which
      // question is missing rather than "preencha as obrigatórias".
      await tester.tap(find.text('Enviar resposta'));
      await tester.pumpAndSettle();

      expect(repository.submissions, isEmpty);
      expect(find.textContaining('pergunta 1'), findsOneWidget);

      // Picking a score then sends the score that is actually shown.
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar resposta'));
      await tester.pumpAndSettle();

      expect(repository.submissions, hasLength(1));
      expect(
        repository.submissions.single.answers.single.answerNumeric,
        4.0,
      );
    });

    testWidgets('clears the form after a response is sent', (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _InMemoryEngageRepository()
        ..surveys.add(_textSurvey());

      await tester.pumpWidget(_wrap(const SurveyResponseScreen(), repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'O que podemos melhorar? *'),
        'Mais horários',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar resposta'));
      await tester.pumpAndSettle();

      expect(repository.submissions, hasLength(1));
      expect(
        repository.submissions.single.customerId,
        isNull,
        reason: 'nobody was picked, so the response is genuinely anonymous',
      );
      expect(
        find.text('Mais horários'),
        findsNothing,
        reason: 'a sent answer left on screen gets re-sent for the next customer',
      );
    });

    testWidgets('analytics shows distinct sections, not one list three times',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _InMemoryEngageRepository()
        ..analytics = const EngageSurveyAnalytics(
          responsesPerSurvey: 6,
          customerSatisfaction: 4.25,
          responsesTotal: 12,
          ratedResponses: 4,
          topAnswers: [
            SurveyAnswerTally(label: 'Preço', count: 7),
            SurveyAnswerTally(label: 'Horário', count: 2),
          ],
          ratingBreakdown: [
            SurveyRatingTally(score: 4, count: 3),
            SurveyRatingTally(score: 5, count: 1),
          ],
        );

      await tester.pumpWidget(_wrap(const SurveyAnalyticsScreen(), repository));
      await tester.pumpAndSettle();

      // Counts, not bare labels: "Preço" alone never said how many people
      // picked it.
      expect(find.text('Preço'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      // The rating spread is its own section, no longer a copy of the answers.
      expect(find.text('Distribuição das notas'), findsOneWidget);
      expect(find.text('Horário'), findsOneWidget);

      // The average is always qualified by how many ratings it rests on.
      expect(find.text('4,3'), findsOneWidget);
      expect(find.textContaining('4 notas'), findsOneWidget);
    });

    testWidgets('analytics offers a way forward before any response exists',
        (tester) async {
      final repository = _InMemoryEngageRepository();

      await tester.pumpWidget(_wrap(const SurveyAnalyticsScreen(), repository));
      await tester.pumpAndSettle();

      expect(find.text('Ainda sem respostas'), findsOneWidget);
    });

    testWidgets('a visit cannot be filed against a customer nobody picked',
        (tester) async {
      final repository = _InMemoryEngageRepository();

      await tester.pumpWidget(_wrap(const VisitReportScreen(), repository));
      await tester.pumpAndSettle();

      // No id field at all: the merchant has no way to type a UUID, and no
      // reason to.
      expect(find.text('ID do cliente'), findsNothing);
      expect(find.text('ID da tarefa (opcional)'), findsNothing);

      await tester.tap(find.text('Guardar relatório'));
      await tester.pumpAndSettle();

      expect(repository.visits, isEmpty);
      expect(find.text('Escolha o cliente visitado.'), findsOneWidget);
    });

    testWidgets('the linked task is offered as a choice and closed on save',
        (tester) async {
      final customer = _customers.first;
      final repository = _InMemoryEngageRepository()
        ..openTasks.add(_openTaskFor(customer.id));

      await tester.pumpWidget(_wrap(const VisitReportScreen(), repository));
      await tester.pumpAndSettle();

      // Nothing about tasks before a customer is chosen: an unscoped task list
      // would only invite linking a visit to someone else's task.
      expect(find.text('Tarefa de recuperação (opcional)'), findsNothing);

      await tester.tap(find.text('Escolher o cliente visitado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(customer.name));
      await tester.pumpAndSettle();

      expect(find.text('Tarefa de recuperação (opcional)'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Prioridade alta').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Concluir a tarefa ao guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Concluir a tarefa ao guardar'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Guardar relatório'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar relatório'));
      await tester.pumpAndSettle();

      expect(repository.visits.single.customerId, customer.id);
      expect(repository.visits.single.taskId, 'task-1');
      expect(repository.completedTaskIds, ['task-1']);
    });

    testWidgets('a survey answer carries the chosen customer, or nobody',
        (tester) async {
      final repository = _InMemoryEngageRepository()
        ..surveys.add(_ratingSurvey());

      await tester.pumpWidget(_wrap(const SurveyResponseScreen(), repository));
      await tester.pumpAndSettle();

      // Anonymous until someone is picked — the field says so in words.
      expect(find.text('Resposta anónima'), findsOneWidget);

      await tester.tap(find.text('Resposta anónima'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amélia Cossa'));
      await tester.pumpAndSettle();
      expect(find.text('Amélia Cossa'), findsOneWidget);

      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar resposta'));
      await tester.pumpAndSettle();

      expect(repository.submissions.single.customerId, _customers.first.id);
      // Sending resets to anonymous, so the next walk-in is not silently
      // recorded as the previous customer.
      expect(find.text('Resposta anónima'), findsOneWidget);
    });

    testWidgets('removing a question keeps the remaining text in place',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _InMemoryEngageRepository();
      await tester.pumpWidget(_wrap(const SurveyBuilderScreen(), repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Título'),
        'Teste',
      );
      // Deliberately not "Pergunta N": the cards are headed "Pergunta 1"… and
      // the test must not confuse a heading for an answer.
      const texts = ['Sobre o preço', 'Sobre o horário', 'Sobre a equipa'];
      for (final text in texts) {
        await tester.tap(find.text('Adicionar'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Texto da pergunta').last,
          text,
        );
        await tester.pumpAndSettle();
      }

      // Drop the first one; the other two must keep their own text — on screen
      // as well as in the data, which is where the stale-element bug showed.
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Sobre o preço'), findsNothing);
      expect(find.text('Sobre o horário'), findsOneWidget);
      expect(find.text('Sobre a equipa'), findsOneWidget);

      await tester.tap(find.text('Publicar questionário'));
      await tester.pumpAndSettle();

      expect(
        repository.surveys.single.questions.map((q) => q.questionText),
        ['Sobre o horário', 'Sobre a equipa'],
      );
    });
  });
}

const _businessAccess = EngageAccess(
  canViewRisk: true,
  canManageRecovery: true,
  canManageVisits: true,
  canManageSurveys: true,
);

Widget _wrap(Widget child, _InMemoryEngageRepository repository) {
  return ProviderScope(
    overrides: [
      engageAccessProvider.overrideWith((ref) async => _businessAccess),
      engageRepositoryProvider.overrideWithValue(repository),
      customerSearchProvider.overrideWith(
        (ref, query) async => _customers
            .where(
              (customer) => customer.name.toLowerCase().contains(
                    query.trim().toLowerCase(),
                  ),
            )
            .toList(),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

/// The merchant's book, as the picker sees it. Ids are UUID-shaped on purpose:
/// the whole point of the picker is that nobody has to read one.
final _customers = [
  Customer(
    id: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    name: 'Amélia Cossa',
    phone: '840000001',
    createdAt: DateTime(2026, 1, 1),
  ),
  Customer(
    id: '9c858901-8a57-4791-81fe-4c455b099bc9',
    name: 'Bruno Macamo',
    phone: '840000002',
    createdAt: DateTime(2026, 1, 1),
  ),
];

EngageSurvey _ratingSurvey() => EngageSurvey(
      id: 'survey-rating',
      title: 'Satisfação',
      isActive: true,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      questions: [
        EngageSurveyQuestion(
          id: 'q-rating',
          surveyId: 'survey-rating',
          questionText: 'Como avalia a experiência?',
          questionType: SurveyQuestionType.rating,
          sortOrder: 0,
          isRequired: true,
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      ],
    );

EngageSurvey _textSurvey() => EngageSurvey(
      id: 'survey-text',
      title: 'Sugestões',
      isActive: true,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      questions: [
        EngageSurveyQuestion(
          id: 'q-text',
          surveyId: 'survey-text',
          questionText: 'O que podemos melhorar?',
          questionType: SurveyQuestionType.shortText,
          sortOrder: 0,
          isRequired: true,
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      ],
    );

/// Keeps what the screens write, so a survey built in one screen can be
/// answered in the next. Only the methods these three screens reach are
/// overridden; anything else would be a test that lies about the flow.
class _InMemoryEngageRepository extends EngageRepository {
  _InMemoryEngageRepository()
      : super(EngageDao(AppDatabase.instance), SyncDao(AppDatabase.instance));

  final List<EngageSurvey> surveys = [];
  final List<SurveySubmissionInput> submissions = [];
  final List<VisitReport> visits = [];
  final List<RecoveryTaskQueueItem> openTasks = [];
  final List<String> completedTaskIds = [];

  @override
  Future<List<EngageSurvey>> getSurveys() async => List.of(surveys);

  @override
  Future<EngageDashboardData> loadDashboard({
    bool refreshRiskScores = true,
  }) async =>
      const EngageDashboardData(
        customersActive: 0,
        customersAtRisk: 0,
        criticalCustomers: 0,
        revenueAtRisk: 0,
        recoveredCustomers: 0,
      );

  @override
  Future<List<RecoveryQueueItem>> getRecoveryQueue({
    int limit = 20,
    bool refreshRiskScores = false,
  }) async =>
      const [];

  @override
  Future<List<RecoveryTaskQueueItem>> getOpenRecoveryTasks({
    int limit = 50,
  }) async =>
      List.of(openTasks);

  @override
  Future<RecoveryTask?> completeRecoveryTask(String taskId) async {
    final match = openTasks.where((item) => item.task.id == taskId).toList();
    if (match.isEmpty) return null;
    completedTaskIds.add(taskId);
    openTasks.removeWhere((item) => item.task.id == taskId);
    return match.single.task;
  }

  @override
  Future<EngageSurvey> createSurvey({
    required String title,
    String? description,
    required List<EngageSurveyQuestion> questions,
  }) async {
    final surveyId = 'survey-${surveys.length + 1}';
    final now = DateTime(2026, 9, 9);
    final survey = EngageSurvey(
      id: surveyId,
      title: title,
      description: description,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      questions: [
        for (var i = 0; i < questions.length; i++)
          EngageSurveyQuestion(
            id: '$surveyId-q$i',
            surveyId: surveyId,
            questionText: questions[i].questionText,
            questionType: questions[i].questionType,
            sortOrder: i,
            isRequired: questions[i].isRequired,
            options: questions[i].options,
            createdAt: now,
            updatedAt: now,
          ),
      ],
    );
    surveys.add(survey);
    return survey;
  }

  @override
  Future<EngageSaveResult<String>> submitSurveyResponseWithResult(
    SurveySubmissionInput submission,
  ) async {
    submissions.add(submission);
    return EngageSaveResult.saved('response-${submissions.length}');
  }

  EngageSurveyAnalytics analytics = EngageSurveyAnalytics.empty;

  @override
  Future<EngageSurveyAnalytics> getSurveyAnalytics() async => analytics;

  @override
  Future<EngageSaveResult<VisitReport>> submitVisitReportWithResult({
    String? reportId,
    required String customerId,
    required String result,
    required DateTime visitedAt,
    String? taskId,
    String? notes,
  }) async {
    final report = VisitReport(
      id: 'visit-${visits.length + 1}',
      customerId: customerId,
      result: result,
      visitedAt: visitedAt,
      taskId: taskId,
      notes: notes,
      createdAt: visitedAt,
      updatedAt: visitedAt,
    );
    visits.add(report);
    return EngageSaveResult.saved(report);
  }
}

RecoveryTaskQueueItem _openTaskFor(String customerId) => RecoveryTaskQueueItem(
      task: RecoveryTask(
        id: 'task-1',
        customerId: customerId,
        priority: RecoveryTaskPriority.high,
        status: RecoveryTaskStatus.open,
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      ),
      customerName: 'Amélia Cossa',
      customerPhone: '840000001',
    );
