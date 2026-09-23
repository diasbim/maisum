import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../design_system/components/loading_button.dart';
import '../../../design_system/components/maisum_app_bar.dart';
import '../../../design_system/components/maisum_surface.dart';
import '../../../design_system/components/maisum_text_field.dart';
import '../../../design_system/components/maisum_toast.dart';
import '../../../design_system/components/validation_state.dart';
import '../../business_profile/domain/business_profile.dart';
import 'reward_templates.dart';
import 'rewards_controller.dart';

/// Set up something customers can exchange their points for.
///
/// Job: a shop owner who has just started a loyalty programme and has no
/// intuition for what "500 pontos" is worth. The screen therefore does three
/// things the previous version did not: it says how points are earned, it
/// translates the points requirement into money the merchant recognises, and
/// it keeps the single primary action reachable while the keyboard is up.
class CreateRewardScreen extends ConsumerStatefulWidget {
  const CreateRewardScreen({super.key, this.initialTemplateCode});

  final String? initialTemplateCode;

  @override
  ConsumerState<CreateRewardScreen> createState() => _CreateRewardScreenState();
}

class _CreateRewardScreenState extends ConsumerState<CreateRewardScreen> {
  final _nameCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _pointsFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  String? _selectedTemplateCode;
  bool _isSaving = false;
  bool _hasSubmitted = false;
  ValidationState _nameState = ValidationState.neutral;
  ValidationState _pointsState = ValidationState.neutral;

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(_onNameFocusChanged);
    _pointsFocusNode.addListener(_onPointsFocusChanged);
    _pointsCtrl.addListener(_onPointsTextChanged);

    final template = rewardTemplateByCode(widget.initialTemplateCode);
    if (template != null) {
      _applyTemplate(template);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pointsCtrl
      ..removeListener(_onPointsTextChanged)
      ..dispose();
    _descCtrl.dispose();
    _nameFocusNode
      ..removeListener(_onNameFocusChanged)
      ..dispose();
    _pointsFocusNode
      ..removeListener(_onPointsFocusChanged)
      ..dispose();
    super.dispose();
  }

  /// Keeps the "vale X MZN em compras" line in step with every keystroke.
  void _onPointsTextChanged() {
    if (mounted) setState(() {});
  }

  void _onNameFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (_nameFocusNode.hasFocus) {
        _nameState = ValidationState.focused;
        return;
      }

      final hasName = _nameCtrl.text.trim().isNotEmpty;
      if (!_hasSubmitted && !hasName) {
        _nameState = ValidationState.neutral;
        return;
      }

