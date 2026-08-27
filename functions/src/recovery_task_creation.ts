import { randomUUID } from 'crypto';

export type RecoveryTaskCreationOutcome = 'created' | 'already_open';

export type RecoveryTaskRow = Record<string, unknown> & {
  id: string;
  creation_created?: boolean;
};

export type RecoveryTaskCreationResult = {
  task: Record<string, unknown>;
  outcome: RecoveryTaskCreationOutcome;
};

type Queryable = {
  query(
    sql: string,
    values: unknown[],
  ): Promise<{ rows: RecoveryTaskRow[] }>;
};

export type CreateRecoveryTaskInput = {
  merchantId: string;
  customerId: string;
  priority: string;
  dueAt: number | null;
  notes: string | null;
  actorAppUserId: string | null;
  now: number;
  id?: string;
  createdAt?: number;
};

export const CREATE_OPEN_RECOVERY_TASK_SQL = `
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

export async function createOrGetOpenRecoveryTask(
  db: Queryable,
  input: CreateRecoveryTaskInput,
): Promise<RecoveryTaskCreationResult> {
  const id = input.id ?? randomUUID();
  const result = await db.query(CREATE_OPEN_RECOVERY_TASK_SQL, [
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
