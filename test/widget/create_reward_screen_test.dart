import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

    final nameField = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
    final pointsField = tester.widget<TextFormField>(find.byType(TextFormField).at(1));

    expect(nameField.controller?.text, 'Desconto de 20%');
    expect(pointsField.controller?.text, '600');

    final selectedChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('reward_template_desconto_20')),
    );
    expect(selectedChip.selected, isTrue);
  });

  testWidgets('updates fields when selecting another template', (tester) async {
    await tester.pumpWidget(_buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reward_template_barba_premium')));
    await tester.pump();

    final nameField = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
    final pointsField = tester.widget<TextFormField>(find.byType(TextFormField).at(1));

    expect(nameField.controller?.text, 'Barba premium');
    expect(pointsField.controller?.text, '700');
  });
}
