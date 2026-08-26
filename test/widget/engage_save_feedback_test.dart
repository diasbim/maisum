import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/engage/data/engage_dao.dart';
import 'package:maisum/features/engage/data/engage_repository.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';
import 'package:maisum/features/engage/presentation/survey_response_screen.dart';
import 'package:maisum/features/engage/presentation/visit_report_screen.dart';
import 'package:maisum/features/engage/providers/engage_providers.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

const _businessAccess = EngageAccess(
  canViewRisk: true,
  canManageRecovery: true,
  canManageVisits: true,
  canManageSurveys: true,
);

class _SaveRepositoryStub extends EngageRepository {
  _SaveRepositoryStub({
    this.onVisitSubmit,
    this.onSurveySubmit,
  }) : super(EngageDao(AppDatabase.instance), SyncDao(AppDatabase.instance));

  final Future<EngageSaveResult<VisitReport>> Function()? onVisitSubmit;
  final Future<EngageSaveResult<String>> Function()? onSurveySubmit;
  int visitSubmitCalls = 0;

  @override
  Future<EngageSaveResult<VisitReport>> submitVisitReportWithResult({
    String? reportId,
    required String customerId,
    required String result,
    required DateTime visitedAt,
    String? taskId,
    String? notes,
  }) {
    visitSubmitCalls++;
    return onVisitSubmit!();
  }

  @override
  Future<EngageSaveResult<String>> submitSurveyResponseWithResult(
    SurveySubmissionInput submission,
  ) =>
      onSurveySubmit!();
}

class _SurveyController extends EngageSurveysController {
  _SurveyController(this.surveys);

  final List<EngageSurvey> surveys;

  @override
  Future<List<EngageSurvey>> build() async => surveys;
}

Widget _wrap(
  Widget child, {
  required EngageRepository repository,
  List<EngageSurvey>? surveys,
}) {
  return ProviderScope(
    overrides: [
      engageAccessProvider.overrideWith((ref) async => _businessAccess),
      engageRepositoryProvider.overrideWithValue(repository),
      if (surveys != null)
        engageSurveysProvider.overrideWith(() => _SurveyController(surveys)),
    ],
    child: MaterialApp(home: child),
  );
}

EngageSurvey _survey() {
  final now = DateTime.now();
  return EngageSurvey(
    id: 'survey-1',
    title: 'Satisfação',
    isActive: true,
    createdAt: now,
    updatedAt: now,
    questions: [
      EngageSurveyQuestion(
        id: 'question-1',
        surveyId: 'survey-1',
        questionText: 'Como foi o atendimento?',
        questionType: SurveyQuestionType.shortText,
        sortOrder: 0,
        isRequired: true,
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

void main() {
  testWidgets('visit report keeps form values and offers retry after failure', (
    tester,
  ) async {
    final repository = _SaveRepositoryStub(
      onVisitSubmit: () =>
          Future<EngageSaveResult<VisitReport>>.error(StateError('fail')),
    );
    await tester.pumpWidget(
      _wrap(const VisitReportScreen(), repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'customer-1');
    await tester.enterText(find.byType(TextField).at(2), 'Notas da visita');
    await tester.tap(find.text('Guardar relatório'));
    await tester.pump();

    expect(repository.visitSubmitCalls, 1);
    expect(
      find.text(
        'Não foi possível guardar o relatório. Os dados continuam preenchidos.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBarAction), findsOneWidget);
    expect(find.text('customer-1'), findsOneWidget);
    expect(find.text('Notas da visita'), findsOneWidget);
  });

  testWidgets('visit report prevents a second submission while saving', (
    tester,
  ) async {
    final completer = Completer<EngageSaveResult<VisitReport>>();
    final repository =
        _SaveRepositoryStub(onVisitSubmit: () => completer.future);
    await tester.pumpWidget(
      _wrap(const VisitReportScreen(), repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'customer-1');
    await tester.tap(find.text('Guardar relatório'));
    await tester.pump();
    await tester.tap(find.text('A gravar...'));
    await tester.pump();

    expect(repository.visitSubmitCalls, 1);
    completer.completeError(StateError('cancelled'));
    await tester.pump();
  });

  testWidgets('survey response identifies a queued submission', (tester) async {
    final repository = _SaveRepositoryStub(
      onSurveySubmit: () async => const EngageSaveResult.queued('response-1'),
    );
    await tester.pumpWidget(
      _wrap(
        const SurveyResponseScreen(),
        repository: repository,
        surveys: [_survey()],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Muito bom');
    await tester.tap(find.text('Enviar resposta'));
    await tester.pump();

    expect(find.text('Resposta guardada para sincronizar'), findsOneWidget);
  });
}
