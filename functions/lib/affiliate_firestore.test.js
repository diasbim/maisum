"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_firestore_js_1 = require("./affiliate_firestore.js");
const affiliate_engine_js_1 = require("./affiliate_engine.js");
const SOURCE = (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'affiliate_firestore.ts'), 'utf8');
/**
 * The claim path, tested through the seam that matters.
 *
 * `allocateAffiliateCode` takes `isTaken` rather than reading Firestore itself,
 * so the retry behaviour can be pinned here without an emulator — and so the
 * production caller can pass a *transactional* read, which is the only kind
 * that makes the claim safe. These tests are about the loop; the transaction
 * around it is asserted by reading the source in affiliate_routes.test.ts.
 */
/** Cycles bytes so the generated suffixes differ from attempt to attempt. */
function byteSource() {
    let n = 0;
    return () => (n++ * 37 + 11) % 256;
}
(0, node_test_1.default)('a free code is taken on the first attempt', async () => {
    const allocation = await (0, affiliate_firestore_js_1.allocateAffiliateCode)({
        name: 'João',
        isTaken: async () => false,
        randomByte: byteSource(),
    });
    (0, node_test_1.default)('production suffixes use cryptographic randomness, never the clock', () => {
        strict_1.default.match(SOURCE, /randomBytes\(1\)\.readUInt8\(0\)/);
        strict_1.default.doesNotMatch(SOURCE, /Timestamp\.now\(\)\.nanoseconds/);
    });
    strict_1.default.equal(allocation.attempts, 1);
    strict_1.default.match(allocation.code, /^AFI-JOAO-[A-Z0-9]{4}$/);
});
(0, node_test_1.default)('a collision is retried with a different suffix', async () => {
    const seen = [];
    const allocation = await (0, affiliate_firestore_js_1.allocateAffiliateCode)({
        name: 'Ana',
        randomByte: byteSource(),
        isTaken: async (candidate) => {
            seen.push(candidate);
            return seen.length < 3;
        },
    });
    strict_1.default.equal(allocation.attempts, 3);
    strict_1.default.equal(seen.length, 3);
    strict_1.default.equal(new Set(seen).size, 3, 'the same suffix was tried twice');
});
(0, node_test_1.default)('the name stays put across retries; only the suffix moves', async () => {
    const seen = [];
    await (0, affiliate_firestore_js_1.allocateAffiliateCode)({
        name: 'Amélia Cossa',
        randomByte: byteSource(),
        isTaken: async (candidate) => {
            seen.push(candidate);
            return seen.length < 4;
        },
    });
    for (const candidate of seen) {
        strict_1.default.match(candidate, /^AFI-AMELIA-[A-Z0-9]{4}$/, candidate);
    }
});
(0, node_test_1.default)('a full space fails loudly rather than widening the format', async () => {
    // Silently using five characters would produce a code the rest of the
    // product does not expect, in a place nobody would think to look.
    await strict_1.default.rejects((0, affiliate_firestore_js_1.allocateAffiliateCode)({
        name: 'Ana',
        randomByte: byteSource(),
        isTaken: async () => true,
        attempts: 3,
    }), (error) => {
        strict_1.default.ok(error instanceof affiliate_firestore_js_1.AffiliateCodeExhaustedError);
        strict_1.default.match(error.message, /3 attempts/);
        return true;
    });
});
(0, node_test_1.default)('it gives up after the configured number of tries, not more', async () => {
    let calls = 0;
    await strict_1.default.rejects((0, affiliate_firestore_js_1.allocateAffiliateCode)({
        name: 'Ana',
        randomByte: byteSource(),
        isTaken: async () => {
            calls++;
            return true;
        },
    }), affiliate_firestore_js_1.AffiliateCodeExhaustedError);
    strict_1.default.equal(calls, affiliate_firestore_js_1.CODE_ALLOCATION_ATTEMPTS);
});
(0, node_test_1.default)('the attempt budget is worth having', async () => {
    // One retry would make a single unlucky collision a user-visible failure;
    // a hundred would hammer Firestore inside a transaction.
    strict_1.default.ok(affiliate_firestore_js_1.CODE_ALLOCATION_ATTEMPTS >= 4, 'too few to absorb a collision');
    strict_1.default.ok(affiliate_firestore_js_1.CODE_ALLOCATION_ATTEMPTS <= 16, 'too many reads for one transaction');
});
(0, node_test_1.default)('every candidate offered is a code the product can store', async () => {
    const seen = [];
    await (0, affiliate_firestore_js_1.allocateAffiliateCode)({
        name: 'Guilhermina Nhamirre',
        randomByte: byteSource(),
        isTaken: async (candidate) => {
            seen.push(candidate);
            return seen.length < 5;
        },
    });
    for (const candidate of seen) {
        const suffix = candidate.split('-')[2];
        strict_1.default.equal(suffix.length, 4);
        for (const character of suffix) {
            strict_1.default.ok(affiliate_engine_js_1.CODE_ALPHABET.includes(character), `${character} is off-alphabet`);
        }
        // The name segment is capped at eight, so the whole code stays dictatable.
        strict_1.default.ok(candidate.length <= 4 + 8 + 5, candidate);
    }
});
