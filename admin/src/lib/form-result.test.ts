import assert from 'node:assert/strict';
import test from 'node:test';

import { AdminApiError } from './admin-api-error';
import {
  describe,
  failure,
  restoredCheckbox,
  snapshot,
} from './form-result';

function formOf(entries: Record<string, string>): FormData {
  const form = new FormData();
  for (const [key, value] of Object.entries(entries)) form.append(key, value);
  return form;
}

/* ------------------------------------------------------------------ snapshot */

test('snapshot keeps every string the operator submitted', () => {
  const form = formOf({ plan_code: 'pro', name: 'Pro', version: 'abc' });
  assert.deepEqual(snapshot(form), {
    plan_code: 'pro',
    name: 'Pro',
    version: 'abc',
  });
});

test('snapshot keeps values verbatim, including the invalid one', () => {
  // The point of restoring is to hand back what was typed so it can be
  // corrected. Trimming or dropping the bad value would defeat that.
  const form = formOf({ amount: '  -5  ' });
  assert.equal(snapshot(form).amount, '  -5  ');
});

test('snapshot skips file entries, which have no defaultValue to restore', () => {
  const form = new FormData();
  form.append('note', 'keep me');
  form.append('upload', new File(['x'], 'x.txt'));
  assert.deepEqual(snapshot(form), { note: 'keep me' });
});

/* ------------------------------------------------------------------- failure */

test('a field failure carries the values back and names the field', () => {
  const form = formOf({ plan_code: 'pro', version: 'abc' });
  const state = failure(form, 'A versão tem de ser um número inteiro.', 'version');

  assert.equal(state.status, 'error');
  assert.deepEqual(state.fieldErrors, {
    version: 'A versão tem de ser um número inteiro.',
  });
  // Without this the operator retypes the whole form to fix one field.
  assert.deepEqual(state.values, { plan_code: 'pro', version: 'abc' });
});

test('a failure with no field still restores the values', () => {
  const form = formOf({ job: 'nfcCards' });
  const state = failure(form, 'Operação desconhecida.');

  assert.equal(state.fieldErrors, undefined);
  assert.deepEqual(state.values, { job: 'nfcCards' });
});

/* ------------------------------------------------------------------ describe */

test('an API failure is framed in Portuguese rather than passed off as ours', () => {
  const form = formOf({ plan_code: 'pro' });
  const state = describe(
    new AdminApiError(404, '/admin/plans', 'Plan version not found'),
    form,
  );

  // The API's own English is quoted, not presented as the console's voice.
  assert.match(state.message, /^Não foi possível gravar\. A API respondeu: /);
  assert.match(state.message, /Plan version not found/);
  assert.deepEqual(state.values, { plan_code: 'pro' });
});

test('an unknown throw does not claim the write was rejected', () => {
  const form = formOf({ plan_code: 'pro' });
  const state = describe(new TypeError('boom'), form);

  // It may well have been applied — saying otherwise would send an operator
  // to re-run a job that already ran.
  assert.match(state.message, /pode não ter sido aplicada/);
  assert.deepEqual(state.values, { plan_code: 'pro' });
});

/* --------------------------------------------------------- checkbox restore */

test('before any submit a checkbox keeps its own default', () => {
  assert.equal(restoredCheckbox(false, undefined, true), true);
  assert.equal(restoredCheckbox(false, undefined, false), false);
  assert.equal(restoredCheckbox(false, undefined, undefined), undefined);
});

test('after a submit a missing checkbox means the operator had it off', () => {
  // An unchecked box sends nothing, so "absent" is an answer, not a gap. If the
  // default won here, a dry run the operator deliberately unchecked would come
  // back checked and the retry would write.
  assert.equal(restoredCheckbox(true, undefined, true), false);
});

test('after a submit a checked box comes back checked', () => {
  assert.equal(restoredCheckbox(true, 'on', false), true);
});
