import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/core/theme/app_colors.dart';
import 'package:maisum/core/theme/app_theme.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/phone_auth_screen.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    double keyboardInset = 0,
    Size? physicalSize,
    ThemeData? theme,
    AuthActor actor = AuthActor.merchant,
  }) async {
    if (physicalSize != null) {
      tester.view.physicalSize = physicalSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: PhoneAuthScreen(actor: actor),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> openPhoneForm(WidgetTester tester) async {
    if (find.byKey(const Key('send_code_button')).evaluate().isNotEmpty) {
      return;
    }

    expect(find.byKey(const Key('welcome_start_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome_start_button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  ElevatedButton continueButton(WidgetTester tester) {
    return tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byKey(const Key('send_code_button')),
        matching: find.byType(ElevatedButton),
      ),
    );
  }

  testWidgets('shows otp-first layout with secondary google action',
      (tester) async {
    await pumpScreen(tester);
    await openPhoneForm(tester);

    expect(find.byKey(const Key('default_country_code')), findsOneWidget);
    expect(find.text('+258'), findsOneWidget);
    expect(find.text('Bem-vindo'), findsOneWidget);
    expect(find.text('CONTINUAR'), findsOneWidget);
    expect(find.byKey(const Key('google_auth_button')), findsOneWidget);
    expect(find.text('Continuar com Google'), findsOneWidget);
    expect(find.byKey(const Key('terms_section')), findsOneWidget);
  });

  testWidgets('customer mode offers only the supported phone OTP action',
      (tester) async {
    await pumpScreen(tester, actor: AuthActor.customer);

    expect(find.byKey(const Key('send_code_button')), findsOneWidget);
    expect(find.byKey(const Key('welcome_start_button')), findsNothing);
    expect(find.byKey(const Key('google_auth_button')), findsNothing);
    expect(find.text('ou continue com'), findsNothing);
    expect(find.byKey(const Key('terms_section')), findsOneWidget);
    expect(find.text('Entre com o telemóvel'), findsOneWidget);
    expect(find.text('PIN'), findsNothing);
    expect(find.text('Pronto'), findsNothing);
  });

  testWidgets('welcome screen fits on small phones without scrolling',
      (tester) async {
    await pumpScreen(tester, physicalSize: const Size(320, 568));

    expect(find.byKey(const Key('welcome_start_button')), findsOneWidget);
    expect(find.text('Clientes que voltam.\nNegócios que crescem.'),
        findsOneWidget);
    expect(find.text('+26%'), findsOneWidget);
    expect(find.text('Funciona offline'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone form always offers a way back to the welcome screen',
      (tester) async {
    await pumpScreen(tester);
    await openPhoneForm(tester);

    expect(find.byTooltip('Voltar'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('welcome_start_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides google and terms while keyboard is open', (tester) async {
    await pumpScreen(tester, keyboardInset: 280);
    await openPhoneForm(tester);

    expect(find.text('CONTINUAR'), findsOneWidget);
    expect(find.byKey(const Key('google_auth_button')), findsNothing);
    expect(find.byKey(const Key('terms_section')), findsNothing);
  });

  testWidgets('keeps validation hidden while typing and shows on submit',
      (tester) async {
    await pumpScreen(tester);
    await openPhoneForm(tester);

    await tester.enterText(find.byKey(const Key('phone_input')), '84 32');
    await tester.pump();

    expect(
      find.text('Número inválido. Use os prefixos 82–87 e 9 dígitos.'),
      findsNothing,
    );

    await tester.enterText(find.byKey(const Key('phone_input')), '813262347');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      find.text('Número inválido. Use os prefixos 82–87 e 9 dígitos.'),
      findsOneWidget,
    );
  });

  testWidgets('enables continue button only at 9 digits', (tester) async {
    await pumpScreen(tester);
    await openPhoneForm(tester);

    expect(continueButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('phone_input')), '84326234');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('phone_input')), '843262347');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('keeps entered phone number visible in dark mode',
      (tester) async {
    await pumpScreen(tester, theme: AppTheme.dark);
    await openPhoneForm(tester);

    final phoneInput = find.byKey(const Key('phone_input'));
    await tester.enterText(phoneInput, '843262347');
    await tester.pump();

    final editableText = tester.widget<EditableText>(
      find.descendant(of: phoneInput, matching: find.byType(EditableText)),
    );
    expect(editableText.controller.text, '84 326 2347');
    expect(editableText.style.color, AppColors.onSurface);
  });

  testWidgets('keeps layout stable on small devices with keyboard open',
      (tester) async {
    await pumpScreen(
      tester,
      physicalSize: const Size(320, 568),
      keyboardInset: 260,
    );
    await openPhoneForm(tester);

    expect(find.byKey(const Key('send_code_button')), findsOneWidget);
    expect(find.byKey(const Key('google_auth_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remains overflow-free when rotating screen', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpScreen(tester);
    await openPhoneForm(tester);

    tester.view.physicalSize = const Size(568, 320);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('send_code_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps layout stable when pasting phone number', (tester) async {
    await pumpScreen(
      tester,
      physicalSize: const Size(320, 568),
      keyboardInset: 260,
    );
    await openPhoneForm(tester);

    await tester.enterText(find.byKey(const Key('phone_input')), '843262347');
    await tester.pumpAndSettle();

    expect(continueButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays overflow-free on 640/720/800 height breakpoints',
      (tester) async {
    const heights = [640.0, 720.0, 800.0];

    for (final height in heights) {
      await pumpScreen(
        tester,
        physicalSize: Size(360, height),
        keyboardInset: 280,
      );
      await openPhoneForm(tester);

      expect(find.byKey(const Key('send_code_button')), findsOneWidget);
      expect(find.byKey(const Key('google_auth_button')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
