import * as admin from 'firebase-admin';

import { affiliateConfigFrom } from './affiliate_store.js';
import {
  commitOfflineReferralSale,
  type OfflineReferralSaleInput,
  type OfflineReferralSaleOutcome,
} from './affiliate_offline_sale.js';
import {
  commitReferralSale,
  recordReferredCustomerReturn,
  reverseReferralSale,
  type DocumentData,
  type ReferralSaleCommitInput,
  type ReferralSaleCommitOutcome,
  type ReferralSaleGateway,
  type ReferralSaleTransaction,
  type ReferredReturnOutcome,
  type ReferralReversalOutcome,
  type StoredDocument,
} from './affiliate_sale_commit.js';

/**
 * The referral sale commands, bound to Firestore.
 *
 * `affiliate_sale_commit.ts` decides; this file is the only thing that knows
 * the decision lands in Firestore. The split is not decoration: the commit is
 * one transaction with seven writes in it, and a test that needed an emulator
 * to check "either all of them or none" would not be run often enough to
 * matter. With the ports here, the decision is tested against a fake that can
 * fail halfway through on purpose.
 *
 * The adapter is deliberately thin. It translates a path to a reference and a
 * query to a `where`, and does nothing else — no defaults, no retries, no
 * field mapping — so there is nothing in it that can disagree with the plan.
 */

const db = () => admin.firestore();

function refFor(path: string): admin.firestore.DocumentReference {
  return db().doc(path);
}

function transactionPorts(
  transaction: admin.firestore.Transaction,
): ReferralSaleTransaction {
  return {
    async getDoc(path: string): Promise<DocumentData | null> {
      const snapshot = await transaction.get(refFor(path));
      return snapshot.exists ? ((snapshot.data() ?? {}) as DocumentData) : null;
    },
    async queryDocs(
      collectionPath: string,
      field: string,
      value: string,
      limit: number,
    ): Promise<StoredDocument[]> {
      const snapshot = await transaction.get(
        db().collection(collectionPath).where(field, '==', value).limit(limit),
      );
      return snapshot.docs.map((doc) => ({
        id: doc.id,
        data: (doc.data() ?? {}) as DocumentData,
      }));
    },
    create(path: string, data: DocumentData): void {
      transaction.create(refFor(path), data);
    },
    merge(path: string, data: DocumentData): void {
      transaction.set(refFor(path), data, { merge: true });
    },
  };
}

export const firestoreReferralSaleGateway: ReferralSaleGateway = {
  runTransaction<T>(run: (transaction: ReferralSaleTransaction) => Promise<T>): Promise<T> {
    return db().runTransaction((transaction) => run(transactionPorts(transaction)));
  },
};

/** The authoritative commit, as a route may call it. */
export async function commitReferralSaleToFirestore(
  input: ReferralSaleCommitInput,
): Promise<ReferralSaleCommitOutcome> {
  return commitReferralSale(firestoreReferralSaleGateway, input, (business) =>
    affiliateConfigFrom((business ?? {}) as DocumentData));
}

/**
 * The reconciliation of a sale a till already made offline.
 *
 * Shares the gateway, the facts and the validation with the online commit on
 * purpose: the only thing that differs is what may still be changed about a
 * sale that has already been paid for, and that difference lives in
 * `affiliate_offline_sale.ts` rather than in a second Firestore adapter.
 */
export async function commitOfflineReferralSaleToFirestore(
  input: OfflineReferralSaleInput,
): Promise<OfflineReferralSaleOutcome> {
  return commitOfflineReferralSale(firestoreReferralSaleGateway, input, (business) =>
    affiliateConfigFrom((business ?? {}) as DocumentData));
}

/** The reversal the sale-cancellation path calls once a sale is cancelled. */
export async function reverseReferralSaleInFirestore(input: {
  merchantId: string;
  saleId: string;
  cancelledAt: number;
  actorId: string;
}): Promise<ReferralReversalOutcome> {
  return reverseReferralSale(firestoreReferralSaleGateway, input);
}

/**
 * The return hook, called from the sale the business already processes.
 *
 * Reads the business settings outside the transaction on purpose: nothing
 * about a return is a race — the reward is keyed by attribution and type, so a
 * stale setting can at worst create a reward the merchant has since switched
 * off, which is a queued approval they can refuse.
 */
export async function recordReferredCustomerReturnInFirestore(input: {
  merchantId: string;
  saleId: string;
  customerId: string;
  amount: number;
  occurredAt: number;
}): Promise<ReferredReturnOutcome> {
  const business = await db().collection('businesses').doc(input.merchantId).get();
  const config = affiliateConfigFrom((business.data() ?? {}) as DocumentData);
  // Every sale in the product reaches this hook, and almost none of them
  // belong to a business that has affiliates at all. One document read is the
  // cheap way to stop; it also means a business that switches the feature off
  // stops accruing return rewards, which is what switching it off means.
  if (!config.enabled) {
    return { status: 'not_referred', reward_id: null };
  }
  return recordReferredCustomerReturn(firestoreReferralSaleGateway, input, config);
}
