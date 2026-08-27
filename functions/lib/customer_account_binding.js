"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.findCustomerAccountBindingConflict = findCustomerAccountBindingConflict;
exports.applyCustomerAccountBinding = applyCustomerAccountBinding;
function findCustomerAccountBindingConflict(input) {
    if (input.existingAccountCanonicalCustomerId != null &&
        input.existingAccountCanonicalCustomerId !== input.canonicalCustomerId) {
        return 'account_identity_mismatch';
    }
    if (input.existingIdentityFirebaseUid != null &&
        input.existingIdentityFirebaseUid !== input.firebaseUid) {
        return 'identity_account_mismatch';
    }
    return null;
}
/**
 * Mirrors the state transition performed inside the Firestore transaction.
 * It keeps the transaction's conflict behavior deterministically testable
 * when an emulator is not configured.
 */
function applyCustomerAccountBinding(input) {
    const conflict = findCustomerAccountBindingConflict(input);
    if (conflict) {
        throw new Error(conflict);
    }
    return {
        accountCanonicalCustomerId: input.canonicalCustomerId,
        identityFirebaseUid: input.firebaseUid,
    };
}
