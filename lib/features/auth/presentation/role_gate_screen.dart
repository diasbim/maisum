import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../design_system/components/maisum_button.dart';
import '../../../design_system/components/maisum_surface.dart';

class RoleGateScreen extends StatelessWidget {
  const RoleGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.offWhite,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryDarker, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xxxl,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppLayout.contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _RoleGateBrand(),
                        const SizedBox(height: AppSpacing.xxxl),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color:
                                  AppColors.secondary.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Text(
                            'ESCOLHA O SEU PERFIL',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Como quer usar\na MaisUm?',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Escolha a área certa para começar. Cada perfil tem uma experiência própria.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.white.withValues(alpha: 0.76),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppLayout.contentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xxl,
                    AppSpacing.xl,
                    AppSpacing.xxxl,
                  ),
                  child: Column(
                    children: [
                      _RoleChoiceCard(
                        key: const Key('business_owner_role'),
                        icon: LucideIcons.store,
                        eyebrow: 'PARA NEGÓCIOS',
                        title: 'Sou proprietário de negócio',
                        description:
                            'Gerir clientes, vendas, recompensas e equipa num só lugar.',
                        benefits: const [
                          'Acompanhar o desempenho do negócio',
                          'Fidelizar clientes e gerir operações',
                        ],
                        actionLabel: 'Entrar na área do negócio',
                        onPressed: () => context.go('/login?source=role'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _RoleChoiceCard(
                        key: const Key('customer_role'),
                        icon: LucideIcons.walletCards,
                        eyebrow: 'PARA CLIENTES',
                        title: 'Sou cliente',
                        description:
                            'Consultar pontos, descobrir prémios e apresentar o seu código.',
                        benefits: const [
                          'Ver todos os saldos rapidamente',
                          'Resgatar prémios sem complicações',
                        ],
                        customer: true,
                        actionLabel: 'Entrar na área do cliente',
                        onPressed: () =>
                            context.go('/customer-login/phone?source=role'),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            LucideIcons.arrowLeftRight,
                            size: 18,
                            color: AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              'Pode mudar de perfil depois de terminar a sessão.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleGateBrand extends StatelessWidget {
  const _RoleGateBrand();

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        label: 'MaisUm',
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.16),
                ),
              ),
              child: const BrandMark(size: 28),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Mais'),
                  TextSpan(
                    text: 'Um',
                    style: TextStyle(color: AppColors.secondary),
                  ),
                ],
              ),
              style: TextStyle(
                color: AppColors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.7,
              ),
            ),
          ],
        ),
      );
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.benefits,
    required this.actionLabel,
    required this.onPressed,
    this.customer = false,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final List<String> benefits;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MaisUmSurface(
      radius: AppRadius.xl,
      padding: const EdgeInsets.all(AppSpacing.xl),
      borderColor: customer ? AppColors.secondary : AppColors.g100,
      borderWidth: customer ? 1.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: customer
                      ? AppColors.secondaryLight
                      : AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primaryDarker,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: customer
                            ? AppColors.secondaryForeground
                            : AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.primaryDarker,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...benefits.map(
            (benefit) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: customer
                          ? AppColors.secondaryLight
                          : AppColors.surfaceContainerLow,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppColors.primaryDarker,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      benefit,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MaisUmButton(
            label: actionLabel,
            onPressed: onPressed,
            variant: customer
                ? MaisUmButtonVariant.secondary
                : MaisUmButtonVariant.primary,
            trailingIcon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}
