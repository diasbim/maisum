import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildFunnel,
  decisionSignals,
  LAST_STAGE,
  raiseStage,
  stageFor,
  STAGE_OF,
  templateResults,
  MIN_SENDS_TO_COMPARE,
} from './prospecting_funnel.js';
import { PROSPECT_PIPELINE } from './prospecting_contracts.js';

/* ------------------------------------------------------------------ stages */

test('the pipeline maps to stage numbers in order', () => {
  assert.equal(STAGE_OF.RAW, 0);
  assert.equal(STAGE_OF.CONTACTED, 5);
  assert.equal(STAGE_OF.CUSTOMER, LAST_STAGE);
  assert.equal(LAST_STAGE, PROSPECT_PIPELINE.length - 1);
});

test('a terminal status has no stage of its own', () => {
  // It says how a lead ended, not how far it got.
  assert.equal(stageFor('LOST'), null);
  assert.equal(stageFor('DO_NOT_CONTACT'), null);
  assert.equal(stageFor('NOT_A_FIT'), null);
});

test('an existing customer is not counted as a conversion', () => {
  // That business was already a MaisUm merchant before prospecting found it.
  // Mapping it to CUSTOMER would credit the funnel with a win it did not make.
  assert.equal(stageFor('EXISTING_CUSTOMER'), null);
});

test('the high-water mark rises and never falls', () => {
  assert.equal(raiseStage(null, 'RAW'), 0);
  assert.equal(raiseStage(0, 'SCORED'), 2);
  assert.equal(raiseStage(5, 'CONTACTED'), 5);
  // The case the whole mechanism exists for: a lead that reached DEMO and then
  // went to LOST has still been through DEMO.
  assert.equal(raiseStage(8, 'LOST'), 8);
  assert.equal(raiseStage(8, 'DO_NOT_CONTACT'), 8);
  // And a transition backwards, if one ever happened, does not lower it.
  assert.equal(raiseStage(8, 'SCORED'), 8);
});

/* ------------------------------------------------------------------ funnel */

test('reaching a later stage counts at every stage before it', () => {
  /**
   * The trap this module exists to avoid.
   *
   * Five leads, all of them now customers. Counting by current status would
   * report zero contacted and zero replied — and a reply rate of nothing, on a
   * pipeline that converted everybody.
   */
  const funnel = buildFunnel({
    reachedByStage: { [LAST_STAGE]: 5 },
    exitsByStatus: {},
  });

  assert.equal(funnel.total, 5);
  for (const stage of funnel.stages) {
    assert.equal(stage.reached, 5, `${stage.status} should count all five`);
  }
});

