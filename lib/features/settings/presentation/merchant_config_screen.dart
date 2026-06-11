import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../auth/presentation/auth_controller.dart';

enum BusinessType {
  barbershop,
  salon,
  beauty,
  laundry,
  other,
}

extension BusinessTypeMapper on BusinessType {
  String get wireValue => switch (this) {
        BusinessType.barbershop => 'barbershop',
        BusinessType.salon => 'salon',
        BusinessType.beauty => 'beauty',
        BusinessType.laundry => 'laundry',
        BusinessType.other => 'other',
      };

  String get label => switch (this) {
        BusinessType.barbershop => 'Barbearia',
        BusinessType.salon => 'Salao',
        BusinessType.beauty => 'Beleza',
        BusinessType.laundry => 'Lavandaria',
        BusinessType.other => 'Outro',
      };

  static BusinessType fromStorage(String? rawValue) {
    final value = rawValue?.trim().toLowerCase() ?? '';
    switch (value) {
      case 'barbershop':
      case 'barbearia':
        return BusinessType.barbershop;
      case 'salon':
      case 'cabeleireiro':
      case 'salao':
        return BusinessType.salon;
      case 'beauty':
      case 'estetica':
      case 'beleza':
      case 'spa':
        return BusinessType.beauty;
      case 'laundry':
      case 'lavandaria':
        return BusinessType.laundry;
      case 'other':
      case 'outro':
        return BusinessType.other;
      default:
        return BusinessType.barbershop;
    }
  }
}

class MerchantConfigScreen extends ConsumerStatefulWidget {
  const MerchantConfigScreen({super.key});

  @override
  ConsumerState<MerchantConfigScreen> createState() =>
      _MerchantConfigScreenState();
}

