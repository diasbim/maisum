import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../design_system/components/maisum_app_bar.dart';
import '../../../design_system/components/maisum_surface.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/widgets/customer_picker_field.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/presentation/feature_upsell_screen.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';
import '../services/survey_invite_service.dart';

/// Sending a survey, rather than transcribing one.
///
/// Until now a survey could only be answered by the merchant typing what a
/// customer said out loud. This screen produces the other half: a link the
/// customer opens themselves, either sent to one person over WhatsApp or shown
/// to anyone in the shop.
///
/// The difference between the two is the link, not the survey. A link minted
/// with a customer attributes the answer to them — which is what lets it feed
/// recovery; a link minted without one is anonymous and can be shown on a
/// counter or a poster.
class SurveySendScreen extends ConsumerStatefulWidget {
  const SurveySendScreen({super.key});

  @override
  ConsumerState<SurveySendScreen> createState() => _SurveySendScreenState();
}

class _SurveySendScreenState extends ConsumerState<SurveySendScreen> {
  static const _inviteService = SurveyInviteService();

  String? _selectedSurveyId;
  Customer? _customer;
  SurveyLink? _link;
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(engageAccessProvider);
    final surveysAsync = ref.watch(engageSurveysProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: const MaisUmAppBar(
        title: 'Enviar questionário',
        fallbackLocation: '/engage',
      ),
      body: accessAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (_, __) => const EmptyState(
          title: 'Não foi possível validar o acesso',
          subtitle: 'Tente novamente em alguns segundos.',
        ),
        data: (access) {
          if (!access.canManageSurveys) {
            return EmptyState(
              title: 'Envio de questionários indisponível',
              subtitle: 'Funcionalidade exclusiva do plano Business.',
              actionLabel: 'Ver opções',
              onAction: () => context.push(
                featureUpsellLocation(
                  featureKey: FeatureKeys.engageManageSurveys,
                  featureName: 'Enviar questionários',
                  reason: 'plan_restricted',
                ),
              ),
            );
          }

          return surveysAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
            error: (_, __) => const EmptyState(
              title: 'Não foi possível carregar os questionários',
              subtitle: 'Atualize e tente novamente.',
            ),
            data: (surveys) {
              final active = surveys.where((survey) => survey.isActive).toList();
              if (active.isEmpty) {
                return const EmptyState(
                  title: 'Nenhum questionário ativo',
                  subtitle: 'Crie um questionário antes de o enviar.',
                );
              }

              final selected = active.firstWhere(
                (survey) => survey.id == (_selectedSurveyId ?? active.first.id),
                orElse: () => active.first,
              );
              _selectedSurveyId ??= selected.id;

              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSurveyId,
                    decoration:
                        const InputDecoration(labelText: 'Questionário'),
                    items: active
                        .map(
                          (survey) => DropdownMenuItem(
                            value: survey.id,
                            child: Text(survey.title),
                          ),
                        )
                        .toList(),
                    onChanged: _working
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedSurveyId = value;
                              // The old link points at the old survey.
                              _link = null;
                            });
                          },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  CustomerPickerField(
                    label: 'Enviar a (opcional)',
                    selected: _customer,
                    optional: true,
                    enabled: !_working,
                    hintText: 'Link aberto, para qualquer pessoa',
                    helperText:
                        'Com um cliente escolhido, a resposta fica ligada a ele '
                        'e conta para a recuperação. Sem cliente, o link serve '
                        'para qualquer pessoa e a resposta é anónima.',
                    onChanged: (customer) => setState(() {
                      _customer = customer;
                      _link = null;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_link == null)
                    FilledButton.icon(
                      onPressed: _working ? null : () => _createLink(selected),
                      icon: _working
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link_rounded),
                      label: Text(_working ? 'A criar...' : 'Criar link'),
                    )
                  else
                    _LinkPanel(
                      link: _link!,
                      customer: _customer,
                      working: _working,
                      onCopy: _copyLink,
                      onWhatsApp: () => _sendWhatsApp(selected),
                      onReset: () => setState(() => _link = null),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createLink(EngageSurvey survey) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final link = await ref.read(engageRepositoryProvider).getSurveyLink(
            survey.id,
            customerId: _customer?.id,
          );
      if (!mounted) return;
      setState(() => _link = link);
      if (!link.isShareable) {
        // The server has no public address configured, so the token is real
        // but there is nowhere to send anybody. Better said plainly than sent.
        AppFeedback.showMessage(
          context,
          message: 'O link ainda não tem endereço público configurado.',
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showRetryableError(
        context,
        message: error is Exception
            ? 'Não foi possível criar o link. Tente novamente.'
            : 'Não foi possível criar o link. Tente novamente.',
        onRetry: () => _createLink(survey),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _copyLink() async {
    final link = _link;
    if (link == null || !link.isShareable) return;
    await Clipboard.setData(ClipboardData(text: link.url!));
    if (!mounted) return;
    AppFeedback.showSuccessToast(
      context,
      message: 'Link copiado',
      subtitle: 'Cole onde quiser partilhá-lo.',
    );
  }

  Future<void> _sendWhatsApp(EngageSurvey survey) async {
    final link = _link;
    final customer = _customer;
    if (link == null || customer == null || _working) return;

    setState(() => _working = true);
    try {
      final outcome = await _inviteService.send(
        customer: customer,
        survey: survey,
        link: link,
        isOnline: ref.read(connectivityServiceProvider).isOnline,
        launchWhatsApp: (uri) =>
            launchUrl(uri, mode: LaunchMode.externalApplication),
      );
      if (!mounted) return;

      switch (outcome) {
        case SurveyInviteDelivery.openedWhatsApp:
          AppFeedback.showSuccessToast(
            context,
            message: 'WhatsApp aberto',
            subtitle: 'A mensagem já leva o link do questionário.',
          );
        case SurveyInviteDelivery.consentRequired:
          AppFeedback.showMessage(
            context,
            message:
                '${customer.name} ainda não autorizou mensagens por WhatsApp.',
            isError: true,
          );
        case SurveyInviteDelivery.invalidPhone:
          AppFeedback.showMessage(
            context,
            message: 'O número deste cliente não serve para WhatsApp.',
            isError: true,
          );
        case SurveyInviteDelivery.offline:
          AppFeedback.showMessage(
            context,
            message: 'Sem ligação. O link continua aqui para copiar.',
            isError: true,
          );
        case SurveyInviteDelivery.noLink:
          AppFeedback.showMessage(
            context,
            message: 'O link ainda não tem endereço público configurado.',
            isError: true,
          );
        case SurveyInviteDelivery.failed:
          AppFeedback.showMessage(
            context,
            message: 'Não foi possível abrir o WhatsApp.',
            isError: true,
          );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

/// The link, once it exists, with the two ways to hand it over.
class _LinkPanel extends StatelessWidget {
  const _LinkPanel({
    required this.link,
    required this.customer,
    required this.working,
    required this.onCopy,
    required this.onWhatsApp,
    required this.onReset,
  });

  final SurveyLink link;
  final Customer? customer;
  final bool working;
  final VoidCallback onCopy;
  final VoidCallback onWhatsApp;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MaisUmSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            customer == null
                ? 'Link aberto, para qualquer pessoa'
                : 'Link para ${customer!.name}',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            link.url ?? 'Sem endereço público configurado.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Válido até ${_formatDate(link.expiresAt)}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (customer != null)
            FilledButton.icon(
              onPressed: working || !link.isShareable ? null : onWhatsApp,
              icon: const Icon(Icons.chat_rounded),
              label: const Text('Enviar por WhatsApp'),
            ),
          if (customer != null) const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: link.isShareable ? onCopy : null,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar link'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: working ? null : onReset,
            child: const Text('Criar outro link'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }
}
