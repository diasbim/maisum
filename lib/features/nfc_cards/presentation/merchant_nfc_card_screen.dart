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
import '../../customers/domain/customer.dart';
import '../../rewards/presentation/redeem_reward_screen.dart';
import '../../sales/presentation/new_sale_screen.dart';
import '../domain/nfc_card_reader.dart';

/// Business owner screen: taps a physical NFC card to identify the
/// associated customer (mirrors [MerchantCustomerQrResolveScreen] for QR),
/// then offers to register a sale or attribute a benefit for them.
class MerchantNfcCardScreen extends ConsumerStatefulWidget {
  const MerchantNfcCardScreen({super.key, NfcCardReader? reader})
      : _injectedReader = reader;

  final NfcCardReader? _injectedReader;

  @override
  ConsumerState<MerchantNfcCardScreen> createState() =>
      _MerchantNfcCardScreenState();
}

class _MerchantNfcCardScreenState extends ConsumerState<MerchantNfcCardScreen> {
  late final NfcCardReader _reader = widget._injectedReader ?? NfcCardReader();
  bool _reading = false;
  bool _customerCreated = false;
  String? _error;
  Customer? _resolvedCustomer;

  @override
  void dispose() {
    unawaited(_reader.cancel());
    super.dispose();
  }

  Future<void> _readAndResolve() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _error = null;
      _resolvedCustomer = null;
      _customerCreated = false;
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
      final result = await ref
          .read(customerAppApiProvider)
          .resolveMerchantNfcCard(token, cardUid: read.cardUid);
      final customerJson =
          (result['customer'] as Map?)?.cast<String, dynamic>();
      final customerId = customerJson?['customer_id'] as String?;
      if (customerJson == null || customerId == null) {
        throw StateError('Cliente não encontrado para este cartão.');
      }
      final customer = await ref
          .read(customerRepositoryProvider)
          .upsertCustomerFromNfcResolve(
            customerId: customerId,
            name: customerJson['name'] as String?,
            phone: customerJson['phone'] as String?,
            totalPoints: (customerJson['total_points'] as num?)?.toInt() ?? 0,
            cardUid: read.cardUid,
          );
      if (!mounted) return;
      setState(() {
        _resolvedCustomer = customer;
        _customerCreated = result['customer_created'] == true;
      });
    } on NfcCardReaderException catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeReaderError(error));
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'merchant_nfc_resolve');
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

  void _registerSale(Customer customer) {
    context.push(
      '/new-sale',
      extra: NewSaleArgs(preselectedCustomerId: customer.id),
    );
  }

  void _attributeBenefit(Customer customer) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RedeemRewardSheet(customer: customer),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = _resolvedCustomer;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ler cartão do cliente'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.link),
            tooltip: 'Associar cartão a um cliente',
            onPressed: () => context.push('/merchant/customer-nfc/link'),
          ),
        ],
      ),
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
                        'Aproxime o cartão NFC do cliente do telemóvel '
                        'para identificar a conta e registar vendas ou '
                        'atribuir benefícios.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      MaisUmButton(
                        label: _reading ? 'A ler cartão...' : 'Ler cartão',
                        leadingIcon: LucideIcons.nfc,
                        isLoading: _reading,
                        onPressed: _reading ? null : _readAndResolve,
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  MaisUmSurface(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
                if (customer != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  MaisUmSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_customerCreated)
                          const Padding(
                            padding: EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Text(
                              'Novo cliente registado a partir deste cartão.',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        Text(
                          customer.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(customer.phone),
                        const SizedBox(height: AppSpacing.xs),
                        Text('${customer.totalPoints} pontos'),
                        const SizedBox(height: AppSpacing.md),
                        MaisUmButton(
                          label: 'Registar venda',
                          leadingIcon: LucideIcons.receipt,
                          onPressed: () => _registerSale(customer),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        MaisUmButton(
                          label: 'Atribuir benefício',
                          leadingIcon: LucideIcons.gift,
                          variant: MaisUmButtonVariant.outlined,
                          onPressed: () => _attributeBenefit(customer),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
