import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/utils/app_logger.dart';

void main() {
  tearDown(() => Log.bindSink(null));

  test('local errors do not notify the Crashlytics sink', () {
    final events = <AppLogEvent>[];
    Log.bindSink(events.add);

    Log.eLocal('Error', 'Crashlytics record failed', Exception('failure'));

    expect(events, isEmpty);
  });
}
