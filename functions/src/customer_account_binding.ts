export type CustomerAccountBindingConflict =
  | 'account_identity_mismatch'
  | 'identity_account_mismatch';

type CustomerAccountBindingInput = {
  firebaseUid: string;
  canonicalCustomerId: string;
  existingAccountCanonicalCustomerId: string | null;
  existingIdentityFirebaseUid: string | null;
};

export type CustomerAccountBindingState = {
  accountCanonicalCustomerId: string | null;
  identityFirebaseUid: string | null;
};

export function findCustomerAccountBindingConflict(
  input: CustomerAccountBindingInput,
): CustomerAccountBindingConflict | null {
  if (
    input.existingAccountCanonicalCustomerId != null &&
    input.existingAccountCanonicalCustomerId !== input.canonicalCustomerId
  ) {
    return 'account_identity_mismatch';
  }
  if (
    input.existingIdentityFirebaseUid != null &&
    input.existingIdentityFirebaseUid !== input.firebaseUid
  ) {
    return 'identity_account_mismatch';
  }
  return null;
}

/**
 * Mirrors the state transition performed inside the Firestore transaction.
 * It keeps the transaction's conflict behavior deterministically testable
 * when an emulator is not configured.
 */
export function applyCustomerAccountBinding(
  input: CustomerAccountBindingInput,
): CustomerAccountBindingState {
  const conflict = findCustomerAccountBindingConflict(input);
  if (conflict) {
    throw new Error(conflict);
  }
  return {
    accountCanonicalCustomerId: input.canonicalCustomerId,
    identityFirebaseUid: input.firebaseUid,
  };
}
