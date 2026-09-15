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

/**
 * The three states the app writes, and only those.
 *
 * `appUserStatus*` in `app_constants.dart` is the whole list. This table used
 * to carry `SUSPENDED` and `PENDING`, which nothing in the codebase has ever
 * written, and to omit `INVITED`, which the app writes every time someone is
 * invited to a team — so the one state a business owner most needs to act on
 * reached them as an English enum. The test reads those constants now instead
 * of repeating them here.
 */
const STAFF_STATUS: Record<string, string> = {
  ACTIVE: 'Ativo',
  INVITED: 'Convidado',
  INACTIVE: 'Inativo',
};

const STAFF_ROLE: Record<string, string> = {
  OWNER: 'Proprietário',
  MANAGER: 'Gerente',
  STAFF: 'Colaborador',
};

/**
 * The six in `SubscriptionStatus` in the app.
 *
 * The plan page was printing this one straight through, so the business owner
 * whose payment had failed read `PAST_DUE` — the state on that screen they had
 * most reason to understand, in the language they were least likely to.
 */
const SUBSCRIPTION: Record<string, string> = {
  TRIAL: 'Experiência',
  ACTIVE: 'Ativa',
  GRACE: 'Em tolerância',
  PAST_DUE: 'Pagamento em atraso',
  CANCELED: 'Cancelada',
  SUSPENDED: 'Suspensa',
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

export const subscriptionLabel = (value: string | null) =>
  translate(SUBSCRIPTION, value);

/* ------------------------------------------- the vocabulary of the new pages */

/**
 * The words the app already uses, not new ones.
 *
 * `engage_labels.dart` has said "Crítico" for a red risk level and "Só volta
 * com promoção" for a visit result since Engage shipped. A merchant who reads
 * one of those on the phone and a different word here would reasonably think
 * they were looking at two different things, so these are copied from there
 * rather than invented — and the test reads that file to keep them in step.
 *
 * `translate` upper-cases before looking up, which is what lets a stored
 * 'green', 'high' or 'Needs Promotion' find its entry here.
 */

const RISK_LEVEL: Record<string, string> = {
  RED: 'Crítico',
  ORANGE: 'Alerta',
  YELLOW: 'Atenção',
  GREEN: 'Saudável',
};

const TASK_PRIORITY: Record<string, string> = {
  HIGH: 'Alta',
  MEDIUM: 'Média',
  LOW: 'Baixa',
};

const TASK_STATUS: Record<string, string> = {
  OPEN: 'Pendente',
  COMPLETED: 'Concluída',
};

const VISIT_RESULT: Record<string, string> = {
  RETURNED: 'Voltou à loja',
  INTERESTED: 'Mostrou interesse',
  // Stored with a space, and `translate` only upper-cases, so the key keeps it.
  'NEEDS PROMOTION': 'Só volta com promoção',
  'WRONG NUMBER': 'Contacto errado',
  'LOST CUSTOMER': 'Cliente perdido',
};

const APPOINTMENT_STATUS: Record<string, string> = {
  SCHEDULED: 'Marcada',
  COMPLETED: 'Cumprida',
  CANCELLED: 'Cancelada',
  MISSED: 'Faltou',
};

const BONUS_STATUS: Record<string, string> = {
  ACTIVE: 'Por usar',
  REDEEMED: 'Usado',
  EXPIRED: 'Expirado',
  CANCELLED: 'Cancelado',
};

const BONUS_TYPE: Record<string, string> = {
  DISCOUNT: 'Desconto',
  EXTRA_POINTS: 'Pontos extra',
  FREE_SERVICE: 'Serviço grátis',
};

/**
 * How a sale ended up in the ledger.
 *
 * A points line without its reason is a number a business cannot argue with,
 * which is the opposite of what a ledger is for.
 */
const LEDGER_ENTRY: Record<string, string> = {
  EARN: 'Ganhou',
  ACCRUAL: 'Ganhou',
  REDEEM: 'Trocou',
  REDEMPTION: 'Trocou',
  REVERSAL: 'Anulado',
  ADJUSTMENT: 'Correção',
  BASELINE: 'Saldo inicial',
  EXPIRY: 'Expirou',
};

export const riskLevelLabel = (value: string | null) =>
  translate(RISK_LEVEL, value);

export const taskPriorityLabel = (value: string | null) =>
  translate(TASK_PRIORITY, value);

export const taskStatusLabel = (value: string | null) =>
  translate(TASK_STATUS, value);

export const visitResultLabel = (value: string | null) =>
  translate(VISIT_RESULT, value);

export const appointmentStatusLabel = (value: string | null) =>
  translate(APPOINTMENT_STATUS, value);

export const bonusStatusLabel = (value: string | null) =>
  translate(BONUS_STATUS, value);

export const bonusTypeLabel = (value: string | null) =>
  translate(BONUS_TYPE, value);

export const ledgerEntryLabel = (value: string | null) =>
  translate(LEDGER_ENTRY, value);

/**
 * Metric keys, which are stored as the code that counts them.
 *
 * Unlike the tables above there is no closed set: a metric added to the
 * backend should still appear on the usage screen, so an unknown key falls
 * through to a readable version of itself rather than being hidden.
 */
const METRIC: Record<string, string> = {
  SALES: 'Vendas',
  CUSTOMERS: 'Clientes',
  CAMPAIGNS: 'Campanhas',
  WHATSAPP_MESSAGES: 'Mensagens WhatsApp',
  SURVEYS: 'Inquéritos',
  SURVEY_RESPONSES: 'Respostas a inquéritos',
  STAFF_SEATS: 'Lugares de equipa',
  RECOVERY_TASKS: 'Tarefas de recuperação',
  VISIT_REPORTS: 'Relatórios de visita',
  APPOINTMENTS: 'Marcações',
  NFC_CARDS: 'Cartões NFC',
};

export function metricLabel(value: string | null): string | null {
  if (!value) return null;
  const known = METRIC[value.trim().toUpperCase()];
  if (known) return known;
  // `whatsapp_messages` reads better as "Whatsapp messages" than as itself.
  const words = value.trim().replace(/_/g, ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/**
 * Feature keys, which the plan page used to print as they are stored.
 *
 * An owner reading their own plan was shown `engage_manage_recovery` and
 * `cloud_backup`. The canonical list is the app's own `FeatureKeys`
 * (`lib/features/subscription/domain/feature_keys.dart`), and the test beside
 * this file reads that file so a feature added there without a name here
 * fails rather than reaching a business untranslated.
 *
 * Named for what the feature does for the business, not for the module it
 * lives in: an owner has never heard of "Engage".
 */
const FEATURE: Record<string, string> = {
  WHATSAPP_AUTOMATION: 'Mensagens automáticas por WhatsApp',
  CAMPAIGNS: 'Campanhas',
  ANALYTICS: 'Relatórios e análises',
  MULTI_DEVICE: 'Vários dispositivos',
  CLOUD_BACKUP: 'Cópia de segurança na nuvem',
  ENGAGE_VIEW_RISK: 'Ver clientes em risco',
  ENGAGE_MANAGE_RECOVERY: 'Gerir tarefas de recuperação',
  ENGAGE_MANAGE_VISITS: 'Registar relatórios de visita',
  ENGAGE_MANAGE_SURVEYS: 'Criar e gerir inquéritos',
  RETENTION_CORE: 'Automações de retenção',
};

/**
 * An unknown key falls through to a readable version of itself, like the
 * metrics above: a feature the backend has and this table has not is still
 * better shown than hidden.
 */
export function featureLabel(value: string | null): string | null {
  if (!value) return null;
  const known = FEATURE[value.trim().toUpperCase()];
  if (known) return known;
  const words = value.trim().replace(/_/g, ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/**
 * What happened to a redemption.
 *
 * The portal used to print these untranslated, on the grounds that the app
 * wrote no fixed vocabulary here. It does: `redemption_status` in
 * `functions/src/customer_api_contracts.ts` is exactly these three, and the
 * app writes `PENDING` the moment a customer asks for a reward.
 */
const REDEMPTION_STATUS: Record<string, string> = {
  PENDING: 'Por levantar',
  CONSUMED: 'Levantado',
  EXPIRED: 'Expirado',
};

export const redemptionStatusLabel = (value: string | null) =>
  translate(REDEMPTION_STATUS, value);
