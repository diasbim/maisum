import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';

void main() {
  testWidgets('shows the explicit customer entry point', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CustomerLoginScreen()));
    expect(find.text('Os seus pontos,\nsempre consigo.'), findsOneWidget);
    expect(find.text('Pontos atualizados'), findsOneWidget);
    expect(find.text('Prémios sem complicações'), findsOneWidget);
    expect(find.text('Código sempre à mão'), findsOneWidget);
    expect(find.byKey(const Key('customer_login_continue')), findsOneWidget);
    expect(find.text('Continuar com telemóvel'), findsOneWidget);
    expect(find.text('Aceder como comerciante'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer entry remains usable on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: CustomerLoginScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byKey(const Key('customer_login_continue')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
