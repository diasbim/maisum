"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.COMPLETE_RECOVERY_TASK_SQL = exports.CREATE_OPEN_RECOVERY_TASK_SQL = void 0;
exports.completeRecoveryTask = completeRecoveryTask;
exports.createOrGetOpenRecoveryTask = createOrGetOpenRecoveryTask;
const crypto_1 = require("crypto");
exports.CREATE_OPEN_RECOVERY_TASK_SQL = `
  INSERT INTO recovery_tasks (
    id,
    merchant_id,
    customer_id,
    priority,
    status,
    due_at,
    notes,
    created_at,
    updated_at,
    created_by_app_user_id,
    updated_by_app_user_id
  ) VALUES ($1,$2,$3,$4,'open',$5,$6,$7,$8,$9,$9)
  ON CONFLICT (merchant_id, customer_id, open_slot) DO UPDATE SET
    priority = CASE
      WHEN recovery_tasks.id = EXCLUDED.id THEN EXCLUDED.priority
      ELSE recovery_tasks.priority
    END,
    due_at = CASE
      WHEN recovery_tasks.id = EXCLUDED.id THEN EXCLUDED.due_at
      ELSE recovery_tasks.due_at
    END,
    notes = CASE
      WHEN recovery_tasks.id = EXCLUDED.id THEN EXCLUDED.notes
      ELSE recovery_tasks.notes
    END,
    updated_by_app_user_id = CASE
      WHEN recovery_tasks.id = EXCLUDED.id THEN EXCLUDED.updated_by_app_user_id
      ELSE recovery_tasks.updated_by_app_user_id
    END,
    updated_at = CASE
      WHEN recovery_tasks.id = EXCLUDED.id THEN EXCLUDED.updated_at
      ELSE recovery_tasks.updated_at
    END
  RETURNING recovery_tasks.*, recovery_tasks.id = $1 AS creation_created
`;
/**
 * Completing a task, scoped to its own business.
 *
 * `status` is compared case-insensitively because the two writers disagree:
 * the app stores `open`/`completed` lower-case, and nothing stops a future
 * caller from sending `OPEN`. Re-completing a task that is already completed
 * returns no row rather than touching `updated_at`, so a double click does not
 * rewrite who closed it and when.
 */
exports.COMPLETE_RECOVERY_TASK_SQL = `
  UPDATE recovery_tasks
  SET status = 'completed',
    updated_at = $3,
    updated_by_app_user_id = $4
  WHERE id = $1
    AND merchant_id = $2
    AND LOWER(status) <> 'completed'
  RETURNING *
`;
/**
 * Returns the task as it now stands, or null when there was nothing to close —
 * an unknown id, another business's task, or one already completed. The caller
 * decides which of those it wants to tell the user apart.
 */
async function completeRecoveryTask(db, input) {
    const result = await db.query(exports.COMPLETE_RECOVERY_TASK_SQL, [
        input.taskId,
        input.merchantId,
        input.now,
        input.actorAppUserId,
    ]);
    return result.rows[0] ?? null;
}
async function createOrGetOpenRecoveryTask(db, input) {
    const id = input.id ?? (0, crypto_1.randomUUID)();
    const result = await db.query(exports.CREATE_OPEN_RECOVERY_TASK_SQL, [
        id,
        input.merchantId,
        input.customerId,
        input.priority,
        input.dueAt,
        input.notes,
        input.createdAt ?? input.now,
        input.now,
        input.actorAppUserId,
    ]);
    const row = result.rows[0];
    if (!row) {
        throw new Error('Recovery task insert returned no row');
    }
    const { creation_created: created, ...task } = row;
    return {
        task,
        outcome: created === true ? 'created' : 'already_open',
    };
}
