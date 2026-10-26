import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

import {
  COMPLETE_RECOVERY_TASK_SQL,
  CREATE_OPEN_RECOVERY_TASK_SQL,
  completeRecoveryTask,
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

/* -------------------------------------------------------------- completion */

test('completion is scoped to the business that owns the task', async () => {
  const calls: unknown[][] = [];
  const db = {
    async query(_sql: string, values: unknown[]) {
      calls.push(values);
      return { rows: [{ id: 'task-1', status: 'completed' } as RecoveryTaskRow] };
    },
  };

  const task = await completeRecoveryTask(db, {
    merchantId: 'merchant-1',
    taskId: 'task-1',
    actorAppUserId: 'user-1',
    now: 456,
  });

  assert.equal(task?.id, 'task-1');
  // The merchant id is a predicate, never a value the caller can omit: without
  // it, any task id would close any business's task.
  assert.deepEqual(calls[0], ['task-1', 'merchant-1', 456, 'user-1']);
  assert.match(COMPLETE_RECOVERY_TASK_SQL, /AND merchant_id = \$2/);
});

test('a task that is already completed is left exactly as it was', async () => {
  // The WHERE clause, not the caller, is what makes a second click harmless:
  // without it a double submit would rewrite updated_at and the actor.
  assert.match(COMPLETE_RECOVERY_TASK_SQL, /LOWER\(status\) <> 'completed'/);

  const db = {
    async query() {
      return { rows: [] as RecoveryTaskRow[] };
    },
  };

  assert.equal(
    await completeRecoveryTask(db, {
      merchantId: 'merchant-1',
      taskId: 'task-1',
      actorAppUserId: null,
      now: 456,
    }),
    null,
  );
});

test('an unknown task and a foreign one are indistinguishable', async () => {
  // Both return no row, which is what lets the route answer 404 for either
  // without confirming that another business's task id exists.
  const db = {
    async query() {
      return { rows: [] as RecoveryTaskRow[] };
    },
  };

  for (const taskId of ['does-not-exist', 'belongs-to-someone-else']) {
    assert.equal(
      await completeRecoveryTask(db, {
        merchantId: 'merchant-1',
        taskId,
        actorAppUserId: null,
        now: 1,
      }),
      null,
    );
  }
});

test('the status written is the one the app reads back', async () => {
  // `RecoveryTaskStatus.completed` in engage_models.dart is 'completed'. A
  // mismatch here would leave the task open on every phone.
  const dart = readFileSync(
    resolve(__dirname, '..', '..', 'lib', 'features', 'engage', 'domain', 'engage_models.dart'),
    'utf8',
  );
  const match = /static const String completed = '([a-z]+)';/.exec(dart);
  assert.ok(match, 'RecoveryTaskStatus.completed is no longer in engage_models.dart');
  assert.match(COMPLETE_RECOVERY_TASK_SQL, new RegExp(`status = '${match[1]}'`));
});
