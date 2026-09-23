import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

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
import 'package:maisum/features/retention/domain/retention_metric.dart';
import 'package:maisum/features/retention/widgets/inactive_customer_card.dart';
import 'package:maisum/features/retention/widgets/recurring_customer_card.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

/// On-device smoke of the retention and paid-Engage surfaces.
///
/// The widget tests already assert this behaviour under the fake async zone;
/// what only a real device can prove is that these screens lay out and paint
/// on a real Android surface — real font metrics, real density, real overflow
/// — and that no stored English value survives the trip to a real screen.
///
/// Runs against a Medium Phone AVD with `flutter test integration_test/...`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Retention cards on device', () {
    testWidgets('name the risk level in Portuguese and fit the phone',
        (tester) async {
      for (final level in RetentionRiskLevel.values) {
        await tester.pumpWidget(
          _app(
            InactiveCustomerCard(
              customer: _inactive(level),
              onSendReminder: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(level),
          findsNothing,
          reason: 'raw "$level" painted on a real screen',
        );
        expect(tester.takeException(), isNull);
      }

      expect(find.text('Perdido'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('dias sem voltar'), findsOneWidget);
    });

    testWidgets('recurring card shows the return rhythm', (tester) async {
      await tester.pumpWidget(
        _app(
          RecurringCustomerCard(
            customer: RecurringCustomerSummary(
              customerId: 'c2',
              name: 'João Matola',
              totalVisits: 12,
              lastVisitAt: DateTime(2026, 9, 1),
              averageVisitInterval: 14,
              totalSpent: 4200,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Campeão'), findsOneWidget);
      expect(find.text('Volta a cada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long name at 200% text does not overflow', (tester) async {
      await tester.pumpWidget(
        _app(
          InactiveCustomerCard(
            customer: const InactiveCustomerSummary(
              customerId: 'c9',
              name: 'Guilhermina Nhamirre da Conceição Mabjaia',
              daysInactive: 132,
              lastVisitAt: null,
              averageTicket: 12500,
              riskLevel: RetentionRiskLevel.risk,
            ),
            onSendReminder: () {},
          ),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sem registo'), findsOneWidget);
    });
  });

  group('Engage paid modules on device', () {
    testWidgets('survey built here can be answered next door', (tester) async {
      final repository = _InMemoryEngageRepository();

      await tester.pumpWidget(
        _app(const SurveyBuilderScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      // The templates are the merchant's first contact with the feature; they
      // used to be titled in English.
      expect(find.text('Porque não voltou?'), findsOneWidget);
      for (final type in SurveyQuestionType.values) {
        expect(find.text(type), findsNothing, reason: 'raw type "$type" shown');
      }

      await tester.tap(find.text('Porque não voltou?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publicar questionário'));
      await tester.pumpAndSettle();

      expect(repository.surveys, hasLength(1));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _app(const SurveyResponseScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      final choice = repository.surveys.single.questions.first;
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preço').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar resposta'));
      await tester.pumpAndSettle();

      expect(repository.submissions, hasLength(1));
      expect(
        repository.submissions.single.answers
            .firstWhere((a) => a.questionId == choice.id)
            .answerText,
        'Preço',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rating is answered by tapping a real 48pt target',
        (tester) async {
      final repository = _InMemoryEngageRepository()
        ..surveys.add(_ratingSurvey());

      await tester.pumpWidget(
        _app(const SurveyResponseScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      // Nothing chosen yet: the send is refused and names the question.
      await tester.tap(find.text('Enviar resposta'));
      await tester.pumpAndSettle();
      expect(repository.submissions, isEmpty);
      expect(find.textContaining('pergunta 1'), findsOneWidget);

      final target = tester.getSize(find.widgetWithText(InkWell, '4'));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));

      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar resposta'));
      await tester.pumpAndSettle();

      expect(repository.submissions.single.answers.single.answerNumeric, 4.0);
    });

    testWidgets('visit report speaks Portuguese end to end', (tester) async {
      final repository = _InMemoryEngageRepository();

      await tester.pumpWidget(
        _app(const VisitReportScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      for (final result in VisitResultType.values) {
        expect(find.text(result), findsNothing, reason: 'raw "$result" shown');
      }

      // Chosen by name on a real screen: the id never appears anywhere.
      await tester.tap(find.text('Escolher o cliente visitado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amélia Cossa'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltou à loja').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar relatório'));
      await tester.pumpAndSettle();

      expect(repository.visits.single.result, VisitResultType.returned);
      expect(repository.visits.single.customerId, _customers.single.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('analytics paints three distinct sections', (tester) async {
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

      await tester.pumpWidget(
        _app(const SurveyAnalyticsScreen(), repository: repository),
      );
      await tester.pumpAndSettle();

      expect(find.text('Respostas mais escolhidas'), findsOneWidget);
      expect(find.text('Distribuição das notas'), findsOneWidget);
      expect(find.text('Preço'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.textContaining('4 notas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('analytics offers a way forward with no responses yet',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const SurveyAnalyticsScreen(),
          repository: _InMemoryEngageRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ainda sem respostas'), findsOneWidget);
    });
  });
}

const _businessAccess = EngageAccess(
  canViewRisk: true,
  canManageRecovery: true,
  canManageVisits: true,
  canManageSurveys: true,
);

Widget _app(
  Widget child, {
  _InMemoryEngageRepository? repository,
  double textScale = 1.0,
}) {
  final isScreen = repository != null;
  return ProviderScope(
    overrides: [
      engageAccessProvider.overrideWith((ref) async => _businessAccess),
      if (repository != null)
        engageRepositoryProvider.overrideWithValue(repository),
      customerSearchProvider.overrideWith((ref, query) async => _customers),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: isScreen
            ? child
            : Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ),
      ),
    ),
  );
}

InactiveCustomerSummary _inactive(String riskLevel) => InactiveCustomerSummary(
      customerId: 'c1',
      name: 'Ana Cumbe',
      daysInactive: 45,
      lastVisitAt: DateTime(2026, 7, 26),
      averageTicket: 850,
      riskLevel: riskLevel,
    );

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

/// Keeps what the screens write, so a survey built in one screen can be
/// answered in the next.
class _InMemoryEngageRepository extends EngageRepository {
  _InMemoryEngageRepository()
      : super(EngageDao(AppDatabase.instance), SyncDao(AppDatabase.instance));

  final List<EngageSurvey> surveys = [];
  final List<SurveySubmissionInput> submissions = [];
  final List<VisitReport> visits = [];
  EngageSurveyAnalytics analytics = EngageSurveyAnalytics.empty;

  @override
  Future<List<EngageSurvey>> getSurveys() async => List.of(surveys);

  @override
  Future<EngageSurveyAnalytics> getSurveyAnalytics() async => analytics;

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
      const [];

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

/// UUID-shaped on purpose: the picker exists so no merchant ever sees one.
final _customers = [
  Customer(
    id: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    name: 'Amélia Cossa',
    phone: '840000001',
    createdAt: DateTime(2026, 1, 1),
  ),
];
