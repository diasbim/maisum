import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../design_system/design_system.dart';
import '../../domain/merchant_onboarding_models.dart';
import '../controllers/merchant_onboarding_controller.dart';
import '../widgets/onboarding_widgets.dart';

class BusinessTypePage extends ConsumerStatefulWidget {
  const BusinessTypePage({super.key});

  @override
  ConsumerState<BusinessTypePage> createState() => _BusinessTypePageState();
}

class _BusinessTypePageState extends ConsumerState<BusinessTypePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(merchantOnboardingControllerProvider.notifier)
          .setCurrentStep(MerchantOnboardingStep.businessType);
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(merchantOnboardingControllerProvider);

    return asyncState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(
          body: ErrorCard(
        message: 'Não foi possível carregar a configuração inicial.',
      )),
      data: (state) {
        final types = state.config.businessTypes;

        return _BusinessTypeShell(
          types: types,
          selectedType: state.draft.businessType,
          errorMessage: state.errorMessage,
          iconFor: _iconFor,
          onBack: () => Navigator.of(context).maybePop(),
          onSelect: (id) {
            return ref
                .read(merchantOnboardingControllerProvider.notifier)
                .selectBusinessType(id);
          },
          onContinue: () async {
            final moved = await ref
                .read(merchantOnboardingControllerProvider.notifier)
                .continueFromStep(MerchantOnboardingStep.businessType);
            if (moved && context.mounted) {
              context.go(MerchantOnboardingStep.businessInfo.route);
            }
          },
        );
      },
    );
  }

  IconData _iconFor(String? iconKey) {
    return switch (iconKey) {
      'barbershop' || 'cut' => Icons.content_cut_rounded,
      'salon' => Icons.chair_rounded,
      'spa' => Icons.spa_rounded,
      'restaurant' => Icons.restaurant_rounded,
      'cafe' => Icons.local_cafe_rounded,
      'clinic' => Icons.health_and_safety_rounded,
      'gym' => Icons.fitness_center_rounded,
      'workshop' => Icons.build_rounded,
      'services' => Icons.business_center_rounded,
      'store' => Icons.storefront_rounded,
      _ => Icons.shopping_bag_rounded,
    };
  }
}

class _BusinessTypeShell extends StatefulWidget {
  const _BusinessTypeShell({
    required this.types,
    required this.selectedType,
    required this.errorMessage,
    required this.iconFor,
    required this.onBack,
    required this.onSelect,
    required this.onContinue,
  });

  final List<MerchantBusinessType> types;
  final String? selectedType;
  final String? errorMessage;
  final IconData Function(String? iconKey) iconFor;
  final VoidCallback onBack;
  final Future<void> Function(String id) onSelect;
  final Future<void> Function() onContinue;

  @override
  State<_BusinessTypeShell> createState() => _BusinessTypeShellState();
}

