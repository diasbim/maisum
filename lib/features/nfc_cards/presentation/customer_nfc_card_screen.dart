import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_layout.dart';
import '../../../design_system/components/maisum_button.dart';
import '../../../design_system/components/maisum_surface.dart';
import '../domain/nfc_card_reader.dart';

/// Customer app screen: self-service association (and revocation) of a
/// physical NFC card to the signed-in customer's own account. Mirrors the
/// staff-assisted flow available in the business owner app
/// (MerchantNfcCardLinkScreen), but authorized as the customer.
class CustomerNfcCardScreen extends ConsumerStatefulWidget {
  const CustomerNfcCardScreen({super.key, NfcCardReader? reader})
      : _injectedReader = reader;

  final NfcCardReader? _injectedReader;

  @override
  ConsumerState<CustomerNfcCardScreen> createState() =>
      _CustomerNfcCardScreenState();
}

class _CustomerNfcCardScreenState extends ConsumerState<CustomerNfcCardScreen> {
  late final NfcCardReader _reader = widget._injectedReader ?? NfcCardReader();
  bool _busy = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    unawaited(_reader.cancel());
    super.dispose();
  }

  Future<void> _readAndRun(
    Future<Map<String, dynamic>> Function(String cardUid) action,
    String successMessage,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final read = await _reader.readOnce(
        alertMessageIos: 'Aproxime o seu cartão do telemóvel.',
      );
      await action(read.cardUid);
      if (!mounted) return;
      setState(() => _successMessage = successMessage);
    } on NfcCardReaderException catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeReaderError(error));
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'customer_nfc_card');
      if (mounted) {
        setState(() => _error = AppErrorMapper.describe(error).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() => _readAndRun(
        (cardUid) =>
            ref.read(customerAppRepositoryProvider).linkNfcCard(cardUid),
        'Cartão associado à sua conta com sucesso.',
      );

  Future<void> _revoke() => _readAndRun(
        (cardUid) =>
            ref.read(customerAppRepositoryProvider).revokeNfcCard(cardUid),
        'Cartão desassociado da sua conta.',
      );

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
        appBar: AppBar(title: const Text('Cartão físico')),
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
                          'Associe um cartão físico com tecnologia NFC à '
                          'sua conta para ganhar pontos e resgatar '
                          'benefícios em qualquer negócio MaisUm sem '
                          'precisar de mostrar o telemóvel.',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        MaisUmButton(
                          label: _busy ? 'A ler cartão...' : 'Associar cartão',
                          leadingIcon: LucideIcons.nfc,
                          isLoading: _busy,
                          onPressed: _busy ? null : _link,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        MaisUmButton(
                          label: 'Desassociar este cartão',
                          variant: MaisUmButtonVariant.outlined,
                          onPressed: _busy ? null : _revoke,
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
                ],
              ),
            ),
          ),
        ),
      );
}
