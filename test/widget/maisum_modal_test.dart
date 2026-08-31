import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/design_system/components/maisum_modal.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required ValueChanged<bool?> onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await MaisUmModal.confirm(
                    context: context,
                    title: 'Confirmar saída',
                    message:
                        'Tem a certeza que quer terminar a sessão? Terá de voltar a autenticar-se para entrar.',
                    primaryLabel: 'Sair',
                    secondaryLabel: 'Cancelar',
                    icon: Icons.logout_rounded,
                    destructive: true,
                  );
                  onResult(result);
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('destructive confirmation can be cancelled', (tester) async {
    bool? result;
    await pumpDialog(tester, onResult: (value) => result = value);

    expect(find.text('Confirmar saída'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('destructive confirmation returns true only after confirm',
      (tester) async {
    bool? result;
    await pumpDialog(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
