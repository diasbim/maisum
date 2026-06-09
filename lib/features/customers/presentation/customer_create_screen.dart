import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/moz_phone_input_formatter.dart';
import '../../../core/utils/moz_phone_validator.dart';
import '../../../design_system/components/loading_button.dart';
import '../../../design_system/components/maisum_modal.dart';
import '../../../design_system/components/maisum_text_field.dart';
import '../../../design_system/components/maisum_toast.dart';
import '../../../design_system/components/validation_state.dart';
import '../../sales/presentation/new_sale_screen.dart';
import 'customers_controller.dart';

class CustomerCreateScreen extends ConsumerStatefulWidget {
  const CustomerCreateScreen({
    super.key,
    this.returnRoute,
    this.resumeSaleFlow = false,
  });

  final String? returnRoute;
  final bool resumeSaleFlow;

  @override
  ConsumerState<CustomerCreateScreen> createState() =>
      _CustomerCreateScreenState();
}

class _CustomerCreateScreenState extends ConsumerState<CustomerCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();

  bool _isSaving = false;
  bool _hasSubmitted = false;
  ValidationState _nameState = ValidationState.neutral;
  ValidationState _phoneState = ValidationState.neutral;

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(_onNameFocusChanged);
    _phoneFocusNode.addListener(_onPhoneFocusChanged);
  }

  @override
  void dispose() {
    _nameFocusNode
      ..removeListener(_onNameFocusChanged)
      ..dispose();
    _phoneFocusNode
      ..removeListener(_onPhoneFocusChanged)
      ..dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onNameFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (_nameFocusNode.hasFocus) {
        _nameState = ValidationState.focused;
        return;
      }

      final hasName = _nameController.text.trim().isNotEmpty;
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

  void _onPhoneFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (_phoneFocusNode.hasFocus) {
        _phoneState = ValidationState.focused;
        return;
      }

      final hasPhone = _phoneController.text.trim().isNotEmpty;
      if (!_hasSubmitted && !hasPhone) {
        _phoneState = ValidationState.neutral;
        return;
      }
      _phoneState = MozPhoneValidator.isValidLocalPhone(_phoneController.text)
          ? ValidationState.valid
          : ValidationState.invalid;
    });
    if (!_phoneFocusNode.hasFocus) {
      _formKey.currentState?.validate();
    }
  }

  String? _nameValidator(String? value) {
    if (!_hasSubmitted && _nameFocusNode.hasFocus) {
      return null;
    }
    if (value == null || value.trim().isEmpty) {
      return AppStrings.nameRequired;
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    if (!_hasSubmitted && _phoneFocusNode.hasFocus) {
      return null;
    }
    return MozPhoneValidator.validationMessage(value);
  }

  Future<void> _save() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();
    if (!_hasSubmitted) {
      setState(() => _hasSubmitted = true);
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      setState(() {
        _nameState = _nameController.text.trim().isEmpty
            ? ValidationState.invalid
            : ValidationState.valid;
        _phoneState = MozPhoneValidator.isValidLocalPhone(_phoneController.text)
            ? ValidationState.valid
            : ValidationState.invalid;
      });
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() => _isSaving = true);

    try {
      final customer = await ref
          .read(customersControllerProvider.notifier)
          .createCustomer(name: name, phone: phone);

      if (!mounted) return;

      if (widget.resumeSaleFlow) {
        try {
          final analytics = ref.read(analyticsServiceProvider);
          unawaited(
            analytics.record(
              eventType: 'customer_created_from_sale_flow',
              source: 'customer_create',
              properties: {'customer_id': customer.id},
            ).catchError((_) {}),
          );
          unawaited(
            analytics.record(
              eventType: 'sale_flow_resumed',
              source: 'customer_create',
              properties: {'customer_id': customer.id},
            ).catchError((_) {}),
          );
        } catch (_) {
          // Analytics is best-effort and must not block sale resume.
        }

        context.go(
          '/new-sale',
          extra: NewSaleArgs(preselectedCustomerId: customer.id),
        );
        return;
      }

      MaisUmToast.show(
        context,
        message: AppStrings.customerCreatedSuccess,
        type: MaisUmToastType.success,
      );

      final destination = widget.returnRoute;
      if (destination != null && destination.isNotEmpty) {
        context.go(destination);
        return;
      }

      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/customers');
      }
    } catch (e) {
      if (!mounted) return;
      final info = AppErrorMapper.describe(e);

      if (info.message == AppStrings.customerPhoneDuplicate) {
        final existing =
            await ref.read(customerRepositoryProvider).findByPhone(phone);
        if (!mounted) return;
        if (existing != null) {
          final openProfile = await MaisUmModal.confirm(
            context: context,
            title: 'Cliente ja existe',
            message: 'Este numero ja esta registado.\n\nDeseja abrir o perfil?',
            primaryLabel: 'Ver Cliente',
            secondaryLabel: 'Cancelar',
          );
          if (openProfile == true && mounted) {
            await context.push('/customers/${existing.id}');
          }
          return;
        }
      }

      MaisUmToast.show(
        context,
        message: info.message,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar Cliente'),
        backgroundColor: AppColors.offWhite,
      ),
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preencha os dados para criar o cliente.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                MaisUmTextField(
                  label: AppStrings.nome,
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  hintText: AppStrings.nomeHint,
                  validator: _nameValidator,
                  validationState: _nameState,
                  showValidIcon: true,
                  onChanged: (_) {
                    if (_hasSubmitted && !_nameFocusNode.hasFocus) {
                      setState(() {
                        _nameState = _nameController.text.trim().isEmpty
                            ? ValidationState.invalid
                            : ValidationState.valid;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                MaisUmTextField(
                  label: AppStrings.phoneNumber,
                  controller: _phoneController,
                  focusNode: _phoneFocusNode,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  hintText: '84 000 0000',
                  validator: _phoneValidator,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                    MozPhoneFormatter(),
                  ],
                  validationState: _phoneState,
                  showValidIcon: true,
                  onChanged: (_) {
                    if (_hasSubmitted && !_phoneFocusNode.hasFocus) {
                      setState(() {
                        _phoneState = MozPhoneValidator.isValidLocalPhone(
                                _phoneController.text)
                            ? ValidationState.valid
                            : ValidationState.invalid;
                      });
                    }
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 20),
                LoadingButton(
                  label: AppStrings.criarCliente,
                  loadingLabel: 'A criar cliente...',
                  onPressed: _save,
                  enabled: !_isSaving,
                  isLoading: _isSaving,
                  height: 56,
                  radius: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
