"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DECISION_MAKER_TITLES = exports.ProviderError = void 0;
exports.runChain = runChain;
exports.assertNoFabrication = assertNoFabrication;
exports.assertCompanySane = assertCompanySane;
exports.seniorityFromTitle = seniorityFromTitle;
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
/**
 * The boundary between this module and anything it pays for.
 *
 * Five interfaces, one internal model, and a fallback chain. Business logic
 * depends on the interfaces and never on a concrete provider — which is what
 * makes the whole pipeline runnable against fixtures, and what makes swapping
 * Apollo for something else a change to one file rather than to the routes.
 *
 * Three rules hold everywhere below.
 *
 * **Provider-shaped data never leaves an adapter.** Every field is mapped into
 * the types in this file before it is returned. A route that handed an Apollo
 * response to the UI would be shipping Apollo's schema as the product's, and
 * the next provider would break every screen.
 *
 * **Absent is null, never guessed.** No adapter may construct an email from a
 * name and a domain, infer an owner from a company name, or default an
 * employee count. This is the rule criterion 13 tests, and it is enforced here
 * rather than trusted: `assertNoFabrication` refuses a result whose email is
 * marked `VERIFIED` without the provider having said so.
 *
 * **Every failure is typed.** An adapter throws `ProviderError` with one of
 * seven codes, and the chain decides what each means. An adapter that let a
 * `fetch` rejection escape would take down a discovery job with a stack trace
 * instead of moving to the next provider.
 */
/* ------------------------------------------------------------------ errors */
class ProviderError extends Error {
    constructor(input) {
        super(`${input.provider}/${input.operation}: ${input.code}`);
        this.name = 'ProviderError';
        this.code = input.code;
        this.provider = input.provider;
        this.operation = input.operation;
        this.detail = input.detail ?? null;
    }
    /** True when another provider should be asked the same question. */
    get isFallbackWorthy() {
        return prospecting_contracts_js_1.FALLBACK_ERROR_CODES.includes(this.code);
    }
}
exports.ProviderError = ProviderError;
/**
 * Ask each provider in turn until one answers.
 *
 * The chain walks configured providers in the order `providerPriority` gives,
 * and stops at the first that answers. It stops *also* at the first
 * `NO_RESULT`: that is an answer, and asking the next provider would be paying
 * twice to hear it again. Fallback exists to route around breakage, not to
 * shop for a better reply — a chain that kept going until somebody said
 * something would eventually find a provider willing to guess, which is the
 * one outcome this module must not produce.
 *
 * A provider that is not configured is skipped without being called and
 * without a usage row, since nothing was spent.
 */
async function runChain(providers, call, options = {}) {
    const now = options.now ?? Date.now;
    const attempts = [];
    let lastCode = 'NOT_CONFIGURED';
    for (const provider of providers) {
        if (!provider.isConfigured())
            continue;
        const startedAt = now();
        try {
            const value = await call(provider);
            attempts.push({
                provider: provider.key,
                ok: true,
                code: null,
                durationMs: now() - startedAt,
            });
            return {
                ok: true,
                value,
                provider: provider.key,
                attempts,
                partial: attempts.length > 1,
            };
        }
        catch (error) {
            const code = error instanceof ProviderError ? error.code : 'UNAVAILABLE';
            attempts.push({
                provider: provider.key,
                ok: false,
                code,
                durationMs: now() - startedAt,
            });
            lastCode = code;
            // An answer, even an empty one, ends the chain.
            if (!prospecting_contracts_js_1.FALLBACK_ERROR_CODES.includes(code)) {
                return { ok: false, code, attempts };
            }
        }
    }
    return { ok: false, code: lastCode, attempts };
}
/* ------------------------------------------------------------- validation */
/**
 * Refuses a person record that claims more than the provider said.
 *
 * Adapters are the place fabrication would enter, and they are written by
 * whoever is integrating a provider under time pressure. So the check is here,
 * applied to every adapter's output by the caller, rather than being a rule in
 * a comment that each adapter is trusted to have followed.
 *
 * Two things are refused outright: an email marked `VERIFIED` that is not a
 * syntactically valid address, and a confidence score outside 0–1. Both are
 * signs the mapping is reading the wrong field, and both would otherwise
 * become a number an operator trusts.
 */
