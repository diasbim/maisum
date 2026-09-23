import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/design_system/design_system.dart';
import 'package:maisum/features/rewards/presentation/create_reward_screen.dart';

Widget _buildScreen({String? template}) {
  return ProviderScope(
    child: MaterialApp(
      home: CreateRewardScreen(initialTemplateCode: template),
    ),
  );
}

void main() {
  testWidgets('prefills reward form when template is passed in route',
      (tester) async {
    await tester.pumpWidget(_buildScreen(template: 'desconto_20'));
    await tester.pumpAndSettle();

    final nameField =
        tester.widget<TextFormField>(find.byType(TextFormField).at(0));
    final pointsField =
        tester.widget<TextFormField>(find.byType(TextFormField).at(1));

    expect(nameField.controller?.text, 'Desconto de 20%');
    expect(pointsField.controller?.text, '800');

    final selectedTemplate = tester.widget<MaisUmSurface>(
      find.descendant(
        of: find.byKey(const Key('reward_template_desconto_20')),
        matching: find.byType(MaisUmSurface),
      ),
    );
    expect(selectedTemplate.selected, isTrue);
  });

  testWidgets('updates fields when selecting another template', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reward_template_brinde')));
    await tester.pump();

    final nameField =
        tester.widget<TextFormField>(find.byType(TextFormField).at(0));
    final pointsField =
        tester.widget<TextFormField>(find.byType(TextFormField).at(1));

    expect(nameField.controller?.text, 'Brinde especial');
    expect(pointsField.controller?.text, '600');
  });

  testWidgets('translates the points target into money the merchant knows',
      (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pumpAndSettle();

    // 500 points at the default 100 MZN per point.
    await tester.enterText(find.byType(TextFormField).at(1), '500');
    await tester.pump();

    expect(find.text('50 000 MZN em compras'), findsOneWidget);
  });

  testWidgets('stops claiming a template once the form is edited by hand',
      (tester) async {
    await tester.pumpWidget(_buildScreen(template: 'desconto_20'));
    await tester.pumpAndSettle();

    MaisUmSurface chip() => tester.widget<MaisUmSurface>(
          find.descendant(
            of: find.byKey(const Key('reward_template_desconto_20')),
            matching: find.byType(MaisUmSurface),
          ),
        );
    expect(chip().selected, isTrue);

    await tester.enterText(find.byType(TextFormField).at(0), 'Outra coisa');
    await tester.pump();

    expect(chip().selected, isFalse);
  });
}
