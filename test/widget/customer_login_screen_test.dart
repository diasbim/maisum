import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';

void main() {
  testWidgets('shows the explicit customer entry point', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CustomerLoginScreen()));
    expect(find.text('Os seus pontos, num só lugar'), findsOneWidget);
    expect(find.byKey(const Key('customer_login_continue')), findsOneWidget);
    expect(find.text('Sou comerciante'), findsOneWidget);
  });
}
