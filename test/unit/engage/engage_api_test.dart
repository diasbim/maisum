import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/network/json_api_client.dart';
import 'package:maisum/features/engage/data/engage_api.dart';
import 'package:maisum/features/engage/domain/engage_models.dart';

void main() {
  late HttpServer server;
  late EngageApi api;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = EngageApi(
      JsonApiClient(baseUrl: 'http://${server.address.host}:${server.port}'),
      () async => 'test-token',
    );
  });

  tearDown(() => server.close(force: true));

  test('maps an existing open task to an already-open creation outcome',
      () async {
    final responseFuture = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/engage/task');
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      expect(body['id'], 'task-requested');
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'data': {
            'outcome': 'already_open',
            'task': {
              'id': 'task-existing',
              'customer_id': 'customer-1',
              'priority': 'high',
              'status': 'open',
              'created_at': 100,
              'updated_at': 200,
            },
          },
        }));
      await request.response.close();
    });

    final result = await api.createTask(
      taskId: 'task-requested',
      customerId: 'customer-1',
      priority: RecoveryTaskPriority.high,
    );
    await responseFuture;

    expect(result.wasAlreadyOpen, isTrue);
    expect(result.task.id, 'task-existing');
  });

  test('maps a newly inserted task to a created outcome', () async {
    final responseFuture = server.first.then((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'data': {
            'outcome': 'created',
            'task': {
              'id': 'task-new',
              'customer_id': 'customer-1',
              'priority': 'medium',
              'status': 'open',
              'created_at': 100,
              'updated_at': 100,
            },
          },
        }));
      await request.response.close();
    });

    final result = await api.createTask(
      taskId: 'task-new',
      customerId: 'customer-1',
      priority: RecoveryTaskPriority.medium,
    );
    await responseFuture;

    expect(result.outcome, RecoveryTaskCreationOutcome.created);
    expect(result.task.id, 'task-new');
  });
}
