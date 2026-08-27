import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

import {
  CREATE_OPEN_RECOVERY_TASK_SQL,
  createOrGetOpenRecoveryTask,
  type RecoveryTaskRow,
} from './recovery_task_creation.js';

test('uses one atomic merchant/customer open slot and returns the existing task', async () => {
  const existing: RecoveryTaskRow = {
    id: 'task-existing',
    merchant_id: 'merchant-1',
    customer_id: 'customer-1',
    status: 'open',
    creation_created: false,
  };
  const calls: unknown[][] = [];
  const db = {
    async query(_sql: string, values: unknown[]) {
      calls.push(values);
      return { rows: [existing] };
    },
  };

  const result = await createOrGetOpenRecoveryTask(db, {
    id: 'task-new',
    merchantId: 'merchant-1',
    customerId: 'customer-1',
    priority: 'high',
    dueAt: null,
    notes: null,
    actorAppUserId: 'user-1',
    now: 123,
  });

  assert.equal(result.outcome, 'already_open');
  assert.equal(result.task.id, 'task-existing');
  assert.equal('creation_created' in result.task, false);
  assert.deepEqual(calls[0]?.slice(1, 3), ['merchant-1', 'customer-1']);
  assert.match(
    CREATE_OPEN_RECOVERY_TASK_SQL,
    /ON CONFLICT \(merchant_id, customer_id, open_slot\) DO UPDATE/,
  );
});

test('reports a newly inserted open task as created', async () => {
  const db = {
    async query(_sql: string, values: unknown[]) {
      return {
        rows: [{
          id: values[0] as string,
          status: 'open',
          creation_created: true,
        }],
      };
    },
  };

  const result = await createOrGetOpenRecoveryTask(db, {
    id: 'task-new',
    merchantId: 'merchant-1',
    customerId: 'customer-1',
    priority: 'medium',
    dueAt: null,
    notes: null,
    actorAppUserId: null,
    now: 123,
  });

  assert.equal(result.outcome, 'created');
  assert.equal(result.task.id, 'task-new');
});

test('schema derives and uniquely indexes the open slot', () => {
  const schema = readFileSync(resolve(process.cwd(), 'sql/schema.sql'), 'utf8');

  assert.match(
    schema,
    /open_slot SMALLINT GENERATED ALWAYS AS \(\s*CASE WHEN LOWER\(status\) = 'open' THEN 1 ELSE NULL END\s*\) STORED/,
  );
  assert.match(
    schema,
    /CREATE UNIQUE INDEX IF NOT EXISTS idx_recovery_tasks_one_open_customer\s+ON recovery_tasks\(merchant_id, customer_id, open_slot\)/,
  );
});

test('queued task collision reconciles to the canonical remote task', async () => {
  const canonical: RecoveryTaskRow = {
    id: 'task-canonical',
    merchant_id: 'merchant-1',
    customer_id: 'customer-1',
    status: 'open',
    created_at: 1000,
    updated_at: 2000,
    creation_created: false,
  };
  let values: unknown[] = [];
  const db = {
    async query(_sql: string, queryValues: unknown[]) {
      values = queryValues;
      return { rows: [canonical] };
    },
  };

  const result = await createOrGetOpenRecoveryTask(db, {
    id: 'task-provisional',
    merchantId: 'merchant-1',
    customerId: 'customer-1',
    priority: 'low',
    dueAt: null,
    notes: 'queued offline',
    actorAppUserId: null,
    createdAt: 1500,
    now: 1600,
  });

  assert.equal(result.outcome, 'already_open');
  assert.equal(result.task.id, 'task-canonical');
  assert.equal(values[0], 'task-provisional');
  assert.equal(values[6], 1500);
});
