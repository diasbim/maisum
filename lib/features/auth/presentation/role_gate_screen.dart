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
        systemNavigationBarColor: AppColors.surfaceContainerLow,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surfaceContainerLow,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _RoleGateHero(theme: theme)),
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppLayout.contentMaxWidth,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xxl,
                      AppSpacing.xl,
                      AppSpacing.xxxxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _RolePanel(
                          key: const Key('business_owner_role'),
                          icon: LucideIcons.building2,
                          accent: AppColors.primary,
                          accentSoft: AppColors.primary.withValues(
                            alpha: 0.08,
                          ),
                          eyebrow: 'PARA NEGÓCIOS',
                          title: 'Sou proprietário de negócio',
                          description: 'Gerir clientes, vendas, recompensas '
                              'e equipa num só lugar.',
                          features: const [
                            'Vendas e equipa em tempo real',
                            'Campanhas de fidelização à medida',
                          ],
                          ctaLabel: 'Aceder à área de negócio',
                          semanticLabel: 'Sou proprietário de negócio. '
                              'Entrar na área do negócio.',
                          onPressed: () =>
                              context.go('/login?source=role'),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _RolePanel(
                          key: const Key('customer_role'),
                          icon: LucideIcons.userRound,
                          accent: AppColors.secondaryForeground,
                          accentSoft: AppColors.secondary.withValues(
                            alpha: 0.22,
                          ),
                          eyebrow: 'PARA CLIENTES',
                          title: 'Sou cliente',
                          description: 'Consultar pontos, descobrir prémios '
                              'e apresentar o seu código.',
                          features: const [
                            'Pontos e prémios em tempo real',
                            'Código pessoal em qualquer loja',
                          ],
                          ctaLabel: 'Aceder à área de cliente',
                          semanticLabel:
                              'Sou cliente. Entrar na área do cliente.',
                          onPressed: () => context
                              .go('/customer-login/phone?source=role'),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        const _RoleSwitchNote(),
                      ],
                    ),
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

class _RoleGateHero extends StatelessWidget {
  const _RoleGateHero({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.xxl),
          bottomRight: Radius.circular(AppRadius.xxl),
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryDarker, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -60,
                right: -40,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.secondary.withValues(alpha: 0.28),
                        AppColors.secondary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppLayout.contentMaxWidth,
                    ),
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
                              color:
                                  AppColors.secondary.withValues(alpha: 0.14),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: AppColors.secondary.withValues(
                                  alpha: 0.28,
                                ),
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
                            'Cada perfil tem uma experiência própria, '
                            'criada à medida.',
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
            ],
          ),
        ),
      );
}

class _RolePanel extends StatefulWidget {
  const _RolePanel({
    super.key,
    required this.icon,
    required this.accent,
    required this.accentSoft,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.features,
    required this.ctaLabel,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color accent;
  final Color accentSoft;
  final String eyebrow;
  final String title;
  final String description;
  final List<String> features;
  final String ctaLabel;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  State<_RolePanel> createState() => _RolePanelState();
}

class _RolePanelState extends State<_RolePanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.35)
                  : AppColors.divider,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDarker.withValues(
                  alpha: _hovered ? 0.12 : 0.05,
                ),
                blurRadius: _hovered ? 28 : 16,
                offset: Offset(0, _hovered ? 12 : 6),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              onTap: widget.onPressed,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: widget.accentSoft,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.accent,
                            size: 24,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          widget.eyebrow,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      widget.title,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: AppColors.primaryDarker,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        height: 1.15,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      widget.description,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    for (final feature in widget.features) ...[
                      _FeatureRow(text: feature, accent: widget.accent),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.ctaLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: widget.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        _RoleArrowButton(accent: widget.accent),
                      ],
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
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.check, size: 16, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      );
}

class _RoleArrowButton extends StatelessWidget {
  const _RoleArrowButton({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          LucideIcons.arrowRight,
          color: accent,
          size: 18,
        ),
      );
}

class _RoleSwitchNote extends StatelessWidget {
  const _RoleSwitchNote();

  @override
  Widget build(BuildContext context) {
    const color = AppColors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.arrowLeftRight, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Pode mudar de perfil sempre que quiser, nas definições.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
