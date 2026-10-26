import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/customer_experience_theme.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';

const _business = CustomerBusiness(
  id: 'business-real-1',
  name: 'Café Central',
  address: 'Av. 24 de Julho',
  phone: '+258820000001',
  confirmedPoints: 120,
  rewards: [],
);

const _featureFlags = CustomerFeatureFlags(
  appEnabled: true,
  redemptionEnabled: true,
  qrEnabled: true,
  pushEnabled: true,
  deepLinksEnabled: true,
);

class _FakeBusinessRepository extends Fake implements CustomerAppRepository {
  @override
  Future<CustomerData<CustomerBusiness>> business(String id) async =>
      CustomerData(_business, fromCache: false, updatedAt: DateTime(2025));

  @override
  Future<CustomerFeatureFlags> featureFlags() async => _featureFlags;
}

Widget _buildScreen() => ProviderScope(
      overrides: [
        customerAppRepositoryProvider.overrideWithValue(
          _FakeBusinessRepository(),
        ),
      ],
      child: const MaterialApp(
        home: CustomerExperienceTheme(
          child: CustomerBusinessDetailScreen(businessId: 'business-real-1'),
        ),
      ),
    );

void main() {
  testWidgets(
    'shows a recoverable error instead of failing silently when WhatsApp cannot open',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch' || call.method == 'launchUrl') {
          return false;
        }
        if (call.method == 'canLaunch' || call.method == 'canLaunchUrl') {
          return true;
        }
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Contactar no WhatsApp'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text(
          'Não foi possível abrir o WhatsApp. Verifique se está instalado.',
        ),
        findsOneWidget,
      );
      // The failure must be caught and reported through feedback, never
      // left as an unhandled exception from the unawaited launch call.
      expect(tester.takeException(), isNull);
    },
  );
}
