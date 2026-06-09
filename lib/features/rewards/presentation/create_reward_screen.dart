import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../design_system/components/loading_button.dart';
import '../../../design_system/components/maisum_text_field.dart';
import '../../../design_system/components/maisum_toast.dart';
import '../../../design_system/components/validation_state.dart';
import 'reward_templates.dart';
import 'rewards_controller.dart';

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

    final template = rewardTemplateByCode(widget.initialTemplateCode);
    if (template != null) {
      _applyTemplate(template);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pointsCtrl.dispose();
    _descCtrl.dispose();
    _nameFocusNode
      ..removeListener(_onNameFocusChanged)
      ..dispose();
    _pointsFocusNode
      ..removeListener(_onPointsFocusChanged)
      ..dispose();
    super.dispose();
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

      _pointsState = hasPoints ? ValidationState.valid : ValidationState.invalid;
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

  bool _hasValidPoints(String input) {
    final parsed = int.tryParse(input.trim());
    return parsed != null && parsed > 0;
  }

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
      return 'Valor invalido';
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
        message: 'Recompensa criada com sucesso.',
        type: MaisUmToastType.success,
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/rewards');
      }
    } catch (e) {
      if (!mounted) return;
      MaisUmToast.show(
        context,
        message: e.toString(),
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text(AppStrings.novaRecompensa)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboardInset),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crie uma recompensa em segundos',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Escolha um template rapido ou personalize os campos.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final template in rewardTemplatePresets)
                      ChoiceChip(
                        key: Key('reward_template_${template.code}'),
                        avatar: Icon(
                          template.icon,
                          size: 16,
                          color: _selectedTemplateCode == template.code
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant,
                        ),
                        label: Text(template.label),
                        selected: _selectedTemplateCode == template.code,
                        onSelected: (_) => _applyTemplate(template),
                        selectedColor: AppColors.secondaryLight,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                MaisUmTextField(
                  label: AppStrings.nome,
                  controller: _nameCtrl,
                  focusNode: _nameFocusNode,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  hintText: AppStrings.nomeRecompensa,
                  validator: _validateName,
                  validationState: _nameState,
                  showValidIcon: true,
                  onChanged: (_) {
                    if (_hasSubmitted && !_nameFocusNode.hasFocus) {
                      setState(() {
                        _nameState = _nameCtrl.text.trim().isEmpty
                            ? ValidationState.invalid
                            : ValidationState.valid;
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                MaisUmTextField(
                  label: AppStrings.pontosNecessarios,
                  controller: _pointsCtrl,
                  focusNode: _pointsFocusNode,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  hintText: AppStrings.pontosNecessarios,
                  validator: _validatePoints,
                  validationState: _pointsState,
                  showValidIcon: true,
                  onChanged: (_) {
                    if (_hasSubmitted && !_pointsFocusNode.hasFocus) {
                      setState(() {
                        _pointsState = _hasValidPoints(_pointsCtrl.text)
                            ? ValidationState.valid
                            : ValidationState.invalid;
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                MaisUmTextField(
                  label: AppStrings.descricao,
                  controller: _descCtrl,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  maxLines: 3,
                  hintText: 'Detalhe opcional para a equipa e cliente',
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                LoadingButton(
                  label: AppStrings.guardar,
                  loadingLabel: 'A guardar recompensa...',
                  onPressed: _submit,
                  enabled: !_isSaving,
                  isLoading: _isSaving,
                  height: 56,
                  radius: 18,
                ),
                const SizedBox(height: 8),
                Text(
                  'Dica: mantenha 2-4 recompensas simples para facilitar o resgate.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
