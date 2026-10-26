import assert from 'node:assert/strict';
import test from 'node:test';

import { AdminApiError, statusMessage } from './admin-api-error';

test('a forbidden error is recognised from either rejecting status', () => {
  assert.equal(new AdminApiError(401, '/admin/plans', 'x').isForbidden, true);
  assert.equal(new AdminApiError(403, '/admin/plans', 'x').isForbidden, true);
  assert.equal(new AdminApiError(404, '/admin/plans', 'x').isForbidden, false);
  assert.equal(new AdminApiError(500, '/admin/plans', 'x').isForbidden, false);
});

test('every status maps to a Portuguese sentence, not a code', () => {
  for (const status of [400, 404, 409, 422, 429, 500, 503, 418]) {
    const message = statusMessage(status);
    assert.ok(message.length > 0, `status ${status} produced nothing`);
    // The number and the route belong in the server log. Neither tells an
    // operator anything they can act on.
    assert.doesNotMatch(
      message,
      new RegExp(String(status)),
      `status ${status} leaked its code into the message`,
    );
    assert.doesNotMatch(message, /\/admin\//, `status ${status} leaked a path`);
    assert.doesNotMatch(message, /http/i, `status ${status} leaked a URL`);
  }
});

test('every status message ends in a full sentence', () => {
  for (const status of [400, 404, 409, 422, 429, 500, 418]) {
    assert.match(statusMessage(status), /\.$/);
  }
});

test('the statuses an operator can act on are told apart', () => {
  const distinct = new Set(
    [404, 409, 422, 429, 500].map((s) => statusMessage(s)),
  );
  // A conflict and a missing record call for different next moves; collapsing
  // them into one sentence would hide that.
  assert.equal(distinct.size, 5);
});

test('400 and 422 share the "review the fields" message', () => {
  assert.equal(statusMessage(400), statusMessage(422));
});

test('any 5xx is treated as the API failing, not as bad input', () => {
  assert.equal(statusMessage(500), statusMessage(503));
  assert.match(statusMessage(502), /API/);
});
