import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';

class RoleGateScreen extends StatelessWidget {
  const RoleGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.secondary,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.secondary,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _RoleGateHero(theme: theme)),
            SliverToBoxAdapter(
              child: _RolePanel(
                key: const Key('business_owner_role'),
                background: AppColors.primaryDark,
                eyebrow: 'PARA NEGÓCIOS',
                eyebrowColor: AppColors.secondary,
                title: 'Sou proprietário de negócio',
                titleColor: AppColors.white,
                description: 'Gerir clientes, vendas, recompensas e equipa '
                    'num só lugar.',
                descriptionColor: AppColors.white.withValues(alpha: 0.72),
                arrowBackground: AppColors.secondary,
                arrowForeground: AppColors.primaryDarker,
                semanticLabel: 'Sou proprietário de negócio. '
                    'Entrar na área do negócio.',
                onPressed: () => context.go('/login?source=role'),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: _RolePanel(
                key: const Key('customer_role'),
                background: AppColors.secondary,
                eyebrow: 'PARA CLIENTES',
                eyebrowColor: AppColors.onSurfaceVariant,
                title: 'Sou cliente',
                titleColor: AppColors.primaryDarker,
                description: 'Consultar pontos, descobrir prémios e '
                    'apresentar o seu código.',
                descriptionColor:
                    AppColors.primaryDarker.withValues(alpha: 0.72),
                arrowBackground: AppColors.primaryDarker,
                arrowForeground: AppColors.white,
                semanticLabel: 'Sou cliente. Entrar na área do cliente.',
                onPressed: () =>
                    context.go('/customer-login/phone?source=role'),
                footer: const _RoleSwitchNote(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleGateHero extends StatelessWidget {
  const _RoleGateHero({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryDarker, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppLayout.contentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: AppColors.secondary.withValues(alpha: 0.28),
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
                        fontSize: 34,
                        height: 1.05,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Cada perfil tem uma experiência própria.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.white.withValues(alpha: 0.6),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _RolePanel extends StatelessWidget {
  const _RolePanel({
    super.key,
    required this.background,
    required this.eyebrow,
    required this.eyebrowColor,
    required this.title,
    required this.titleColor,
    required this.description,
    required this.descriptionColor,
    required this.arrowBackground,
    required this.arrowForeground,
    required this.semanticLabel,
    required this.onPressed,
    this.footer,
  });

  final Color background;
  final String eyebrow;
  final Color eyebrowColor;
  final String title;
  final Color titleColor;
  final String description;
  final Color descriptionColor;
  final Color arrowBackground;
  final Color arrowForeground;
  final String semanticLabel;
  final VoidCallback onPressed;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onPressed,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppLayout.contentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xxxxl,
                  AppSpacing.xl,
                  AppSpacing.xxxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                eyebrow,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: eyebrowColor,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                title,
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  color: titleColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 28,
                                  height: 1.15,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        _RoleArrowButton(
                          background: arrowBackground,
                          foreground: arrowForeground,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      description,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: descriptionColor,
                        height: 1.45,
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleArrowButton extends StatelessWidget {
  const _RoleArrowButton({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(
          Icons.arrow_forward_rounded,
          color: foreground,
          size: 22,
        ),
      );
}

class _RoleSwitchNote extends StatelessWidget {
  const _RoleSwitchNote();

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primaryDarker.withValues(alpha: 0.65);
    return Row(
      children: [
        Icon(LucideIcons.arrowLeftRight, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Pode mudar de perfil depois de terminar a sessão.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
