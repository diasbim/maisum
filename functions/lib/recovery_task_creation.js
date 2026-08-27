"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CREATE_OPEN_RECOVERY_TASK_SQL = void 0;
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
