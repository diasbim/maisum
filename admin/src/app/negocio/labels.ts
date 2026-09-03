/**
 * The stored values, in the language the business reads.
 *
 * The console prints `ACTIVE` and `AT_RISK` on purpose — internal staff match
 * those strings against logs and rules. A business owner has no such need and
 * is owed their own language, so every enum that reaches a business screen
 * passes through here.
 *
 * An unknown value falls through as itself rather than as a dash: a state this
 * file has not caught up with is still information, and printing "—" would
 * hide it.
 */

function translate(
  table: Record<string, string>,
  value: string | null,
): string | null {
  if (!value) return null;
  return table[value.trim().toUpperCase()] ?? value;
}

const RELATIONSHIP: Record<string, string> = {
  ACTIVE: 'Ativo',
  BLOCKED: 'Bloqueado',
  ARCHIVED: 'Arquivado',
};

const LIFECYCLE: Record<string, string> = {
  NEW: 'Novo',
  ACTIVE: 'Ativo',
  RETURNING: 'Regressou',
  REGULAR: 'Regular',
  LOYAL: 'Fiel',
  VIP: 'VIP',
  ADVOCATE: 'Embaixador',
};

const RETENTION: Record<string, string> = {
  HEALTHY: 'Saudável',
  AT_RISK: 'Em risco',
  INACTIVE: 'Inativo',
  LOST: 'Perdido',
};

const STAFF_STATUS: Record<string, string> = {
  ACTIVE: 'Ativo',
  INACTIVE: 'Inativo',
  SUSPENDED: 'Suspenso',
  PENDING: 'Pendente',
};

const STAFF_ROLE: Record<string, string> = {
  OWNER: 'Proprietário',
  MANAGER: 'Gerente',
  STAFF: 'Colaborador',
};

export const relationshipLabel = (value: string | null) =>
  translate(RELATIONSHIP, value);

export const lifecycleLabel = (value: string | null) =>
  translate(LIFECYCLE, value);

export const retentionLabel = (value: string | null) =>
  translate(RETENTION, value);

export const staffStatusLabel = (value: string | null) =>
  translate(STAFF_STATUS, value);

export const staffRoleLabel = (value: string | null) =>
  translate(STAFF_ROLE, value);
