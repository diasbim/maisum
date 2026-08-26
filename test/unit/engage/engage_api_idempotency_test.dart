import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/network/api_response.dart';
import 'package:maisum/core/network/json_api_client.dart';
import 'package:maisum/features/engage/data/engage_api.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';

void main() {
  test('create endpoints send caller-provided entity IDs', () async {
    final client = _RecordingJsonApiClient();
    final api = EngageApi(client, () async => 'token');

    await api.logAction(
      actionId: 'action-1',
      customerId: 'customer-1',
      actionType: RecoveryActionType.call,
    );
    expect(client.lastBody?['id'], 'action-1');

    await api.submitVisitReport(
      reportId: 'report-1',
      customerId: 'customer-1',
      result: VisitResultType.interested,
      visitedAt: DateTime.fromMillisecondsSinceEpoch(123),
    );
    expect(client.lastBody?['id'], 'report-1');

    await api.submitSurveyResponse(
      const SurveySubmissionInput(
        responseId: 'response-1',
        surveyId: 'survey-1',
        answers: [
          SurveyAnswerInput(id: 'answer-1', questionId: 'question-1'),
        ],
      ),
    );
    expect(client.lastBody?['id'], 'response-1');
    expect(
      (client.lastBody?['answers'] as List<dynamic>).single['id'],
      'answer-1',
    );
  });
}

class _RecordingJsonApiClient extends JsonApiClient {
  _RecordingJsonApiClient() : super(baseUrl: 'https://example.test');

  Map<String, dynamic>? lastBody;

  @override
  Future<ApiResponse<dynamic>> post(
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? queryParameters,
    Object? body,
    String? bearerToken,
  }) async {
    lastBody = Map<String, dynamic>.from(body! as Map);
    switch (path) {
      case '/engage/action':
        return const ApiResponse<dynamic>(
          success: true,
          data: {
            'id': 'action-1',
            'customer_id': 'customer-1',
            'action_type': 'CALL',
            'created_at': 1,
            'updated_at': 1,
          },
        );
      case '/engage/visit-report':
        return const ApiResponse<dynamic>(
          success: true,
          data: {
            'id': 'report-1',
            'customer_id': 'customer-1',
            'result': 'Interested',
            'visited_at': 123,
            'created_at': 1,
            'updated_at': 1,
          },
        );
      default:
        return const ApiResponse<dynamic>(
          success: true,
          data: {'response_id': 'response-1'},
        );
    }
  }
}
