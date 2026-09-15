import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/engage/data/engage_dao.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';

import '../../helpers/test_database.dart';

/// The analytics screen is fed by three SQL aggregates that join answers back
/// to their question. Every widget test stubs the repository, so nothing else
/// in the suite ever executes this SQL — a wrong column or a broken join would
/// only surface as an empty analytics screen in a merchant's hands.
void main() {
  setUp(setUpTestDatabase);
  tearDown(tearDownTestDatabase);

  late EngageDao dao;

  setUp(() {
    dao = EngageDao(AppDatabase.instance, merchantId: 'merchant-1');
  });

  Future<EngageSurvey> seedSurvey() {
    final now = DateTime(2026, 9, 1);
    EngageSurveyQuestion question(String text, String type) =>
        EngageSurveyQuestion(
          id: '',
          surveyId: '',
          questionText: text,
          questionType: type,
          sortOrder: 0,
          isRequired: true,
          createdAt: now,
          updatedAt: now,
        );

    return dao.createSurvey(
      title: 'Porque não voltou?',
      questions: [
        question('Motivo', SurveyQuestionType.multipleChoice),
        question('Nota', SurveyQuestionType.rating),
        question('Comentário', SurveyQuestionType.shortText),
      ],
    );
  }

  Future<void> answer(
    EngageSurvey survey, {
    String? choice,
    double? rating,
    String? freeText,
  }) async {
    await dao.submitSurveyResponse(
      SurveySubmissionInput(
        surveyId: survey.id,
        channel: SurveyChannel.manual,
        answers: [
          if (choice != null)
            SurveyAnswerInput(
              questionId: survey.questions[0].id,
              answerText: choice,
            ),
          if (rating != null)
            SurveyAnswerInput(
              questionId: survey.questions[1].id,
              answerNumeric: rating,
            ),
          if (freeText != null)
            SurveyAnswerInput(
              questionId: survey.questions[2].id,
              answerText: freeText,
            ),
        ],
      ),
    );
  }

  test('counts choice answers and leaves free text out of the ranking',
      () async {
    final survey = await seedSurvey();
    await answer(survey, choice: 'Preço', freeText: 'Estava caro nesse dia');
    await answer(survey, choice: 'Preço', freeText: 'Achei o preço alto');
    await answer(survey, choice: 'Horário');

    final analytics = await dao.getSurveyAnalytics();

    expect(analytics.responsesTotal, 3);
    expect(
      analytics.topAnswers.map((a) => '${a.label}:${a.count}'),
      ['Preço:2', 'Horário:1'],
      reason: 'free-text answers must not be ranked as if they were options',
    );
  });

  test('satisfaction averages the ratings only, and reports how many',
      () async {
    final survey = await seedSurvey();
    await answer(survey, rating: 5, choice: 'Preço', freeText: 'Bom');
    await answer(survey, rating: 3);

    final analytics = await dao.getSurveyAnalytics();

    expect(analytics.customerSatisfaction, 4.0);
    expect(analytics.ratedResponses, 2);
    expect(
      analytics.ratingBreakdown.map((r) => '${r.score}:${r.count}'),
      ['3:1', '5:1'],
    );
  });

  test('responses per survey is a ratio, never a percentage', () async {
    final survey = await seedSurvey();
    for (var i = 0; i < 5; i++) {
      await answer(survey, choice: 'Preço');
    }

    final analytics = await dao.getSurveyAnalytics();

    // The old formula multiplied by 100 and printed "500%" here.
    expect(analytics.responsesPerSurvey, 5.0);
  });

  test('an untouched account reports zeroes rather than throwing', () async {
    final analytics = await dao.getSurveyAnalytics();

    expect(analytics.responsesTotal, 0);
    expect(analytics.ratedResponses, 0);
    expect(analytics.topAnswers, isEmpty);
    expect(analytics.ratingBreakdown, isEmpty);
    expect(analytics.customerSatisfaction, 0);
  });
}