      _nameState = hasName ? ValidationState.valid : ValidationState.invalid;
    });
    if (!_nameFocusNode.hasFocus) {
      _formKey.currentState?.validate();
    }
  }

  void _onPointsFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (_pointsFocusNode.hasFocus) {
        _pointsState = ValidationState.focused;
        return;
      }

      final hasPoints = _hasValidPoints(_pointsCtrl.text);
      if (!_hasSubmitted && _pointsCtrl.text.trim().isEmpty) {
        _pointsState = ValidationState.neutral;
        return;
      }

      _pointsState =
          hasPoints ? ValidationState.valid : ValidationState.invalid;
    });
    if (!_pointsFocusNode.hasFocus) {
      _formKey.currentState?.validate();
    }
  }

  void _applyTemplate(RewardTemplatePreset template) {
    _nameCtrl.text = template.rewardName;
    _pointsCtrl.text = template.pointsRequired.toString();
    _descCtrl.text = template.description;
    setState(() {
      _selectedTemplateCode = template.code;
      _nameState = ValidationState.valid;
      _pointsState = ValidationState.valid;
    });
  }

  /// Once the merchant edits a field by hand the chip no longer describes what
  /// is in the form, so it stops claiming to.
  void _clearTemplateIfEdited() {
    final code = _selectedTemplateCode;
    if (code == null) return;
    final template = rewardTemplateByCode(code);
    if (template == null) return;
    final stillMatches = _nameCtrl.text.trim() == template.rewardName &&
        _pointsCtrl.text.trim() == template.pointsRequired.toString();
    if (!stillMatches) {
      setState(() => _selectedTemplateCode = null);
    }
  }

  bool _hasValidPoints(String input) {
    final parsed = int.tryParse(input.trim());
    return parsed != null && parsed > 0;
  }

  int? get _points => int.tryParse(_pointsCtrl.text.trim());

  String? _validateName(String? value) {
    if (!_hasSubmitted && _nameFocusNode.hasFocus) {
      return null;
    }
    if (value == null || value.trim().isEmpty) {
      return AppStrings.rewardNameRequired;
    }
    return null;
  }

  String? _validatePoints(String? value) {
    if (!_hasSubmitted && _pointsFocusNode.hasFocus) {
      return null;
    }
    if (value == null || value.trim().isEmpty) {
      return AppStrings.pointsRequired;
    }
    if (!_hasValidPoints(value)) {
      return 'Indique um número de pontos maior que zero';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();
    if (!_hasSubmitted) {
      setState(() => _hasSubmitted = true);
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() {
        _nameState = _nameCtrl.text.trim().isEmpty
            ? ValidationState.invalid
            : ValidationState.valid;
        _pointsState = _hasValidPoints(_pointsCtrl.text)
            ? ValidationState.valid
            : ValidationState.invalid;
      });
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(rewardsControllerProvider.notifier).createReward(
            name: _nameCtrl.text.trim(),
            pointsRequired: int.parse(_pointsCtrl.text.trim()),
            description:
                _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          );
      if (!mounted) return;
      MaisUmToast.show(
        context,
        message: 'Recompensa criada. Já pode ser resgatada.',
        type: MaisUmToastType.success,
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/rewards');
      }
    } catch (error, stackTrace) {
      // Never show the raw exception: it is in English, it names internals, and
      // it tells the merchant nothing they can act on.
      AppErrorReporter.report(error, stackTrace, hint: 'create_reward');
      if (!mounted) return;
      MaisUmToast.show(
        context,
        message: 'Não foi possível criar a recompensa. Tente de novo.',
        type: MaisUmToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(activeBusinessProfileProvider).valueOrNull;
    final profileId = profile?.id ?? 'other';
    final pointsPerMzn =
        profile?.loyalty.pointsPerMzn ?? BusinessProfiles.generic.loyalty.pointsPerMzn;
    final rewardTemplates = rewardTemplatesForProfile(profileId);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: const MaisUmAppBar(
        title: AppStrings.novaRecompensa,
        fallbackLocation: '/rewards',
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HowPointsWork(pointsPerMzn: pointsPerMzn),
                      const SizedBox(height: AppSpacing.xxl),
                      const _SectionHeader(
                        title: 'Comece por um modelo',
                        subtitle:
                            'Toque num modelo para preencher tudo e ajuste o que quiser.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final template in rewardTemplates)
                            _RewardTemplateOption(
                              key: Key('reward_template_${template.code}'),
                              selected: _selectedTemplateCode == template.code,
                              icon: template.icon,
                              label: template.label,
                              onTap: _isSaving
                                  ? null
                                  : () => _applyTemplate(template),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      const _SectionHeader(
                        title: 'Detalhes da recompensa',
                        subtitle:
                            'É isto que a sua equipa e os clientes vão ver.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      MaisUmTextField(
                        label: AppStrings.nomeRecompensa,
                        controller: _nameCtrl,
                        focusNode: _nameFocusNode,
                        enabled: !_isSaving,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        hintText: 'Ex.: Corte grátis',
                        validator: _validateName,
                        validationState: _nameState,
                        showValidIcon: true,
                        onChanged: (_) {
                          _clearTemplateIfEdited();
                          if (_hasSubmitted && !_nameFocusNode.hasFocus) {
                            setState(() {
                              _nameState = _nameCtrl.text.trim().isEmpty
                                  ? ValidationState.invalid
                                  : ValidationState.valid;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      MaisUmTextField(
                        label: AppStrings.pontosNecessarios,
                        controller: _pointsCtrl,
                        focusNode: _pointsFocusNode,
                        enabled: !_isSaving,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        hintText: 'Ex.: 500',
                        validator: _validatePoints,
                        validationState: _pointsState,
                        showValidIcon: true,
                        onChanged: (_) {
                          _clearTemplateIfEdited();
                          if (_hasSubmitted && !_pointsFocusNode.hasFocus) {
                            setState(() {
                              _pointsState = _hasValidPoints(_pointsCtrl.text)
                                  ? ValidationState.valid
                                  : ValidationState.invalid;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _PointsMeaning(
                        points: _points,
                        pointsPerMzn: pointsPerMzn,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      MaisUmTextField(
                        label: AppStrings.descricao,
                        controller: _descCtrl,
                        enabled: !_isSaving,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        maxLines: 3,
                        hintText:
                            'Ex.: válido de segunda a quinta, não acumula com outras ofertas',
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _SubmitBar(
              isSaving: _isSaving,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// The anchor the merchant is missing: what a point is worth in the first place.
class _HowPointsWork extends StatelessWidget {
  const _HowPointsWork({required this.pointsPerMzn});

  final int pointsPerMzn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MaisUmSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppRadius.card,
      backgroundColor: AppColors.secondaryLight,
      borderColor: AppColors.secondary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.stars_rounded,
            color: AppColors.secondaryForeground,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como funcionam os pontos',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Cada ${_formatMzn(pointsPerMzn)} MZN gastos na sua loja valem '
                  '1 ponto. A recompensa é o que o cliente troca por esses pontos.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurface,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Turns an abstract points target into money the merchant recognises, and
/// flags the two ends where a reward stops working: trivial, or unreachable.
class _PointsMeaning extends StatelessWidget {
  const _PointsMeaning({required this.points, required this.pointsPerMzn});

  final int? points;
  final int pointsPerMzn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = points;

    if (value == null || value <= 0) {
      return Text(
        'Quantos pontos o cliente precisa de juntar para trocar.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      );
    }

    final requiredSpend = value * pointsPerMzn;
    final (icon, color, note) = switch (requiredSpend) {
      < 2000 => (
          Icons.info_outline_rounded,
          AppColors.secondaryForeground,
          'Alcança-se muito depressa — considere pedir mais pontos.',
        ),
      > 100000 => (
          Icons.info_outline_rounded,
          AppColors.secondaryForeground,
          'Pode demorar muito a alcançar — considere pedir menos pontos.',
        ),
      _ => (
          Icons.check_circle_outline_rounded,
          AppColors.greenDark,
          'Um objetivo realista para quem compra com regularidade.',
        ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_formatMzn(requiredSpend)} MZN em compras',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

/// The primary action, pinned so it survives a long form and an open keyboard.
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.isSaving, required this.onSubmit});

  final bool isSaving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.g100)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LoadingButton(
            label: AppStrings.criarRecompensa,
            loadingLabel: 'A criar recompensa…',
            onPressed: onSubmit,
            enabled: !isSaving,
            isLoading: isSaving,
            height: AppControlSize.button,
            radius: AppRadius.lg,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Duas a quatro recompensas simples funcionam melhor do que muitas.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardTemplateOption extends StatelessWidget {
  const _RewardTemplateOption({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Navy on cream when selected, and a check mark alongside it: selection is
    // never signalled by colour alone.
    final foreground = selected ? AppColors.primary : AppColors.onSurface;

    return MaisUmSurface(
      selected: selected,
      semanticButton: true,
      semanticLabel: selected ? 'Modelo $label, selecionado' : 'Modelo $label',
      onTap: onTap,
      radius: AppRadius.pill,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      backgroundColor: selected ? AppColors.secondaryLight : AppColors.white,
      borderColor: selected ? AppColors.secondaryDark : AppColors.g300,
      borderWidth: selected ? 2 : 1.2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.check_rounded : icon,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// Groups thousands so "50000" reads as "50 000" at a glance.
String _formatMzn(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
