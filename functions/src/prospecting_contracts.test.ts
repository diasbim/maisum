import assert from 'node:assert/strict';
import test from 'node:test';

import {
  blocksOutreach,
  canTransition,
  isDecisionMakerSeniority,
  isProspectStatus,
  isReachableEmail,
  isTerminalStatus,
  PROSPECT_PIPELINE,
  PROSPECT_STATUS,
  PROSPECT_STATUS_LABEL,
  PROSPECT_TERMINAL,
  type ProspectStatus,
} from './prospecting_contracts.js';

/* --------------------------------------------------------------- the enum */

test('every status has a label, and no label is orphaned', () => {
  // A status with no label renders as a blank cell; a label with no status is
  // a rename somebody half-finished.
  for (const status of PROSPECT_STATUS) {
    assert.ok(PROSPECT_STATUS_LABEL[status], `no label for ${status}`);
  }
  assert.equal(Object.keys(PROSPECT_STATUS_LABEL).length, PROSPECT_STATUS.length);
});

test('the pipeline and the terminal set do not overlap', () => {
  for (const status of PROSPECT_PIPELINE) {
    assert.equal(isTerminalStatus(status), false, `${status} is both`);
  }
  for (const status of PROSPECT_TERMINAL) {
    assert.equal(isTerminalStatus(status), true);
  }
});

test('an unknown string is not a status', () => {
  assert.equal(isProspectStatus('RAW'), true);
  assert.equal(isProspectStatus('raw'), false);
  assert.equal(isProspectStatus('WON'), false);
  assert.equal(isProspectStatus(null), false);
});

/* --------------------------------------------------------- the transitions */

test('the pipeline moves forward one stage at a time', () => {
  for (let index = 0; index < PROSPECT_PIPELINE.length - 1; index++) {
    assert.equal(
      canTransition(PROSPECT_PIPELINE[index], PROSPECT_PIPELINE[index + 1]),
      true,
    );
  }
});

test('stages may be skipped', () => {
  // A lead that answers the first message goes straight to REPLIED without
  // anyone recording a CONTACTED that did not happen.
  assert.equal(canTransition('READY_TO_CONTACT', 'REPLIED'), true);
  assert.equal(canTransition('RAW', 'CUSTOMER'), true);
});

test('the pipeline never moves backwards', () => {
  assert.equal(canTransition('DEMO', 'CONTACTED'), false);
  assert.equal(canTransition('CUSTOMER', 'TRIAL'), false);
  assert.equal(canTransition('QUALIFIED', 'RAW'), false);
});

test('a status cannot transition to itself', () => {
  for (const status of PROSPECT_STATUS) {
    assert.equal(canTransition(status, status), false);
  }
});

test('any pipeline stage may end', () => {
  for (const from of PROSPECT_PIPELINE) {
    for (const to of PROSPECT_TERMINAL) {
      assert.equal(canTransition(from, to), true, `${from} -> ${to}`);
    }
  }
});

test('a terminal status admits nothing at all', () => {
  // Not even back to RAW: reopening a DO_NOT_CONTACT would erase a refusal the
  // person who gave it has no way to give twice.
  for (const from of PROSPECT_TERMINAL) {
    for (const to of PROSPECT_STATUS) {
      assert.equal(canTransition(from, to), false, `${from} -> ${to}`);
    }
  }
});

/* ------------------------------------------------------------- the blocks */

test('only the two compliance statuses block outreach', () => {
  const blocking = PROSPECT_STATUS.filter((status) => blocksOutreach(status));
  assert.deepEqual([...blocking].sort(), ['DO_NOT_CONTACT', 'OPTED_OUT']);
});

test('being an existing customer stops acquisition but is not an outreach ban', () => {
  // Criterion 10 excludes them from the funnel; it does not say the account
  // manager may never write to them.
  assert.equal(blocksOutreach('EXISTING_CUSTOMER'), false);
  assert.equal(isTerminalStatus('EXISTING_CUSTOMER'), true);
});

/* --------------------------------------------------------------- contacts */

test('a decision maker is anyone from manager upwards', () => {
  assert.equal(isDecisionMakerSeniority('OWNER'), true);
  assert.equal(isDecisionMakerSeniority('FOUNDER'), true);
  assert.equal(isDecisionMakerSeniority('C_LEVEL'), true);
  assert.equal(isDecisionMakerSeniority('DIRECTOR'), true);
  assert.equal(isDecisionMakerSeniority('MANAGER'), true);
  assert.equal(isDecisionMakerSeniority('STAFF'), false);
  // An unmapped title is a gap in the mapping table, not a junior person — but
  // it is also not someone to present as the person to pitch.
  assert.equal(isDecisionMakerSeniority('UNKNOWN'), false);
});

test('only a verified email counts as reachable', () => {
  assert.equal(isReachableEmail('VERIFIED'), true);
  // A pattern-built address must never be treated as one that works.
  assert.equal(isReachableEmail('GUESSED'), false);
  assert.equal(isReachableEmail('UNVERIFIED'), false);
  assert.equal(isReachableEmail('INVALID'), false);
  assert.equal(isReachableEmail('UNKNOWN'), false);
});

/* ---------------------------------------------------------- exhaustiveness */

test('the transition table has no unreachable status', () => {
  // Every status must be reachable from RAW, or it is dead vocabulary that
  // will eventually be written by a route that does not consult this table.
  const unreachable = PROSPECT_STATUS.filter(
    (status: ProspectStatus) => status !== 'RAW' && !canTransition('RAW', status),
  );
  assert.deepEqual(unreachable, []);
});
