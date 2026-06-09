import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/features/auth/domain/auth_session.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/settings/presentation/merchant_config_screen.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession?> build() async => _session;
}

Widget _buildScreen(AuthSession session) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(session)),
      firestoreInstanceProvider.overrideWithValue(FakeFirebaseFirestore()),
    ],
    child: const MaterialApp(home: MerchantConfigScreen()),
  );
}

void main() {
  final session = AuthSession(
    userId: 'user-1',
    appUserId: 'app-user-1',
    merchantId: 'merchant-1',
    merchantName: 'Minha Loja',
    subscriptionStatus: 'TRIAL',
    phone: '841234567',
    token: 'token',
    expiresAt: DateTime(2099, 1, 1),
  );

  testWidgets('starts merchant name empty for legacy default value',
      (tester) async {
    await tester.pumpWidget(_buildScreen(session));
    await tester.pumpAndSettle();

    final nameField =
        tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(nameField.controller?.text, isEmpty);
    expect(find.text('Ex.: Barbearia Nova Era'), findsOneWidget);
  });

  testWidgets('preselects default city as Maputo', (tester) async {
    await tester.pumpWidget(_buildScreen(session));
    await tester.pumpAndSettle();

    final cityDropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    expect(cityDropdown.initialValue, 'Maputo');
  });

  testWidgets('preselects default business type as barbershop', (tester) async {
    await tester.pumpWidget(_buildScreen(session));
    await tester.pumpAndSettle();

    final businessDropdown =
        tester.widget<DropdownButtonFormField<BusinessType>>(
      find.byType(DropdownButtonFormField<BusinessType>).first,
    );
    expect(businessDropdown.initialValue, BusinessType.barbershop);
  });
}