class _MerchantConfigScreenState extends ConsumerState<MerchantConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  static const _legacyDefaultMerchantName = 'Minha Loja';
  static const _defaultCity = 'Maputo';
  static const _defaultBusinessType = BusinessType.barbershop;

  String? _selectedCity;
  BusinessType? _selectedBusinessType;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showSuccess = false;
  bool _wasProfileCompleteAtLoad = false;
  bool _processingPulse = false;
  int _processingStepIndex = 0;
  Timer? _processingTicker;

  static const _processingSteps = [
    'Validando dados',
    'A criar conta',
    'A preparar recompensas',
    'Tudo pronto',
  ];

  static const _cities = [
    'Maputo',
    'Matola',
    'Beira',
    'Nampula',
    'Chimoio',
    'Outra',
  ];

  @override
  void initState() {
    super.initState();
    _primeFields();
  }

  @override
  void dispose() {
    _processingTicker?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _startProcessingTicker() {
    _processingTicker?.cancel();
    _processingTicker = Timer.periodic(const Duration(milliseconds: 760), (_) {
      if (!mounted || !_isSaving) return;
      setState(() {
        _processingPulse = !_processingPulse;
        if (_processingStepIndex < _processingSteps.length - 2) {
          _processingStepIndex++;
        }
      });
    });
  }

  void _stopProcessingTicker() {
    _processingTicker?.cancel();
    _processingTicker = null;
  }

  Future<void> _primeFields() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    final initialMerchantName = (session?.merchantName ?? '').trim();
    _nameController.text = initialMerchantName == _legacyDefaultMerchantName
        ? ''
        : initialMerchantName;
    _phoneController.text = session?.phone ?? '';
    _selectedCity = _defaultCity;
    _selectedBusinessType = _defaultBusinessType;

    final merchantId = ref.read(activeMerchantIdProvider);
    if (merchantId != null && merchantId.isNotEmpty) {
      try {
        final doc = await ref
            .read(firestoreInstanceProvider)
            .collection('businesses')
            .doc(merchantId)
            .get();
        final data = doc.data();
        if (data != null) {
          final name = data['merchant_name'] as String?;
          final phone = data['phone'] as String?;
          final city = data['city'] as String?;
          final businessType = data['business_type'] as String?;

          if (name != null && name.trim().isNotEmpty) {
            _nameController.text = name;
          }
          if (phone != null && phone.trim().isNotEmpty) {
            _phoneController.text = phone;
          }
          _selectedCity = city != null && city.trim().isNotEmpty
              ? city.trim()
              : _defaultCity;
          _selectedBusinessType = BusinessTypeMapper.fromStorage(businessType);
        }
      } catch (e, st) {
        // Keep local defaults when remote data is not reachable.
        AppErrorReporter.report(e, st, hint: 'merchant_config_fetch');
      }
    }

    if (mounted) {
      _wasProfileCompleteAtLoad = _isProfileComplete();
      setState(() => _isLoading = false);
    }
  }

  bool _isProfileComplete() {
    final merchantName = _nameController.text.trim();
    return merchantName.isNotEmpty &&
        merchantName.toLowerCase() != _legacyDefaultMerchantName.toLowerCase();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final merchantId = ref.read(activeMerchantIdProvider);
    if (merchantId == null || merchantId.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: 'Sessao invalida.',
        isError: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    setState(() {
      _processingStepIndex = 0;
      _processingPulse = true;
    });
    _startProcessingTicker();

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final city = _selectedCity ?? _defaultCity;
    final businessType =
        (_selectedBusinessType ?? _defaultBusinessType).wireValue;

    try {
      final session = ref.read(authControllerProvider).valueOrNull;
      if (session == null) {
        throw StateError('Sem sessao ativa');
      }

      if (name.isNotEmpty && name != session.merchantName) {
        await ref
            .read(authControllerProvider.notifier)
            .updateMerchantName(name);
      }

      await ref
          .read(firestoreInstanceProvider)
          .collection('businesses')
          .doc(merchantId)
          .set({
        'merchant_name': name,
        'phone': phone,
        'city': city,
        'business_type': businessType,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      if (!_wasProfileCompleteAtLoad) {
        await ref
            .read(secureStorageServiceProvider)
            .setOnboardingPlanConfirmed(false);
      }

      if (!mounted) return;
      _stopProcessingTicker();
      setState(() {
        _processingStepIndex = _processingSteps.length - 1;
        _processingPulse = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _showSuccess = false;
      });
      HapticFeedback.mediumImpact();

      if (!_wasProfileCompleteAtLoad && context.mounted) {
        context.go('/onboarding-plan');
        return;
      }

      if (context.mounted) {
        AppFeedback.showMessage(
          context,
          message: 'Configuracoes guardadas com sucesso.',
          isError: false,
        );
        context.pop();
      }
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'merchant_config_save');
      if (!mounted) return;
      _stopProcessingTicker();
      setState(() {
        _processingPulse = false;
      });
      final info = AppErrorMapper.describe(e);
      AppFeedback.showMessage(
        context,
        message: info.message,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 140,
                right: -40,
                child: Opacity(
                  opacity: 0.92,
                  child: Image.asset(
                    'assets/images/barber.png',
                    width: 260,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (_isLoading)
                const Positioned.fill(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              if (!_isLoading)
                LayoutBuilder(
                  builder: (context, constraints) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      );
                      final scale = Tween<double>(begin: 0.98, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                      );
                      return FadeTransition(
                        opacity: fade,
                        child: ScaleTransition(scale: scale, child: child),
                      );
                    },
                    child: _showSuccess
                        ? _SetupSuccessView(
                            key: const ValueKey('setup-success-view'),
                            onPrimaryCta: () => context.go('/new-sale'),
                            onSecondaryCta: () => context.go('/dashboard'),
                          )
                        : SingleChildScrollView(
                            key: const ValueKey('setup-form-view'),
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight - 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _TopBar(
                                    onBack: () {
                                      if (context.canPop()) {
                                        context.pop();
                                        return;
                                      }
                                      context.go('/settings');
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  const _SetupSteps(currentStep: 0),
                                  const SizedBox(height: 28),
                                  Text.rich(
                                    TextSpan(
                                      text: 'Vamos\nconfigurar\n',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 30,
                                        height: 1.15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'a sua\n',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.85,
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const TextSpan(
                                          text: 'barbearia',
                                          style: TextStyle(
                                            color: AppColors.secondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Em poucos passos o MaisUm estara pronto para trazer\nclientes de volta.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                      height: 1.5,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  Form(
                                    key: _formKey,
                                    child: Column(
                                      children: [
                                        _ConfigTextField(
                                          controller: _nameController,
                                          label: 'Nome da barbearia',
                                          hint: 'Ex.: Barbearia Nova Era',
                                          icon: Icons.storefront_rounded,
                                          textInputAction: TextInputAction.next,
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'Introduza o nome do negocio';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        _ConfigTextField(
                                          controller: _phoneController,
                                          label: 'Telefone',
                                          hint: '+258 82 326 2347',
                                          icon: Icons.phone_rounded,
                                          readOnly: true,
                                          keyboardType: TextInputType.phone,
                                          textInputAction: TextInputAction.next,
                                        ),
                                        const SizedBox(height: 14),
                                        _ConfigDropdownField(
                                          label: 'Cidade',
                                          hint: 'Ex.: Maputo',
                                          icon: Icons.place_rounded,
                                          value: _selectedCity,
                                          items: _cities,
                                          onChanged: (value) {
                                            setState(
                                              () => _selectedCity = value,
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        _BusinessTypeDropdownField(
                                          label: 'Tipo de negocio',
                                          hint: 'Selecione o tipo de negocio',
                                          icon: Icons.content_cut_rounded,
                                          value: _selectedBusinessType,
                                          onChanged: (value) {
                                            setState(
                                              () =>
                                                  _selectedBusinessType = value,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Pode atualizar estas informacoes mais tarde nas definicoes.',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.55,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 32),
                                  _PrimaryActionButton(
                                    label: 'Continuar',
                                    loadingLabel: 'A criar sua barbearia...',
                                    loadingHint: '⏳ A sincronizar dados',
                                    isLoading: _isSaving,
                                    pulseOn: _processingPulse,
                                    onPressed: _isSaving ? null : _save,
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
              if (_isSaving)
                _ProcessingOverlay(
                  steps: _processingSteps,
                  activeStepIndex: _processingStepIndex,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 300;

        return Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  const Text.rich(
                    TextSpan(
                      text: 'Mais',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                      children: [
                        TextSpan(
                          text: 'Um',
                          style: TextStyle(color: AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const Spacer(),
            const SizedBox(width: 40),
          ],
        );
      },
    );
  }
}

class _SetupSteps extends StatelessWidget {
  const _SetupSteps({required this.currentStep});

  final int currentStep;

  static const _labels = ['Barbearia', 'Conta', 'Programa', 'Pronto'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (index) {
            final isActive = index == currentStep;
            final isDone = index < currentStep;
            return Expanded(
              child: Row(
                children: [
                  _StepCircle(active: isActive, done: isDone, index: index),
                  if (index != 3)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isDone || isActive
                            ? AppColors.secondary
                            : Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(4, (index) {
            final isActive = index == currentStep;
            return Expanded(
              child: Text(
                _labels[index],
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: isActive
                      ? AppColors.secondary
                      : Colors.white.withValues(alpha: 0.45),
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.active,
    required this.done,
    required this.index,
  });

  final bool active;
  final bool done;
  final int index;

  @override
  Widget build(BuildContext context) {
    final fill = active || done
        ? AppColors.secondary
        : Colors.white.withValues(alpha: 0.08);
    final border = active || done
        ? AppColors.secondary
        : Colors.white.withValues(alpha: 0.2);
    final textColor = active || done
        ? AppColors.primaryDarker
        : Colors.white.withValues(alpha: 0.6);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ConfigTextField extends StatelessWidget {
  const _ConfigTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.readOnly = false,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool readOnly;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      readOnly: readOnly,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: AppColors.secondary,
      validator: validator,
      decoration: _fieldDecoration(
        label: label,
        hint: hint,
        icon: icon,
      ),
    );
  }
}

class _BusinessTypeDropdownField extends StatelessWidget {
  const _BusinessTypeDropdownField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final IconData icon;
  final BusinessType? value;
  final ValueChanged<BusinessType?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<BusinessType>(
      initialValue: value,
      isExpanded: true,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: Colors.white.withValues(alpha: 0.7),
      ),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      dropdownColor: AppColors.primaryDark,
      decoration: _fieldDecoration(
        label: label,
        hint: hint,
        icon: icon,
      ),
      onChanged: onChanged,
      selectedItemBuilder: (context) => BusinessType.values
          .map(
            (item) => Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
          .toList(),
      items: BusinessType.values
          .map(
            (item) => DropdownMenuItem<BusinessType>(
              value: item,
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ConfigDropdownField extends StatelessWidget {
  const _ConfigDropdownField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final IconData icon;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: Colors.white.withValues(alpha: 0.7),
      ),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      dropdownColor: AppColors.primaryDark,
      decoration: _fieldDecoration(
        label: label,
        hint: hint,
        icon: icon,
      ),
      onChanged: onChanged,
      validator: validator,
      selectedItemBuilder: (context) => items
          .map(
            (item) => Text(
              item,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
          .toList(),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
    );
  }
}

InputDecoration _fieldDecoration({
  required String label,
  required String hint,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontWeight: FontWeight.w600,
    ),
    hintStyle: TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: Icon(icon, color: AppColors.secondary),
    filled: true,
    fillColor: AppColors.primaryDark.withValues(alpha: 0.6),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: Colors.white.withValues(alpha: 0.12),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: Colors.white.withValues(alpha: 0.12),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.red, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.red, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
  );
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.loadingLabel,
    required this.loadingHint,
    required this.isLoading,
    required this.pulseOn,
    required this.onPressed,
  });

  final String label;
  final String loadingLabel;
  final String loadingHint;
  final bool isLoading;
  final bool pulseOn;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: isLoading ? 1.02 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.goldGradient,
          borderRadius: BorderRadius.circular(isLoading ? 24 : 18),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(
                alpha: isLoading ? (pulseOn ? 0.55 : 0.35) : 0.35,
              ),
              blurRadius: isLoading ? (pulseOn ? 22 : 14) : 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(isLoading ? 24 : 18),
          child: InkWell(
            borderRadius: BorderRadius.circular(isLoading ? 24 : 18),
            onTap: isLoading ? null : onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isLoading ? 16 : 20,
                vertical: isLoading ? 14 : 18,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isLoading
                    ? _LoadingButtonContent(
                        key: const ValueKey('loading-content'),
                        title: loadingLabel,
                        subtitle: loadingHint,
                      )
                    : Row(
                        key: const ValueKey('idle-content'),
                        children: [
                          const SizedBox(width: 22, height: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primaryDarker,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.primaryDarker,
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

class _LoadingButtonContent extends StatelessWidget {
  const _LoadingButtonContent({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppColors.primaryDarker,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.primaryDarker,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.primaryDarker,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay({
    required this.steps,
    required this.activeStepIndex,
  });

  final List<String> steps;
  final int activeStepIndex;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            color: Colors.black.withValues(alpha: 0.22),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom: i == steps.length - 1 ? 0 : 8),
                          child: _ProgressStepItem(
                            label: steps[i],
                            isDone: i < activeStepIndex,
                            isActive: i == activeStepIndex,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.cloud_done_rounded,
                            size: 15,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Dados protegidos localmente e sincronizados quando houver internet.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 11,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
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
          ),
        ),
      ),
    );
  }
}

class _ProgressStepItem extends StatelessWidget {
  const _ProgressStepItem({
    required this.label,
    required this.isDone,
    required this.isActive,
  });

  final String label;
  final bool isDone;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isDone
        ? AppColors.secondary
        : isActive
            ? Colors.white
            : Colors.white.withValues(alpha: 0.45);
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: isDone
              ? const Icon(Icons.check_circle_rounded,
                  color: AppColors.secondary, size: 18)
              : isActive
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    )
                  : Icon(
                      Icons.radio_button_unchecked_rounded,
                      color: Colors.white.withValues(alpha: 0.35),
                      size: 16,
                    ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight:
                  isDone || isActive ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _SetupSuccessView extends StatefulWidget {
  const _SetupSuccessView({
    super.key,
    required this.onPrimaryCta,
    required this.onSecondaryCta,
  });

  final VoidCallback onPrimaryCta;
  final VoidCallback onSecondaryCta;

  @override
  State<_SetupSuccessView> createState() => _SetupSuccessViewState();
}

class _SetupSuccessViewState extends State<_SetupSuccessView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _checkScale;
  late final Animation<double> _confettiBurst;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    HapticFeedback.selectionClick();
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 220),
        HapticFeedback.lightImpact,
      ),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scale = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _checkScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.72, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.18, 0.72, curve: Curves.easeOut),
      ),
    );
    _confettiBurst = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.08, 0.68, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _GoldParticles(animation: _controller),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 128,
                              height: 128,
                              child: _ConfettiBurst(animation: _confettiBurst),
                            ),
                            ScaleTransition(
                              scale: _checkScale,
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.2,
                                  ),
                                  border: Border.all(
                                    color: AppColors.secondary,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.secondary.withValues(
                                        alpha: 0.28,
                                      ),
                                      blurRadius: 20,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 52,
                                  color: AppColors.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Conta pronta para vender',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tudo configurado. Pode registar a primeira venda agora e ativar o ciclo de clientes recorrentes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.shield_moon_rounded,
                                size: 16,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Modo fiavel: funciona offline e sincroniza automaticamente.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        _PrimaryActionButton(
                          label: 'Registar primeira venda',
                          loadingLabel: 'A abrir vendas',
                          loadingHint: 'Preparando o fluxo inicial',
                          isLoading: false,
                          pulseOn: false,
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            widget.onPrimaryCta();
                          },
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            widget.onSecondaryCta();
                          },
                          icon: const Icon(Icons.dashboard_customize_rounded),
                          label: const Text('Ver dashboard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
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
}

class _GoldParticles extends StatelessWidget {
  const _GoldParticles({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => CustomPaint(
        painter: _GoldParticlesPainter(progress: animation.value),
      ),
    );
  }
}

class _ConfettiBurst extends StatelessWidget {
  const _ConfettiBurst({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => CustomPaint(
        painter: _ConfettiBurstPainter(progress: animation.value),
      ),
    );
  }
}

class _ConfettiBurstPainter extends CustomPainter {
  _ConfettiBurstPainter({required this.progress});

  final double progress;

  static const _angles = [
    0.0,
    0.42,
    0.88,
    1.32,
    1.76,
    2.2,
    2.64,
    3.08,
    3.52,
    3.96,
    4.4,
    4.84,
    5.28,
    5.72,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final outward = Curves.easeOut.transform(progress);
    final fadeOut = (1 - progress).clamp(0.0, 1.0);

    for (var i = 0; i < _angles.length; i++) {
      final angle = _angles[i];
      final distance = 24 + ((i % 3) * 7) + (outward * 22);
      final dx = center.dx + distance * math.cos(angle);
      final dy = center.dy + distance * math.sin(angle);
      final isGold = i.isEven;
      final color = isGold
          ? AppColors.secondary
          : AppColors.green.withValues(alpha: 0.95);

      final dotPaint = Paint()..color = color.withValues(alpha: 0.75 * fadeOut);
      canvas.drawCircle(Offset(dx, dy), isGold ? 2.4 : 1.8, dotPaint);

      final tickPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45 * fadeOut)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final start = Offset(
        center.dx + (distance - 8) * math.cos(angle),
        center.dy + (distance - 8) * math.sin(angle),
      );
      final end = Offset(
        center.dx + (distance - 2) * math.cos(angle),
        center.dy + (distance - 2) * math.sin(angle),
      );
      canvas.drawLine(start, end, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiBurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _GoldParticlesPainter extends CustomPainter {
  _GoldParticlesPainter({required this.progress});

  final double progress;

  static const _points = [
    Offset(0.15, 0.18),
    Offset(0.28, 0.12),
    Offset(0.82, 0.14),
    Offset(0.72, 0.2),
    Offset(0.12, 0.34),
    Offset(0.88, 0.36),
    Offset(0.22, 0.52),
    Offset(0.78, 0.58),
    Offset(0.1, 0.72),
    Offset(0.9, 0.68),
    Offset(0.3, 0.84),
    Offset(0.68, 0.86),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOut.transform(progress);
    for (var i = 0; i < _points.length; i++) {
      final point = _points[i];
      final dx = point.dx * size.width;
      final wave = math.sin((progress * 6.0) + i) * 2.2;
      final dy =
          point.dy * size.height - ((1 - eased) * 24 * ((i % 3) + 1)) + wave;
      final baseOpacity = 0.12 + ((i % 4) * 0.06);
      final color = i.isEven
          ? AppColors.secondary
          : AppColors.green.withValues(alpha: 0.95);
      final paint = Paint()
        ..color = color.withValues(alpha: baseOpacity * eased);
      canvas.drawCircle(Offset(dx, dy), 2.2 + (i % 3).toDouble(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