class _BusinessTypeShellState extends State<_BusinessTypeShell> {
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.selectedType;
  }

  @override
  void didUpdateWidget(covariant _BusinessTypeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedType != oldWidget.selectedType) {
      _selectedType = widget.selectedType;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.white,
              AppColors.offWhite,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth >= AppBreakpoints.tablet
                  ? AppLayout.formMaxWidth
                  : null;
              final compact = constraints.maxHeight < 690;

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth ?? constraints.maxWidth,
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xxl,
                      compact ? AppSpacing.sm : AppSpacing.md,
                      AppSpacing.xxl,
                      AppSpacing.xxl,
                    ),
                    children: [
                      _BusinessTypeProgressHeader(onBack: widget.onBack),
                      SizedBox(
                          height: compact ? AppSpacing.xxl : AppSpacing.xxxxxl),
                      Text(
                        'Qual é o tipo do negócio?',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(
                              color: AppColors.primaryDarker,
                              fontSize: compact || constraints.maxWidth < 360
                                  ? 32
                                  : 40,
                              height: 1.08,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                      ),
                      SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
                      Text(
                        'Escolha a categoria mais próxima.',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: compact || constraints.maxWidth < 360
                                  ? 16
                                  : 18,
                              height: 1.34,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                            ),
                      ),
                      SizedBox(
                          height: compact ? AppSpacing.lg : AppSpacing.xxxl),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: widget.errorMessage == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.lg),
                                child: ErrorCard(message: widget.errorMessage!),
                              ),
                      ),
                      if (widget.types.isEmpty)
                        const ErrorCard(
                          message:
                              'As categorias de negócio ainda não foram configuradas no Firestore.',
                        )
                      else ...[
                        _BusinessTypeGrid(
                          compact: compact,
                          types: widget.types,
                          selectedType: _selectedType,
                          iconFor: widget.iconFor,
                          onSelect: _handleSelect,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _BusinessTypeTipCard(),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth >= AppBreakpoints.tablet
                ? AppLayout.formMaxWidth
                : null;
            final compact = constraints.maxHeight < 120;

            return Container(
              color: AppColors.offWhite,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                compact ? AppSpacing.sm : AppSpacing.md,
                AppSpacing.xxl,
                AppSpacing.md,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth ?? constraints.maxWidth,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BusinessTypeContinueButton(
                        compact: compact,
                        enabled:
                            widget.types.isNotEmpty && _selectedType != null,
                        onPressed: _handleContinue,
                      ),
                      SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                      _BusinessTypeAutosaveNote(compact: compact),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleSelect(String id) async {
    setState(() => _selectedType = id);
    await widget.onSelect(id);
  }

  Future<void> _handleContinue() async {
    final selectedType = _selectedType;
    if (selectedType == null) return;
    if (selectedType != widget.selectedType) {
      await widget.onSelect(selectedType);
    }
    await widget.onContinue();
  }
}

class _BusinessTypeProgressHeader extends StatelessWidget {
  const _BusinessTypeProgressHeader({required this.onBack});

  static const _step = MerchantOnboardingStep.businessType;

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Passo ${_step.number} de ${_step.total}',
      child: Row(
        children: [
          SizedBox(
            width: AppControlSize.iconButton,
            height: AppControlSize.iconButton,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.primary,
              iconSize: 24,
              padding: EdgeInsets.zero,
              tooltip: 'Voltar',
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: _BusinessTypeProgressSegments(step: _step),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '${_step.number} de ${_step.total}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessTypeProgressSegments extends StatelessWidget {
  const _BusinessTypeProgressSegments({required this.step});

  final MerchantOnboardingStep step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < step.total; index++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color:
                    index < step.number ? AppColors.secondary : AppColors.g100,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
          if (index < step.total - 1) const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _BusinessTypeGrid extends StatelessWidget {
  const _BusinessTypeGrid({
    required this.compact,
    required this.types,
    required this.selectedType,
    required this.iconFor,
    required this.onSelect,
  });

  final bool compact;
  final List<MerchantBusinessType> types;
  final String? selectedType;
  final IconData Function(String? iconKey) iconFor;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.md;
        final itemWidth = (constraints.maxWidth - (spacing * 2)) / 3;
        final itemHeight = compact ? itemWidth * 1.2 : itemWidth / 0.86;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final option in types)
              SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: _BusinessTypeOptionCard(
                  key: Key('business_type_option_${option.id}'),
                  compact: compact,
                  label: option.label,
                  icon: iconFor(option.iconKey),
                  selected: selectedType == option.id,
                  onTap: () => onSelect(option.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BusinessTypeOptionCard extends StatelessWidget {
  const _BusinessTypeOptionCard({
    super.key,
    required this.compact,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final bool compact;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected ? AppColors.white : AppColors.primaryDarker;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MaisUmSurface(
        onTap: onTap,
        selected: selected,
        radius: AppRadius.lg,
        borderWidth: selected ? 2 : 1.4,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          compact ? AppSpacing.sm : AppSpacing.md,
          AppSpacing.md,
          compact ? AppSpacing.sm : AppSpacing.md,
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: compact ? 18 : 22,
                height: compact ? 18 : 22,
                child: selected
                    ? DecoratedBox(
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: AppColors.primaryDarker,
                          size: compact ? 13 : 16,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const Spacer(),
            Icon(
              icon,
              color: selected ? AppColors.secondary : foreground,
              size: compact ? 24 : 34,
            ),
            SizedBox(height: compact ? AppSpacing.xs : 10),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground,
                fontSize: compact ? 11 : 14,
                height: 1.12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessTypeTipCard extends StatelessWidget {
  const _BusinessTypeTipCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MaisUmSurface(
      variant: MaisUmSurfaceVariant.muted,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.primaryDarker,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              color: AppColors.secondary,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Pode alterar depois nas definições.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const _BusinessTypeTargetMark(),
        ],
      ),
    );
  }
}

class _BusinessTypeTargetMark extends StatelessWidget {
  const _BusinessTypeTargetMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.adjust_rounded,
            color: AppColors.primaryDarker,
            size: 46,
          ),
          Icon(
            Icons.arrow_forward_rounded,
            color: AppColors.secondary,
            size: 24,
          ),
        ],
      ),
    );
  }
}

class _BusinessTypeContinueButton extends StatelessWidget {
  const _BusinessTypeContinueButton({
    required this.compact,
    required this.enabled,
    required this.onPressed,
  });

  final bool compact;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MaisUmButton(
      label: 'Continuar',
      onPressed: onPressed,
      enabled: enabled,
      height: compact ? AppControlSize.button : AppControlSize.buttonLarge,
      trailingIcon: Icons.arrow_forward_rounded,
      iconColor: AppColors.secondary,
    );
  }
}

class _BusinessTypeAutosaveNote extends StatelessWidget {
  const _BusinessTypeAutosaveNote({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.cloud_done_outlined,
          color: AppColors.onSurfaceVariant,
          size: compact ? 14 : 16,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            'Guardamos o seu progresso automaticamente',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