test('the worked example from the plan comes out right', () => {
  // 700 qualified, 300 scored on, 200 contacted, 40 replied, 5 customers.
  const funnel = buildFunnel({
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

  const reached = (status: string) =>
    funnel.stages.find((stage) => stage.status === status)?.reached ?? 0;

  assert.equal(funnel.total, 1000);
  assert.equal(reached('QUALIFIED'), 700);
  assert.equal(reached('CONTACTED'), 200);
  assert.equal(reached('REPLIED'), 40);
  assert.equal(reached('CUSTOMER'), 5);

  const replied = funnel.stages.find((stage) => stage.status === 'REPLIED');
  assert.equal(replied?.conversionFromPrevious, 40 / 200);
  assert.equal(replied?.conversionFromStart, 40 / 1000);
});

test('a stage nobody reached converts to null, not to zero', () => {
  // "No leads reached the previous stage" is not the same statement as "none
  // of them converted", and a screen printing 0% asserts something false.
  const funnel = buildFunnel({ reachedByStage: { 0: 10 }, exitsByStatus: {} });
  const contacted = funnel.stages.find((stage) => stage.status === 'CONTACTED');

  assert.equal(contacted?.reached, 0);
  assert.equal(contacted?.conversionFromPrevious, null);
});

test('an empty pipeline reports nothing rather than dividing by zero', () => {
  const funnel = buildFunnel({ reachedByStage: {}, exitsByStatus: {} });

  assert.equal(funnel.total, 0);
  assert.deepEqual(funnel.exits, []);
  for (const stage of funnel.stages) {
    assert.equal(stage.reached, 0);
    assert.equal(stage.conversionFromStart, null);
  }
});

test('the first stage has no previous to convert from', () => {
  const funnel = buildFunnel({ reachedByStage: { 0: 10 }, exitsByStatus: {} });
  assert.equal(funnel.stages[0]!.conversionFromPrevious, null);
  assert.equal(funnel.stages[0]!.conversionFromStart, 1);
});

test('exits are listed largest first and empty ones are dropped', () => {
  const funnel = buildFunnel({
    reachedByStage: { 0: 100 },
    exitsByStatus: { LOST: 5, NOT_A_FIT: 30, OPTED_OUT: 0 },
  });

  assert.deepEqual(
    funnel.exits.map((exit) => exit.status),
    ['NOT_A_FIT', 'LOST'],
  );
  assert.ok(funnel.exits.every((exit) => exit.label !== undefined));
});

/* ------------------------------------------------------------- the signals */

test('the reply rate is measured over everyone ever contacted', () => {
  const funnel = buildFunnel({
    reachedByStage: { 5: 160, 6: 35, 10: 5 },
    exitsByStatus: {},
  });

  const signals = decisionSignals({
    funnel,
    priorityCustomers: 4,
    priorityTotal: 50,
    nurtureCustomers: 1,
    nurtureTotal: 100,
  });

  assert.equal(signals.replyRate, 40 / 200);
  // Priority converts at 8%, nurture at 1%: the rules are discriminating, and
  // a learned ranking has nothing to add yet.
  assert.equal(signals.bandSeparation, 0.08 / 0.01);
});

test('bands that convert alike are the signal that the rules are not working', () => {
  const funnel = buildFunnel({ reachedByStage: { 5: 100 }, exitsByStatus: {} });
  const signals = decisionSignals({
    funnel,
    priorityCustomers: 5,
    priorityTotal: 100,
    nurtureCustomers: 5,
    nurtureTotal: 100,
  });

  assert.equal(signals.bandSeparation, 1);
});

test('nobody contacted yet is null, not a rate of zero', () => {
  const funnel = buildFunnel({ reachedByStage: { 0: 50 }, exitsByStatus: {} });
  const signals = decisionSignals({
    funnel,
    priorityCustomers: 0,
    priorityTotal: 0,
    nurtureCustomers: 0,
    nurtureTotal: 0,
  });

  assert.equal(signals.replyRate, null);
  assert.equal(signals.bandSeparation, null);
});

test('one band converting and the other not is not a ratio', () => {
  // Infinity on a screen would be reporting a certainty nobody has.
  const funnel = buildFunnel({ reachedByStage: { 5: 10 }, exitsByStatus: {} });
  const signals = decisionSignals({
    funnel,
    priorityCustomers: 3,
    priorityTotal: 10,
    nurtureCustomers: 0,
    nurtureTotal: 10,
  });

  assert.equal(signals.bandSeparation, null);
});

/* ----------------------------------------------------------- the A/B table */

test('a template with no sends has no rate, rather than a rate of zero', () => {
  const [row] = templateResults({ 'a-v1': { sent: 0, replied: 0 } });
  assert.equal(row!.replyRate, null);
  assert.equal(row!.conclusive, false);
});

test('a small sample is marked inconclusive and sorted below a real one', () => {
  // 1 of 2 is 50% and means nothing; 9 of 60 is 15% and means something. A
  // table that ranked by rate alone would put the noise on top and send an
  // operator to rewrite the template that is actually working.
  const rows = templateResults({
    'lucky-v1': { sent: 2, replied: 1 },
    'real-v1': { sent: 60, replied: 9 },
  });

  assert.equal(rows[0]!.templateId, 'real-v1');
  assert.equal(rows[0]!.conclusive, true);
  assert.equal(rows[1]!.templateId, 'lucky-v1');
  assert.equal(rows[1]!.conclusive, false);
});

test('conclusive templates are ranked best first', () => {
  const rows = templateResults({
    'worse-v1': { sent: 100, replied: 5 },
    'better-v2': { sent: 100, replied: 20 },
  });

  assert.equal(rows[0]!.templateId, 'better-v2');
  assert.equal(rows[0]!.replyRate, 0.2);
  assert.equal(rows[1]!.templateId, 'worse-v1');
});

test('the threshold is the stated one', () => {
  assert.equal(
    templateResults({ x: { sent: MIN_SENDS_TO_COMPARE - 1, replied: 1 } })[0]!
      .conclusive,
    false,
  );
  assert.equal(
    templateResults({ x: { sent: MIN_SENDS_TO_COMPARE, replied: 1 } })[0]!.conclusive,
    true,
  );
});

test('nothing sent at all produces an empty table, not a row of dashes', () => {
  assert.deepEqual(templateResults({}), []);
});
