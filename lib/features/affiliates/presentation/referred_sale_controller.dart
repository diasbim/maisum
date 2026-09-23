import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../customers/presentation/customers_controller.dart';
import '../../sales/domain/sale_item.dart';
import '../../sales/presentation/sale_controller.dart';
import '../domain/offline_referral.dart';
import '../domain/referral_sale_commit.dart';
import '../providers/affiliate_providers.dart';
import '../services/referral_copy.dart';

/// What came of trying to commit a sale with a code.
///
/// A refusal is a result, not an exception, because the sale itself is still
/// good: the cashier is one tap from finishing it without the code, and losing
/// the typed amount to an error screen would be the worse outcome by far.
sealed class ReferredSaleOutcome {
  const ReferredSaleOutcome();
}

/// The server wrote the sale. [result] is its canonical projection.
class ReferredSaleAccepted extends ReferredSaleOutcome {
  const ReferredSaleAccepted(this.result, this.commit);

  final SaleResult result;
  final ReferralSaleCommit commit;
}

/// The code could not be used. The sale was not written.
class ReferredSaleRejected extends ReferredSaleOutcome {
  const ReferredSaleRejected(this.message);

  final String message;
}

/// This device cannot commit a referred sale at all.
///
/// Distinct from a refusal on purpose: nothing was attempted, and retrying will
/// not help until the device is linked, so the message has to say that rather
/// than blame the code.
class ReferredSaleDeviceUnavailable extends ReferredSaleOutcome {
  const ReferredSaleDeviceUnavailable(this.message);

  final String message;
}

/// The sale was written here and the referral queued for the server to judge.
///
/// [benefitApplied] says whether money actually came off the bill. When it did,
/// it came off from a cached code and the discount is already the customer's;
/// when it did not, the sale was charged in full and the typed code is carried
/// up as an intention. Either way nothing is confirmed, which is why the screen
/// that shows this has to say "pendente de confirmação" rather than name an
/// affiliate as credited.
class ReferredSaleQueuedOffline extends ReferredSaleOutcome {
  const ReferredSaleQueuedOffline(this.result, this.decision);

  final SaleResult result;
  final OfflineReferralDecision decision;

  bool get benefitApplied => decision.appliesBenefit;

  bool get codeWasKnown => decision.isKnownCode;
}

/// Commits a sale that carries a referral code.
///
/// Deliberately separate from `SaleController`: a sale without a code still
/// goes through that controller, that repository and that queue, untouched, and
/// keeping the two apart is what guarantees the ordinary path cannot regress
/// when the referral path changes.
class ReferredSaleController extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  /// The till's id for this sale, minted once.
  ///
  /// It is half of the idempotency key, so it must survive a retry: if a second
  /// attempt invented a new id after a dropped response, the server would write
  /// the same sale twice and pay the affiliate twice for it.
  String newLocalSaleId() => _uuid.v4();

  /// Writes a referred sale with no server in reach.
  ///
  /// The sale is final locally and the referral is not: one row, one queued
  /// authoritative operation, and a benefit applied only when the code was in
  /// this device's cache and passed every check the device can make. Nothing
  /// here claims the affiliate has been credited, because nothing here can
  /// know that.
  Future<ReferredSaleOutcome> commitOffline({
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    required String localSaleId,
    List<SaleItemInput> items = const <SaleItemInput>[],
  }) async {
    final repository = ref.read(affiliateOfflineGatewayProvider);
    if (repository == null) {
      return const ReferredSaleDeviceUnavailable(
        'Este dispositivo ainda não está identificado. '
        'Ligue-o ao negócio para registar vendas com código.',
      );
    }

    state = const AsyncLoading();
    try {
      final result = await repository.recordOfflineReferralSale(
        customerId: customerId,
        customerPhone: customerPhone,
        grossAmount: grossAmount,
        code: normalizeReferralCodeInput(code),
        localSaleId: localSaleId,
        items: items,
      );

      ref.invalidate(customerDetailProvider(customerId));
      ref.invalidate(customerSalesProvider(customerId));
      ref.invalidate(allSalesWithCustomerProvider);

      state = const AsyncData(null);
      return ReferredSaleQueuedOffline(
        SaleResult(sale: result.sale, customer: result.customer),
        result.decision,
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<ReferredSaleOutcome> commit({
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    required String localSaleId,
    List<SaleItemInput> items = const <SaleItemInput>[],
  }) async {
    final repository = ref.read(affiliateSaleRepositoryProvider);
    if (repository == null) {
      return const ReferredSaleDeviceUnavailable(
        'Este dispositivo ainda não está identificado. '
        'Ligue-o ao negócio para registar vendas com código.',
      );
    }

    state = const AsyncLoading();
    try {
      final commit = await repository.commitReferredSale(
        customerId: customerId,
        customerPhone: customerPhone,
        grossAmount: grossAmount,
        code: normalizeReferralCodeInput(code),
        localSaleId: localSaleId,
        items: items,
      );

      final sale = commit.sale;
      if (!commit.isAccepted || sale == null) {
        state = const AsyncData(null);
        return ReferredSaleRejected(
          commit.message?.trim().isNotEmpty == true
              ? commit.message!.trim()
              : referralErrorMessage(commit.errorCode),
        );
      }

      final customer =
          await ref.read(customerRepositoryProvider).getById(customerId);
      if (customer == null) {
        throw StateError('Customer not found after referred sale commit');
      }

      ref.invalidate(customerDetailProvider(customerId));
      ref.invalidate(customerSalesProvider(customerId));
      ref.invalidate(allSalesWithCustomerProvider);
      ref.read(syncServiceProvider).processQueue();

      state = const AsyncData(null);
      return ReferredSaleAccepted(
        SaleResult(sale: sale, customer: customer),
        commit,
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final referredSaleControllerProvider =
    AsyncNotifierProvider<ReferredSaleController, void>(
  ReferredSaleController.new,
);
