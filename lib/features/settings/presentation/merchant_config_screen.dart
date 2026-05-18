import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../auth/presentation/auth_controller.dart';

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

  String? _selectedCity;
  String? _selectedBusinessType;
  bool _isLoading = true;
  bool _isSaving = false;

  static const _cities = [
    'Maputo',
    'Matola',
    'Beira',
    'Nampula',
    'Chimoio',
    'Outra',
  ];

  static const _businessTypes = [
    'Barbearia',
    'Cabeleireiro',
    'Estetica',
    'Spa',
    'Outro',
  ];

  @override
  void initState() {
    super.initState();
    _primeFields();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _primeFields() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    _nameController.text = session?.merchantName ?? '';
    _phoneController.text = session?.phone ?? '';

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
          _selectedCity = city;
          _selectedBusinessType = businessType;
        }
      } catch (e, st) {
        // Keep local defaults when remote data is not reachable.
        AppErrorReporter.report(e, st, hint: 'merchant_config_fetch');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final merchantId = ref.read(activeMerchantIdProvider);
    if (merchantId == null || merchantId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessao invalida.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final city = _selectedCity ?? '';
    final businessType = _selectedBusinessType ?? '';

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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuracao guardada.')),
      );
      context.pop();
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'merchant_config_save');
      if (!mounted) return;
      final info = AppErrorMapper.describe(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(info.message)),
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
                  builder: (context, constraints) => SingleChildScrollView(
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
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const TextSpan(
                                  text: 'barbearia',
                                  style: TextStyle(color: AppColors.secondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Em poucos passos o MaisUm estara pronto para trazer\nclientes de volta.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
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
                                  hint: 'Ex.: Barbearia Top Look',
                                  icon: Icons.storefront_rounded,
                                  textInputAction: TextInputAction.next,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
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
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Introduza o telefone';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                _ConfigDropdownField(
                                  label: 'Cidade',
                                  hint: 'Ex.: Maputo',
                                  icon: Icons.place_rounded,
                                  value: _selectedCity,
                                  items: _cities,
                                  onChanged: (value) {
                                    setState(() => _selectedCity = value);
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Selecione a cidade';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                _ConfigDropdownField(
                                  label: 'Tipo de negocio',
                                  hint: 'Selecione o tipo de negocio',
                                  icon: Icons.content_cut_rounded,
                                  value: _selectedBusinessType,
                                  items: _businessTypes,
                                  onChanged: (value) {
                                    setState(
                                        () => _selectedBusinessType = value);
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Selecione o tipo de negocio';
                                    }
                                    return null;
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
                                color: Colors.white.withValues(alpha: 0.5),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pode atualizar estas informacoes mais tarde nas definicoes.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          _PrimaryActionButton(
                            label: 'Continuar',
                            isLoading: _isSaving,
                            onPressed: _isSaving ? null : _save,
                          ),
                        ],
                      ),
                    ),
                  ),
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
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        const Spacer(),
        Row(
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
        ),
        const Spacer(),
        const SizedBox(width: 40),
      ],
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
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
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

class _ConfigDropdownField extends StatelessWidget {
  const _ConfigDropdownField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
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
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
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
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppTheme.goldGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isLoading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: isLoading
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryDarker,
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.primaryDarker,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
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
    );
  }
}
