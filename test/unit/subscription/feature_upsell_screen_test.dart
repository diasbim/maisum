import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/subscription/domain/remote_config_defaults.dart';
import 'package:maisum/features/subscription/presentation/feature_upsell_screen.dart';
import 'package:maisum/features/subscription/services/remote_config_reader.dart';

void main() {
  test('builds WhatsApp URI with encoded feature and reason', () {
    final uri = buildFeatureUpsellWhatsAppUri(
      config: const UpsellWhatsAppConfig(
        number: '258823262347',
        message: 'Ola. Quero desbloquear o MaisUm.',
      ),
      featureName: 'Retencao inteligente',
      reason: 'trial_expired',
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/258823262347');

    final text = uri.queryParameters['text']!;
    expect(text, contains('Ola. Quero desbloquear o MaisUm.'));
    expect(text, contains('Funcionalidade: Retencao inteligente'));
    expect(text, contains('Motivo: teste terminado'));
  });

  test('uses fallback upsell WhatsApp config constants', () {
    const config = UpsellWhatsAppConfig(
      number: RemoteConfigDefaults.upsellWhatsAppNumber,
      message: RemoteConfigDefaults.upsellWhatsAppMessage,
    );

    final uri = buildFeatureUpsellWhatsAppUri(
      config: config,
      featureName: '',
    );

    expect(uri.path, '/258823262347');
    expect(
      uri.queryParameters['text'],
      contains('Funcionalidade: Funcionalidade paga'),
    );
  });
}
