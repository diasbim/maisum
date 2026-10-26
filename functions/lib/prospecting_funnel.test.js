"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_funnel_js_1 = require("./prospecting_funnel.js");
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
/* ------------------------------------------------------------------ stages */
(0, node_test_1.default)('the pipeline maps to stage numbers in order', () => {
    strict_1.default.equal(prospecting_funnel_js_1.STAGE_OF.RAW, 0);
    strict_1.default.equal(prospecting_funnel_js_1.STAGE_OF.CONTACTED, 5);
    strict_1.default.equal(prospecting_funnel_js_1.STAGE_OF.CUSTOMER, prospecting_funnel_js_1.LAST_STAGE);
    strict_1.default.equal(prospecting_funnel_js_1.LAST_STAGE, prospecting_contracts_js_1.PROSPECT_PIPELINE.length - 1);
});
(0, node_test_1.default)('a terminal status has no stage of its own', () => {
    // It says how a lead ended, not how far it got.
    strict_1.default.equal((0, prospecting_funnel_js_1.stageFor)('LOST'), null);
    strict_1.default.equal((0, prospecting_funnel_js_1.stageFor)('DO_NOT_CONTACT'), null);
    strict_1.default.equal((0, prospecting_funnel_js_1.stageFor)('NOT_A_FIT'), null);
});
(0, node_test_1.default)('an existing customer is not counted as a conversion', () => {
    // That business was already a MaisUm merchant before prospecting found it.
    // Mapping it to CUSTOMER would credit the funnel with a win it did not make.
    strict_1.default.equal((0, prospecting_funnel_js_1.stageFor)('EXISTING_CUSTOMER'), null);
});
(0, node_test_1.default)('the high-water mark rises and never falls', () => {
    strict_1.default.equal((0, prospecting_funnel_js_1.raiseStage)(null, 'RAW'), 0);
    strict_1.default.equal((0, prospecting_funnel_js_1.raiseStage)(0, 'SCORED'), 2);
    strict_1.default.equal((0, prospecting_funnel_js_1.raiseStage)(5, 'CONTACTED'), 5);
    // The case the whole mechanism exists for: a lead that reached DEMO and then
    // went to LOST has still been through DEMO.
    strict_1.default.equal((0, prospecting_funnel_js_1.raiseStage)(8, 'LOST'), 8);
    strict_1.default.equal((0, prospecting_funnel_js_1.raiseStage)(8, 'DO_NOT_CONTACT'), 8);
    // And a transition backwards, if one ever happened, does not lower it.
    strict_1.default.equal((0, prospecting_funnel_js_1.raiseStage)(8, 'SCORED'), 8);
});
/* ------------------------------------------------------------------ funnel */
(0, node_test_1.default)('reaching a later stage counts at every stage before it', () => {
    /**
     * The trap this module exists to avoid.
     *
     * Five leads, all of them now customers. Counting by current status would
     * report zero contacted and zero replied — and a reply rate of nothing, on a
     * pipeline that converted everybody.
     */
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({
        reachedByStage: { [prospecting_funnel_js_1.LAST_STAGE]: 5 },
        exitsByStatus: {},
    });
    strict_1.default.equal(funnel.total, 5);
    for (const stage of funnel.stages) {
        strict_1.default.equal(stage.reached, 5, `${stage.status} should count all five`);
    }
});
(0, node_test_1.default)('the worked example from the plan comes out right', () => {
    // 700 qualified, 300 scored on, 200 contacted, 40 replied, 5 customers.
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({
        reachedByStage: {
            0: 300, // stopped at RAW
            1: 400, // stopped at QUALIFIED
            2: 100, // stopped at SCORED
            5: 160, // contacted, never replied
            6: 25, // replied, went no further
            7: 10,
            10: 5, // customers
        },
        exitsByStatus: { LOST: 20, NOT_A_FIT: 300 },
    });
    const reached = (status) => funnel.stages.find((stage) => stage.status === status)?.reached ?? 0;
    strict_1.default.equal(funnel.total, 1000);
    strict_1.default.equal(reached('QUALIFIED'), 700);
    strict_1.default.equal(reached('CONTACTED'), 200);
    strict_1.default.equal(reached('REPLIED'), 40);
    strict_1.default.equal(reached('CUSTOMER'), 5);
    const replied = funnel.stages.find((stage) => stage.status === 'REPLIED');
    strict_1.default.equal(replied?.conversionFromPrevious, 40 / 200);
    strict_1.default.equal(replied?.conversionFromStart, 40 / 1000);
});
(0, node_test_1.default)('a stage nobody reached converts to null, not to zero', () => {
    // "No leads reached the previous stage" is not the same statement as "none
    // of them converted", and a screen printing 0% asserts something false.
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({ reachedByStage: { 0: 10 }, exitsByStatus: {} });
    const contacted = funnel.stages.find((stage) => stage.status === 'CONTACTED');
    strict_1.default.equal(contacted?.reached, 0);
    strict_1.default.equal(contacted?.conversionFromPrevious, null);
});
(0, node_test_1.default)('an empty pipeline reports nothing rather than dividing by zero', () => {
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({ reachedByStage: {}, exitsByStatus: {} });
    strict_1.default.equal(funnel.total, 0);
    strict_1.default.deepEqual(funnel.exits, []);
    for (const stage of funnel.stages) {
        strict_1.default.equal(stage.reached, 0);
        strict_1.default.equal(stage.conversionFromStart, null);
    }
});
(0, node_test_1.default)('the first stage has no previous to convert from', () => {
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({ reachedByStage: { 0: 10 }, exitsByStatus: {} });
    strict_1.default.equal(funnel.stages[0].conversionFromPrevious, null);
    strict_1.default.equal(funnel.stages[0].conversionFromStart, 1);
});
(0, node_test_1.default)('exits are listed largest first and empty ones are dropped', () => {
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({
        reachedByStage: { 0: 100 },
        exitsByStatus: { LOST: 5, NOT_A_FIT: 30, OPTED_OUT: 0 },
    });
    strict_1.default.deepEqual(funnel.exits.map((exit) => exit.status), ['NOT_A_FIT', 'LOST']);
    strict_1.default.ok(funnel.exits.every((exit) => exit.label !== undefined));
});
/* ------------------------------------------------------------- the signals */
(0, node_test_1.default)('the reply rate is measured over everyone ever contacted', () => {
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({
        reachedByStage: { 5: 160, 6: 35, 10: 5 },
        exitsByStatus: {},
    });
    const signals = (0, prospecting_funnel_js_1.decisionSignals)({
        funnel,
        priorityCustomers: 4,
        priorityTotal: 50,
        nurtureCustomers: 1,
        nurtureTotal: 100,
    });
    strict_1.default.equal(signals.replyRate, 40 / 200);
    // Priority converts at 8%, nurture at 1%: the rules are discriminating, and
    // a learned ranking has nothing to add yet.
    strict_1.default.equal(signals.bandSeparation, 0.08 / 0.01);
});
(0, node_test_1.default)('bands that convert alike are the signal that the rules are not working', () => {
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({ reachedByStage: { 5: 100 }, exitsByStatus: {} });
    const signals = (0, prospecting_funnel_js_1.decisionSignals)({
        funnel,
        priorityCustomers: 5,
        priorityTotal: 100,
        nurtureCustomers: 5,
        nurtureTotal: 100,
    });
    strict_1.default.equal(signals.bandSeparation, 1);
});
(0, node_test_1.default)('nobody contacted yet is null, not a rate of zero', () => {
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({ reachedByStage: { 0: 50 }, exitsByStatus: {} });
    const signals = (0, prospecting_funnel_js_1.decisionSignals)({
        funnel,
        priorityCustomers: 0,
        priorityTotal: 0,
        nurtureCustomers: 0,
        nurtureTotal: 0,
    });
    strict_1.default.equal(signals.replyRate, null);
    strict_1.default.equal(signals.bandSeparation, null);
});
(0, node_test_1.default)('one band converting and the other not is not a ratio', () => {
    // Infinity on a screen would be reporting a certainty nobody has.
    const funnel = (0, prospecting_funnel_js_1.buildFunnel)({ reachedByStage: { 5: 10 }, exitsByStatus: {} });
    const signals = (0, prospecting_funnel_js_1.decisionSignals)({
        funnel,
        priorityCustomers: 3,
        priorityTotal: 10,
        nurtureCustomers: 0,
        nurtureTotal: 10,
    });
    strict_1.default.equal(signals.bandSeparation, null);
});
/* ----------------------------------------------------------- the A/B table */
(0, node_test_1.default)('a template with no sends has no rate, rather than a rate of zero', () => {
    const [row] = (0, prospecting_funnel_js_1.templateResults)({ 'a-v1': { sent: 0, replied: 0 } });
    strict_1.default.equal(row.replyRate, null);
    strict_1.default.equal(row.conclusive, false);
});
(0, node_test_1.default)('a small sample is marked inconclusive and sorted below a real one', () => {
    // 1 of 2 is 50% and means nothing; 9 of 60 is 15% and means something. A
    // table that ranked by rate alone would put the noise on top and send an
    // operator to rewrite the template that is actually working.
    const rows = (0, prospecting_funnel_js_1.templateResults)({
        'lucky-v1': { sent: 2, replied: 1 },
        'real-v1': { sent: 60, replied: 9 },
    });
    strict_1.default.equal(rows[0].templateId, 'real-v1');
    strict_1.default.equal(rows[0].conclusive, true);
    strict_1.default.equal(rows[1].templateId, 'lucky-v1');
    strict_1.default.equal(rows[1].conclusive, false);
});
(0, node_test_1.default)('conclusive templates are ranked best first', () => {
    const rows = (0, prospecting_funnel_js_1.templateResults)({
        'worse-v1': { sent: 100, replied: 5 },
        'better-v2': { sent: 100, replied: 20 },
    });
    strict_1.default.equal(rows[0].templateId, 'better-v2');
    strict_1.default.equal(rows[0].replyRate, 0.2);
    strict_1.default.equal(rows[1].templateId, 'worse-v1');
});
(0, node_test_1.default)('the threshold is the stated one', () => {
    strict_1.default.equal((0, prospecting_funnel_js_1.templateResults)({ x: { sent: prospecting_funnel_js_1.MIN_SENDS_TO_COMPARE - 1, replied: 1 } })[0]
        .conclusive, false);
    strict_1.default.equal((0, prospecting_funnel_js_1.templateResults)({ x: { sent: prospecting_funnel_js_1.MIN_SENDS_TO_COMPARE, replied: 1 } })[0].conclusive, true);
});
(0, node_test_1.default)('nothing sent at all produces an empty table, not a row of dashes', () => {
    strict_1.default.deepEqual((0, prospecting_funnel_js_1.templateResults)({}), []);
});
