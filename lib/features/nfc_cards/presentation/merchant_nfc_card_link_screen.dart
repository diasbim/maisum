import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_layout.dart';
import '../../../design_system/components/maisum_button.dart';
import '../../../design_system/components/maisum_surface.dart';
import '../domain/nfc_card_reader.dart';

/// Business owner screen: staff-assisted association of a physical NFC
/// card to a customer (existing or new), for customers who do not have
/// the customer app installed. Mirrors the self-service flow available in
/// the customer app (see CustomerNfcCardScreen), but authorized as the
/// merchant instead of the customer.
class MerchantNfcCardLinkScreen extends ConsumerStatefulWidget {
  const MerchantNfcCardLinkScreen({super.key, NfcCardReader? reader})
      : _injectedReader = reader;

  final NfcCardReader? _injectedReader;

  @override
  ConsumerState<MerchantNfcCardLinkScreen> createState() =>
      _MerchantNfcCardLinkScreenState();
}

class _MerchantNfcCardLinkScreenState
    extends ConsumerState<MerchantNfcCardLinkScreen> {
  late final NfcCardReader _reader = widget._injectedReader ?? NfcCardReader();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  bool _reading = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    unawaited(_reader.cancel());
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _readAndLink() async {
    if (_reading) return;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Introduza o número de telefone do cliente.');
      return;
    }
    setState(() {
      _reading = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final read = await _reader.readOnce(
        alertMessageIos: 'Aproxime o cartão do cliente do telemóvel.',
      );
      final token = await ref
          .read(firebaseAuthInstanceProvider)
          .currentUser
          ?.getIdToken();
      if (token == null || token.isEmpty) {
        throw StateError('Sessão indisponível.');
      }
      final name = _nameController.text.trim();
      final result = await ref.read(customerAppApiProvider).linkMerchantNfcCard(
            token,
            cardUid: read.cardUid,
            phone: phone,
            customerName: name.isEmpty ? null : name,
          );
      if (!mounted) return;
      final created = result['customer_created'] == true;
      setState(() {
        _successMessage = created
            ? 'Cartão associado a um novo cliente.'
            : 'Cartão associado ao cliente existente.';
      });
    } on NfcCardReaderException catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeReaderError(error));
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'merchant_nfc_link');
      if (mounted) {
        setState(() => _error = AppErrorMapper.describe(error).message);
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  String _describeReaderError(NfcCardReaderException error) =>
      switch (error.reason) {
        NfcCardReaderErrorReason.unsupported =>
          'Este dispositivo não suporta leitura de cartões NFC.',
        NfcCardReaderErrorReason.disabled =>
          'Ative o NFC nas definições do dispositivo e tente novamente.',
        NfcCardReaderErrorReason.timeout =>
          'Tempo esgotado. Aproxime o cartão do telemóvel e tente novamente.',
        NfcCardReaderErrorReason.cancelled => 'Leitura cancelada.',
        NfcCardReaderErrorReason.unreadableTag =>
          'Não foi possível ler este cartão.',
        NfcCardReaderErrorReason.sessionError =>
          'Ocorreu um erro na leitura. Tente novamente.',
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Associar cartão a um cliente')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.contentMaxWidth,
              ),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  MaisUmSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Indique o telefone do cliente (obrigatório) e, '
                          'se for um cliente novo, o nome. Depois aproxime '
                          'o cartão físico do telemóvel para o associar — '
                          'tanto para clientes já existentes como para '
                          'clientes ainda sem conta.',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Telefone do cliente',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nome (apenas para clientes novos)',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        MaisUmButton(
                          label: _reading
                              ? 'A ler cartão...'
                              : 'Ler cartão e associar',
                          leadingIcon: LucideIcons.nfc,
                          isLoading: _reading,
                          onPressed: _reading ? null : _readAndLink,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    MaisUmSurface(
                      variant: MaisUmSurfaceVariant.error,
                      child: Text(_error!),
                    ),
                  ],
                  if (_successMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    MaisUmSurface(
                      variant: MaisUmSurfaceVariant.success,
                      child: Text(_successMessage!),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  MaisUmButton(
                    label: 'Concluir',
                    variant: MaisUmButtonVariant.ghost,
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
