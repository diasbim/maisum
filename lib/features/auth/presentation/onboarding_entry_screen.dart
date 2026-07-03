import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../design_system/design_system.dart';

class OnboardingEntryScreen extends StatefulWidget {
  const OnboardingEntryScreen({super.key});

  @override
  State<OnboardingEntryScreen> createState() => _OnboardingEntryScreenState();
}

class _OnboardingEntryScreenState extends State<OnboardingEntryScreen> {
  _OnboardingIntent? _selectedIntent;
  String? _errorMessage;

  void _selectIntent(_OnboardingIntent intent) {
    setState(() {
      _selectedIntent = intent;
      _errorMessage = null;
    });
  }

  void _continue() {
    if (_selectedIntent == null) {
      const message = 'Selecione uma opcao para continuar.';
      setState(() => _errorMessage = message);
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
      return;
    }

    final route = _selectedIntent == _OnboardingIntent.joinExisting
        ? '/link-device'
        : '/merchant-onboarding/type';
    try {
      context.go(route);
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'onboarding_entry_continue');
      const message = 'Nao foi possivel continuar. Tente novamente.';
      setState(() => _errorMessage = message);
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Como comecar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Passo 1 de 2',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: 'Progresso do onboarding',
            value: '50 por cento, passo 1 de 2',
            readOnly: true,
            child: LinearProgressIndicator(
              value: 0.5,
              borderRadius: BorderRadius.circular(999),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Escolha uma opcao para continuar.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          _IntentCard(
            icon: Icons.link_rounded,
            intent: _OnboardingIntent.joinExisting,
            isSelected: _selectedIntent == _OnboardingIntent.joinExisting,
            onSelected: _selectIntent,
            title: 'Entrar em barbearia existente',
            subtitle: 'Usar codigo da barbearia.',
            semanticsLabel: 'Entrar em barbearia existente',
            semanticsHint:
                'Abre o fluxo para vincular este dispositivo com codigo.',
          ),
          const SizedBox(height: AppSpacing.md),
          _IntentCard(
            icon: Icons.storefront_rounded,
            intent: _OnboardingIntent.createNew,
            isSelected: _selectedIntent == _OnboardingIntent.createNew,
            onSelected: _selectIntent,
            title: 'Criar nova barbearia',
            subtitle: 'Iniciar uma nova configuracao de negocio.',
            semanticsLabel: 'Criar nova barbearia',
            semanticsHint: 'Abre o fluxo de criacao da barbearia.',
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              liveRegion: true,
              container: true,
              label: 'Erro: $_errorMessage',
              child: MaisUmSurface(
                variant: MaisUmSurfaceVariant.error,
                radius: AppRadius.md,
                padding: const EdgeInsets.all(AppSpacing.md),
                borderColor: theme.colorScheme.error,
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            button: true,
            label: 'Continuar para o proximo passo',
            hint: 'Abre o fluxo escolhido.',
            child: MaisUmButton(
              label: 'Continuar',
              onPressed: _continue,
              height: AppControlSize.button,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MaisUmSurface(
            variant: MaisUmSurfaceVariant.muted,
            radius: AppRadius.md,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'Pode concluir em etapas. O app retoma de onde parou.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

enum _OnboardingIntent { joinExisting, createNew }

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.icon,
    required this.intent,
    required this.isSelected,
    required this.onSelected,
    required this.title,
    required this.subtitle,
    required this.semanticsLabel,
    required this.semanticsHint,
  });

  final IconData icon;
  final _OnboardingIntent intent;
  final bool isSelected;
  final ValueChanged<_OnboardingIntent> onSelected;
  final String title;
  final String subtitle;
  final String semanticsLabel;
  final String semanticsHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionColor = isSelected ? AppColors.secondary : AppColors.g300;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: semanticsLabel,
        hint: semanticsHint,
        child: MaisUmSurface(
          onTap: () => onSelected(intent),
          selected: isSelected,
          semanticButton: true,
          semanticLabel: semanticsLabel,
          radius: AppRadius.lg,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppControlSize.iconButton,
                height: AppControlSize.iconButton,
                decoration: BoxDecoration(
                  color: selectionColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 24, color: selectionColor),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isSelected ? AppColors.white : null,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isSelected
                            ? AppColors.white.withValues(alpha: 0.78)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selectionColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
