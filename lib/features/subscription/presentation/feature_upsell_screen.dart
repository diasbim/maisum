import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../design_system/design_system.dart';
import '../services/remote_config_reader.dart';

const featureUpsellRoutePath = '/feature-upsell';

class FeatureUpsellArgs {
  const FeatureUpsellArgs({
    required this.featureKey,
    required this.featureName,
    this.reason,
  });

  final String featureKey;
  final String featureName;
  final String? reason;

  factory FeatureUpsellArgs.fromQuery(Map<String, String> query) {
    return FeatureUpsellArgs(
      featureKey: query['featureKey'] ?? '',
      featureName: query['featureName'] ?? 'Funcionalidade paga',
      reason: query['reason'],
    );
  }
}

String featureUpsellLocation({
  required String featureKey,
  required String featureName,
  String? reason,
}) {
  return Uri(
    path: featureUpsellRoutePath,
    queryParameters: {
      'featureKey': featureKey,
      'featureName': featureName,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason,
    },
  ).toString();
}

Uri buildFeatureUpsellWhatsAppUri({
  required UpsellWhatsAppConfig config,
  required String featureName,
  String? reason,
}) {
  final feature =
      featureName.trim().isEmpty ? 'Funcionalidade paga' : featureName.trim();
  final message = [
    config.message.trim(),
    'Funcionalidade: $feature',
    'Motivo: ${_reasonLabel(reason)}',
  ].where((line) => line.isNotEmpty).join('\n\n');

  return Uri.parse(
    'https://wa.me/${config.number}?text=${Uri.encodeComponent(message)}',
  );
}

class FeatureUpsellScreen extends ConsumerStatefulWidget {
  const FeatureUpsellScreen({super.key, required this.args});

  final FeatureUpsellArgs args;

  @override
  ConsumerState<FeatureUpsellScreen> createState() =>
      _FeatureUpsellScreenState();
}

class _FeatureUpsellScreenState extends ConsumerState<FeatureUpsellScreen> {
  bool _openingWhatsApp = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _titleForReason(widget.args.reason);
    final subtitle = _subtitleForReason(widget.args.reason);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Desbloquear funcionalidade'),
        backgroundColor: AppColors.offWhite,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: MaisUmSurface(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.secondaryLight,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: const Icon(
                        Icons.lock_open_rounded,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      widget.args.featureName,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    MaisUmButton(
                      label: 'Falar no WhatsApp',
                      loadingLabel: 'A abrir WhatsApp...',
                      isLoading: _openingWhatsApp,
                      leadingIcon: Icons.chat_bubble_outline_rounded,
                      onPressed: _openWhatsApp,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    MaisUmButton(
                      label: 'Ver subscrição',
                      variant: MaisUmButtonVariant.ghost,
                      onPressed: () => context.push('/subscription-admin'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openWhatsApp() async {
    if (_openingWhatsApp) return;
    setState(() => _openingWhatsApp = true);
    try {
      final config =
          await ref.read(remoteConfigReaderProvider).getUpsellWhatsAppConfig();
      final uri = buildFeatureUpsellWhatsAppUri(
        config: config,
        featureName: widget.args.featureName,
        reason: widget.args.reason,
      );
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        AppFeedback.showMessage(
          context,
          message: 'Não foi possível abrir o WhatsApp neste dispositivo.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingWhatsApp = false);
      }
    }
  }
}

String _titleForReason(String? reason) {
  return switch (reason) {
    'trial_expired' => 'O período de teste terminou',
    'quota_exceeded' => 'O limite do plano foi atingido',
    'subscription_inactive' || 'grace_expired' => 'Subscrição inativa',
    _ => 'Funcionalidade paga',
  };
}

String _subtitleForReason(String? reason) {
  return switch (reason) {
    'trial_expired' =>
      'O teste de 30 dias deu acesso a todas as funcionalidades. Para continuar a usar esta área, fale com a equipa MaisUm no WhatsApp.',
    'quota_exceeded' =>
      'O plano atual chegou ao limite desta funcionalidade. A equipa MaisUm pode ajudar a desbloquear mais capacidade.',
    'subscription_inactive' ||
    'grace_expired' =>
      'Regularize a subscrição para voltar a usar as funcionalidades pagas do MaisUm.',
    _ =>
      'Esta funcionalidade faz parte dos recursos pagos do MaisUm. Fale connosco no WhatsApp para desbloquear o acesso.',
  };
}

String _reasonLabel(String? reason) {
  return switch (reason) {
    'trial_expired' => 'teste terminado',
    'quota_exceeded' => 'limite atingido',
    'subscription_inactive' => 'subscrição inativa',
    'grace_expired' => 'período de graça terminado',
    'flag_disabled' => 'funcionalidade desativada',
    _ => 'funcionalidade paga',
  };
}