function assertNoFabrication(person, provider, operation) {
    const fail = (detail) => {
        throw new ProviderError({
            code: 'INVALID_SCHEMA',
            provider,
            operation,
            detail,
        });
    };
    if (person.email !== null && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(person.email)) {
        fail('email is not a valid address');
    }
    if (person.email === null && person.email_status === 'VERIFIED') {
        fail('email_status VERIFIED with no address');
    }
    if (person.confidence_score !== null &&
        (person.confidence_score < 0 || person.confidence_score > 1)) {
        fail('confidence_score outside 0-1');
    }
    return person;
}
/** The same, for a company. Refuses an employee count that cannot be one. */
function assertCompanySane(company, provider, operation) {
    if (company.name.trim() === '') {
        throw new ProviderError({
            code: 'INVALID_SCHEMA',
            provider,
            operation,
            detail: 'company has no name',
        });
    }
    if (company.employee_count !== null &&
        (!Number.isInteger(company.employee_count) || company.employee_count < 0)) {
        throw new ProviderError({
            code: 'INVALID_SCHEMA',
            provider,
            operation,
            detail: 'employee_count is not a whole number',
        });
    }
    // A rating outside 0–5 is a provider whose scale is not the one assumed, and
    // the scoring table compares it against a threshold without asking. Refusing
    // here is the difference between a loud bug and every lead in the campaign
    // quietly earning or losing five points for the wrong reason.
    if (company.rating !== null &&
        (!Number.isFinite(company.rating) || company.rating < 0 || company.rating > 5)) {
        throw new ProviderError({
            code: 'INVALID_SCHEMA',
            provider,
            operation,
            detail: 'rating is not on a 0-5 scale',
        });
    }
    if (company.review_count !== null &&
        (!Number.isInteger(company.review_count) || company.review_count < 0)) {
        throw new ProviderError({
            code: 'INVALID_SCHEMA',
            provider,
            operation,
            detail: 'review_count is not a whole number',
        });
    }
    // A coordinate off its scale is worse than a missing one: the distance test
    // would still answer, and it would answer "far apart" for two listings of
    // the same shop. Deduplication would then pay twice and report success.
    if (company.latitude !== null &&
        (!Number.isFinite(company.latitude) ||
            company.latitude < -90 ||
            company.latitude > 90)) {
        throw new ProviderError({
            code: 'INVALID_SCHEMA',
            provider,
            operation,
            detail: 'latitude is not a degree between -90 and 90',
        });
    }
    if (company.longitude !== null &&
        (!Number.isFinite(company.longitude) ||
            company.longitude < -180 ||
            company.longitude > 180)) {
        throw new ProviderError({
            code: 'INVALID_SCHEMA',
            provider,
            operation,
            detail: 'longitude is not a degree between -180 and 180',
        });
    }
    return company;
}
/* ------------------------------------------------------------- titles */
/**
 * Who to ask for, most likely to decide first.
 *
 * Bilingual because the businesses are Mozambican and the providers index
 * whatever the business wrote on LinkedIn, which is as often English as
 * Portuguese. Asking for only one language halves the hit rate on exactly the
 * leads worth having.
 */
exports.DECISION_MAKER_TITLES = [
    'owner',
    'proprietário',
    'proprietario',
    'founder',
    'fundador',
    'ceo',
    'managing director',
    'director geral',
    'diretor geral',
    'general manager',
    'gerente geral',
    'manager',
    'gerente',
];
/**
 * A job title mapped to the seniority the scorer reads.
 *
 * Returns `UNKNOWN` for anything unrecognised rather than guessing `STAFF`:
 * an unmapped title is a gap in this table, not a statement that the person is
 * junior, and treating it as one would quietly drop real owners whose title is
 * written in a way nobody anticipated.
 */
function seniorityFromTitle(title) {
    if (title === null)
        return 'UNKNOWN';
    const value = title
        .normalize('NFD')
        .replace(/\p{M}/gu, '')
        .toLowerCase();
    // The Portuguese stems carry a gendered ending, so the alternation spells
    // both out: `\bproprietari\b` can never match, because the character after
    // the stem is always a letter and the boundary never falls there.
    if (/\b(owner|proprietari[ao]|dono|dona|titular)\b/.test(value))
        return 'OWNER';
    if (/\b(founder|fundador[ao]?|cofounder|co-founder)\b/.test(value))
        return 'FOUNDER';
    if (/\b(ceo|cfo|coo|cto|chief)\b/.test(value))
        return 'C_LEVEL';
    if (/\b(director|diretor|directora|diretora|managing)\b/.test(value)) {
        return 'DIRECTOR';
    }
    if (/\b(manager|gerente|gestor|gestora|supervisor)\b/.test(value)) {
        return 'MANAGER';
    }
    if (/\b(assistant|assistente|atendimento|rece(p)?cionista|staff)\b/.test(value)) {
        return 'STAFF';
    }
    return 'UNKNOWN';
}
