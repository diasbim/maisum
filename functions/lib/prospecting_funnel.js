"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MIN_SENDS_TO_COMPARE = exports.LAST_STAGE = exports.STAGE_OF = void 0;
exports.stageFor = stageFor;
exports.raiseStage = raiseStage;
exports.buildFunnel = buildFunnel;
exports.templateResults = templateResults;
exports.decisionSignals = decisionSignals;
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
/**
 * The funnel, and the trap in counting one from statuses.
 *
 * `prospects.status` is where a lead *is*, not where it has *been*. A lead
 * that signed up today has status `CUSTOMER`, which means a naive count by
 * status reports zero leads contacted — every one of them has moved on. Worse,
 * the error is invisible: the numbers look plausible, the rates come out
 * absurdly high, and the conclusion drawn from them is wrong in the direction
 * that flatters the product.
 *
 * So the funnel is not counted from `status`. It is counted from
 * `furthest_stage`, a high-water mark the store raises on every transition and
 * never lowers. A lead that reached `DEMO` and then went to `LOST` still
 * counts at every stage up to `DEMO`, which is the only way "how many of the
 * leads we contacted replied?" has a true answer.
 *
 * This module is pure: it turns a bag of counts into stages and rates. The
 * counting is Firestore's job and the interpretation is the operator's; what
 * happens here is only the arithmetic, so it can be checked without an
 * emulator.
 */
/* ------------------------------------------------------------------ stages */
/**
 * The ordered pipeline, as stage numbers.
 *
 * `RAW` is stage 0 and `CUSTOMER` is the last. Terminal statuses have no
 * stage of their own — a lead that went to `LOST` keeps the furthest pipeline
 * stage it had reached, which is exactly the point of the high-water mark.
 */
exports.STAGE_OF = Object.fromEntries(prospecting_contracts_js_1.PROSPECT_PIPELINE.map((status, index) => [status, index]));
exports.LAST_STAGE = prospecting_contracts_js_1.PROSPECT_PIPELINE.length - 1;
/**
 * The stage a status implies, for raising the high-water mark.
 *
 * A terminal status returns null: it says how a lead ended, not how far it
 * got, and writing one into the mark would erase the distance travelled. The
 * one exception people expect — `EXISTING_CUSTOMER` — is deliberately not
 * mapped to `CUSTOMER`: that lead was already a MaisUm merchant before
 * prospecting found it, and counting it as a conversion would credit the
 * funnel with a customer it did not win.
 */
function stageFor(status) {
    return exports.STAGE_OF[status] ?? null;
}
/**
 * The mark after a transition. Never lowers.
 *
 * Called by the store inside the same transaction that writes the status, so
 * the two cannot disagree.
 */
function raiseStage(current, to) {
    const reached = stageFor(to);
    const previous = current ?? 0;
    return reached === null ? previous : Math.max(previous, reached);
}
/**
 * Counts in, a funnel out.
 *
 * `reachedByStage` is how many leads have `furthest_stage` equal to each
 * index — not cumulative. This function does the accumulating, from the bottom
 * up, because a lead at stage 7 has by definition passed 0 through 6 and
 * asking the database that question eleven times is eleven queries for an
 * answer one pass of arithmetic already has.
 */
function buildFunnel(input) {
    const cumulative = new Array(prospecting_contracts_js_1.PROSPECT_PIPELINE.length).fill(0);
    let running = 0;
    for (let stage = exports.LAST_STAGE; stage >= 0; stage--) {
        running += input.reachedByStage[stage] ?? 0;
        cumulative[stage] = running;
    }
    const total = cumulative[0] ?? 0;
    const stages = prospecting_contracts_js_1.PROSPECT_PIPELINE.map((status, index) => {
        const reached = cumulative[index] ?? 0;
        const previous = index === 0 ? null : (cumulative[index - 1] ?? 0);
        return {
            status,
            label: prospecting_contracts_js_1.PROSPECT_STATUS_LABEL[status],
            stage: index,
            reached,
            // Division by zero is null, not zero and not NaN. "No leads reached the
            // previous stage" is not the same statement as "none of them converted",
            // and a screen that prints 0% for it is asserting something false.
            conversionFromPrevious: previous === null || previous === 0 ? null : reached / previous,
            conversionFromStart: total === 0 ? null : reached / total,
        };
    });
    const exits = Object.entries(input.exitsByStatus)
        .filter(([, count]) => (count ?? 0) > 0)
        .map(([status, count]) => ({
        status: status,
        label: prospecting_contracts_js_1.PROSPECT_STATUS_LABEL[status],
        count: count ?? 0,
    }))
        .sort((left, right) => right.count - left.count);
    return { stages, exits, total };
}
/** Below this, a reply rate is a coincidence with a percentage sign on it. */
exports.MIN_SENDS_TO_COMPARE = 30;
function templateResults(byTemplate) {
    return Object.entries(byTemplate)
        .map(([templateId, counts]) => ({
        templateId,
        sent: counts.sent,
        replied: counts.replied,
        replyRate: counts.sent === 0 ? null : counts.replied / counts.sent,
        conclusive: counts.sent >= exports.MIN_SENDS_TO_COMPARE,
    }))
        // Best first, but only among the conclusive ones: an inconclusive template
        // at the top of the table is a recommendation nobody meant to make.
        .sort((left, right) => {
        if (left.conclusive !== right.conclusive)
            return left.conclusive ? -1 : 1;
        return (right.replyRate ?? -1) - (left.replyRate ?? -1);
    });
}
function decisionSignals(input) {
    const contacted = input.funnel.stages.find((stage) => stage.status === 'CONTACTED')?.reached ?? 0;
    const replied = input.funnel.stages.find((stage) => stage.status === 'REPLIED')?.reached ?? 0;
    const priorityRate = input.priorityTotal === 0 ? null : input.priorityCustomers / input.priorityTotal;
    const nurtureRate = input.nurtureTotal === 0 ? null : input.nurtureCustomers / input.nurtureTotal;
    return {
        replyRate: contacted === 0 ? null : replied / contacted,
        // Null rather than Infinity when nurture converted nobody: one band
        // converting and the other not is not a ratio, and a screen showing ∞
        // would be reporting a certainty nobody has.
        bandSeparation: priorityRate === null || nurtureRate === null || nurtureRate === 0
            ? null
            : priorityRate / nurtureRate,
    };
}
