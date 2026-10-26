"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
/* --------------------------------------------------------------- the enum */
(0, node_test_1.default)('every status has a label, and no label is orphaned', () => {
    // A status with no label renders as a blank cell; a label with no status is
    // a rename somebody half-finished.
    for (const status of prospecting_contracts_js_1.PROSPECT_STATUS) {
        strict_1.default.ok(prospecting_contracts_js_1.PROSPECT_STATUS_LABEL[status], `no label for ${status}`);
    }
    strict_1.default.equal(Object.keys(prospecting_contracts_js_1.PROSPECT_STATUS_LABEL).length, prospecting_contracts_js_1.PROSPECT_STATUS.length);
});
(0, node_test_1.default)('the pipeline and the terminal set do not overlap', () => {
    for (const status of prospecting_contracts_js_1.PROSPECT_PIPELINE) {
        strict_1.default.equal((0, prospecting_contracts_js_1.isTerminalStatus)(status), false, `${status} is both`);
    }
    for (const status of prospecting_contracts_js_1.PROSPECT_TERMINAL) {
        strict_1.default.equal((0, prospecting_contracts_js_1.isTerminalStatus)(status), true);
    }
});
(0, node_test_1.default)('an unknown string is not a status', () => {
    strict_1.default.equal((0, prospecting_contracts_js_1.isProspectStatus)('RAW'), true);
    strict_1.default.equal((0, prospecting_contracts_js_1.isProspectStatus)('raw'), false);
    strict_1.default.equal((0, prospecting_contracts_js_1.isProspectStatus)('WON'), false);
    strict_1.default.equal((0, prospecting_contracts_js_1.isProspectStatus)(null), false);
});
/* --------------------------------------------------------- the transitions */
(0, node_test_1.default)('the pipeline moves forward one stage at a time', () => {
    for (let index = 0; index < prospecting_contracts_js_1.PROSPECT_PIPELINE.length - 1; index++) {
        strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)(prospecting_contracts_js_1.PROSPECT_PIPELINE[index], prospecting_contracts_js_1.PROSPECT_PIPELINE[index + 1]), true);
    }
});
(0, node_test_1.default)('stages may be skipped', () => {
    // A lead that answers the first message goes straight to REPLIED without
    // anyone recording a CONTACTED that did not happen.
    strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)('READY_TO_CONTACT', 'REPLIED'), true);
    strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)('RAW', 'CUSTOMER'), true);
});
(0, node_test_1.default)('the pipeline never moves backwards', () => {
    strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)('DEMO', 'CONTACTED'), false);
    strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)('CUSTOMER', 'TRIAL'), false);
    strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)('QUALIFIED', 'RAW'), false);
});
(0, node_test_1.default)('a status cannot transition to itself', () => {
    for (const status of prospecting_contracts_js_1.PROSPECT_STATUS) {
        strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)(status, status), false);
    }
});
(0, node_test_1.default)('any pipeline stage may end', () => {
    for (const from of prospecting_contracts_js_1.PROSPECT_PIPELINE) {
        for (const to of prospecting_contracts_js_1.PROSPECT_TERMINAL) {
            strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)(from, to), true, `${from} -> ${to}`);
        }
    }
});
(0, node_test_1.default)('a terminal status admits nothing at all', () => {
    // Not even back to RAW: reopening a DO_NOT_CONTACT would erase a refusal the
    // person who gave it has no way to give twice.
    for (const from of prospecting_contracts_js_1.PROSPECT_TERMINAL) {
        for (const to of prospecting_contracts_js_1.PROSPECT_STATUS) {
            strict_1.default.equal((0, prospecting_contracts_js_1.canTransition)(from, to), false, `${from} -> ${to}`);
        }
    }
});
/* ------------------------------------------------------------- the blocks */
(0, node_test_1.default)('only the two compliance statuses block outreach', () => {
    const blocking = prospecting_contracts_js_1.PROSPECT_STATUS.filter((status) => (0, prospecting_contracts_js_1.blocksOutreach)(status));
    strict_1.default.deepEqual([...blocking].sort(), ['DO_NOT_CONTACT', 'OPTED_OUT']);
});
(0, node_test_1.default)('being an existing customer stops acquisition but is not an outreach ban', () => {
    // Criterion 10 excludes them from the funnel; it does not say the account
    // manager may never write to them.
    strict_1.default.equal((0, prospecting_contracts_js_1.blocksOutreach)('EXISTING_CUSTOMER'), false);
    strict_1.default.equal((0, prospecting_contracts_js_1.isTerminalStatus)('EXISTING_CUSTOMER'), true);
});
/* --------------------------------------------------------------- contacts */
(0, node_test_1.default)('a decision maker is anyone from manager upwards', () => {
    strict_1.default.equal((0, prospecting_contracts_js_1.isDecisionMakerSeniority)('OWNER'), true);
    strict_1.default.equal((0, prospecting_contracts_js_1.isDecisionMakerSeniority)('FOUNDER'), true);
    strict_1.default.equal((0, prospecting_contracts_js_1.isDecisionMakerSeniority)('C_LEVEL'), true);
    strict_1.default.equal((0, prospecting_contracts_js_1.isDecisionMakerSeniority)('DIRECTOR'), true);
    strict_1.default.equal((0, prospecting_contracts_js_1.isDecisionMakerSeniority)('MANAGER'), true);
    strict_1.default.equal((0, prospecting_contracts_js_1.isDecisionMakerSeniority)('STAFF'), false);
    // An unmapped title is a gap in the mapping table, not a junior person — but
    // it is also not someone to present as the person to pitch.
    strict_1.default.equal((0, prospecting_contracts_js_1.isDecisionMakerSeniority)('UNKNOWN'), false);
});
(0, node_test_1.default)('only a verified email counts as reachable', () => {
    strict_1.default.equal((0, prospecting_contracts_js_1.isReachableEmail)('VERIFIED'), true);
    // A pattern-built address must never be treated as one that works.
    strict_1.default.equal((0, prospecting_contracts_js_1.isReachableEmail)('GUESSED'), false);
    strict_1.default.equal((0, prospecting_contracts_js_1.isReachableEmail)('UNVERIFIED'), false);
    strict_1.default.equal((0, prospecting_contracts_js_1.isReachableEmail)('INVALID'), false);
    strict_1.default.equal((0, prospecting_contracts_js_1.isReachableEmail)('UNKNOWN'), false);
});
/* ---------------------------------------------------------- exhaustiveness */
(0, node_test_1.default)('the transition table has no unreachable status', () => {
    // Every status must be reachable from RAW, or it is dead vocabulary that
    // will eventually be written by a route that does not consult this table.
    const unreachable = prospecting_contracts_js_1.PROSPECT_STATUS.filter((status) => status !== 'RAW' && !(0, prospecting_contracts_js_1.canTransition)('RAW', status));
    strict_1.default.deepEqual(unreachable, []);
});
