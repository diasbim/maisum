'use server';

import { revalidatePath } from 'next/cache';

import type { ActionState } from './action-state';
import {
  AdminApiError,
  JOB_PATHS,
  type JobPath,
  type JobResult,
  runJob,
  upsertEntitlement,
  upsertPlan,
  upsertPlanFeature,
  upsertPrice,
} from './admin-api';

/**
 * Every mutation the portal can perform.
 *
 * These are server actions rather than route handlers so the session cookie is
 * read on the server and the ID token never reaches the browser. A form posts
 * straight here; there is no client-side fetch to the admin API at all.
 */


/**
 * Everything the operator typed, so a rejected submit can hand it straight back.
 *
 * Only string entries are kept: `File` values have no `defaultValue` to restore
 * them to, and none of these forms upload anything.
 */
function snapshot(form: FormData): Record<string, string> {
  const values: Record<string, string> = {};
  for (const [key, value] of form.entries()) {
    if (typeof value === 'string') values[key] = value;
  }
  return values;
}

/**
 * A validation failure.
 *
 * `field` names the input at fault so the message can render against it rather
 * than only at the foot of the form. Omit it for failures that belong to the
 * submission as a whole.
 */
function failure(form: FormData, message: string, field?: string): ActionState {
  return {
    status: 'error',
    message,
    values: snapshot(form),
    ...(field ? { fieldErrors: { [field]: message } } : {}),
  };
}

/**
 * Turns a thrown error into a state the form can render.
 *
 * `AdminApiError` carries a message the API wrote, which is often English
 * ("Plan version not found") and would land mid-sentence in a Portuguese
 * console. It is shown as a quoted detail under a Portuguese lead rather than
 * passed off as our own copy, so the operator still gets the specific reason
 * without the interface changing language on them.
 */
function describe(caught: unknown, form: FormData): ActionState {
  if (caught instanceof AdminApiError) {
    return {
      status: 'error',
      message: `Não foi possível gravar. A API respondeu: ${caught.message}`,
      values: snapshot(form),
    };
  }
  return {
    status: 'error',
    message: 'Erro inesperado. A operação pode não ter sido aplicada.',
    values: snapshot(form),
  };
}

/* ------------------------------------------------------------------- fields */

function text(form: FormData, key: string): string {
  const value = form.get(key);
  return typeof value === 'string' ? value.trim() : '';
}

function checkbox(form: FormData, key: string): boolean {
  return form.get(key) === 'on' || form.get(key) === 'true';
}

/**
 * An optional integer field.
 *
 * Blank means "no value", which is different from zero — a blank limit leaves
 * an entitlement unmetered, while `0` denies it entirely. Conflating them would
 * silently cut off a paying business, so a blank returns `null` and anything
 * unparseable is an error rather than a default.
 */
function optionalInt(
  form: FormData,
  key: string,
): { ok: true; value: number | null } | { ok: false } {
  const raw = text(form, key);
  if (raw === '') return { ok: true, value: null };
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) return { ok: false };
  return { ok: true, value: parsed };
}

function requiredInt(
  form: FormData,
  key: string,
): { ok: true; value: number } | { ok: false } {
  const parsed = Number.parseInt(text(form, key), 10);
  if (!Number.isFinite(parsed)) return { ok: false };
  return { ok: true, value: parsed };
}

function optionalText(form: FormData, key: string): string | null {
  const value = text(form, key);
  return value === '' ? null : value;
}

/* -------------------------------------------------------------- entitlements */

export async function saveEntitlementAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const merchantId = text(form, 'merchant_id');
  const featureKey = text(form, 'feature_key');

  if (!merchantId) return failure(form, 'Indique o negócio.', 'merchant_id');
  if (!featureKey) return failure(form, 'Indique a chave da funcionalidade.', 'feature_key');

  const limit = optionalInt(form, 'limit_value');
  if (!limit.ok) return failure(form, 'O limite tem de ser um número inteiro.', 'limit_value');

  try {
    await upsertEntitlement({
      merchantId,
      featureKey,
      isEnabled: checkbox(form, 'is_enabled'),
      limitValue: limit.value,
      unit: optionalText(form, 'unit'),
    });
  } catch (caught) {
    return describe(caught, form);
  }

  revalidatePath(`/admin/merchants/${merchantId}`);
  return {
    status: 'ok',
    message: `Entitlement "${featureKey}" gravado.`,
  };
}

/* --------------------------------------------------------------------- plans */

export async function savePlanAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const planCode = text(form, 'plan_code');
  const name = text(form, 'name');
  const version = requiredInt(form, 'version');

  if (!planCode) return failure(form, 'Indique o código do plano.', 'plan_code');
  if (!name) return failure(form, 'Indique o nome do plano.', 'name');
  if (!version.ok) return failure(form, 'A versão tem de ser um número inteiro.', 'version');

  const isActive = checkbox(form, 'is_active');

  try {
    await upsertPlan({ planCode, version: version.value, name, isActive });
  } catch (caught) {
    return describe(caught, form);
  }

  revalidatePath('/admin/plans');
  revalidatePath('/admin/plans/reconciliacao');
  return {
    status: 'ok',
    // Activating a version deactivates the others for that code. That happens
    // server-side and is easy to miss, so it is stated back.
    message: isActive
      ? `Plano ${planCode} v${version.value} gravado e activo. As outras versões deste código foram desactivadas.`
      : `Plano ${planCode} v${version.value} gravado como inactivo.`,
  };
}

export async function savePriceAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const planCode = text(form, 'plan_code');
  const currency = text(form, 'currency') || 'MZN';
  const pricingVersion = requiredInt(form, 'pricing_version');
  const amount = requiredInt(form, 'amount');

  if (!planCode) return failure(form, 'Indique o código do plano.', 'plan_code');
  if (!pricingVersion.ok) {
    return failure(form, 'A versão de preço tem de ser um número inteiro.', 'pricing_version');
  }
  if (!amount.ok) return failure(form, 'O valor tem de ser um número inteiro.', 'amount');
  if (amount.value < 0) return failure(form, 'O valor não pode ser negativo.', 'amount');

  try {
    await upsertPrice({
      planCode,
      pricingVersion: pricingVersion.value,
      currency,
      amount: amount.value,
      billingPeriod: text(form, 'billing_period') || 'monthly',
      isActive: checkbox(form, 'is_active'),
    });
  } catch (caught) {
    return describe(caught, form);
  }

  revalidatePath('/admin/plans');
  return {
    status: 'ok',
    message: `Preço ${amount.value} ${currency} gravado para ${planCode}.`,
  };
}

export async function savePlanFeatureAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const planCode = text(form, 'plan_code');
  const featureKey = text(form, 'feature_key');
  const planVersion = requiredInt(form, 'plan_version');

  if (!planCode) return failure(form, 'Indique o código do plano.', 'plan_code');
  if (!featureKey) return failure(form, 'Indique a chave da funcionalidade.', 'feature_key');
  if (!planVersion.ok) {
    return failure(form, 'A versão do plano tem de ser um número inteiro.', 'plan_version');
  }

  const limit = optionalInt(form, 'limit_value');
  if (!limit.ok) return failure(form, 'O limite tem de ser um número inteiro.', 'limit_value');

  try {
    await upsertPlanFeature({
      planCode,
      planVersion: planVersion.value,
      featureKey,
      isEnabled: checkbox(form, 'is_enabled'),
      limitValue: limit.value,
      unit: optionalText(form, 'unit'),
    });
  } catch (caught) {
    return describe(caught, form);
  }

  revalidatePath('/admin/plans');
  revalidatePath('/admin/plans/reconciliacao');
  return {
    status: 'ok',
    message: `Funcionalidade "${featureKey}" gravada em ${planCode} v${planVersion.value}.`,
  };
}

/* ---------------------------------------------------------------------- jobs */

const JOB_BY_KEY: Record<string, JobPath> = {
  businessCustomers: JOB_PATHS.businessCustomersBackfill,
  nfcCards: JOB_PATHS.nfcCardsBackfill,
  loyaltyBackfill: JOB_PATHS.loyaltyLedgerBackfill,
  loyaltyReconcile: JOB_PATHS.loyaltyLedgerReconcile,
  retentionPolicy: JOB_PATHS.retentionPolicyUpsert,
  retentionScan: JOB_PATHS.retentionClassificationScan,
};

/**
 * Builds the job payload from the form.
 *
 * Only keys the operator actually filled in are sent. An empty cursor field
 * must not become `start_after_id: ""`, which the API would treat as a real
 * cursor and use to skip the first page.
 */
function jobPayload(key: string, form: FormData): Record<string, unknown> {
  const payload: Record<string, unknown> = {};

  const put = (field: string, value: unknown) => {
    if (value !== null && value !== undefined && value !== '') {
      payload[field] = value;
    }
  };

  put('merchant_id', optionalText(form, 'merchant_id'));

  const limit = optionalInt(form, 'limit');
  if (limit.ok && limit.value != null) payload.limit = limit.value;

  switch (key) {
    case 'businessCustomers':
      payload.dry_run = !checkbox(form, 'apply');
      put('start_after_customer_id', optionalText(form, 'cursor'));
      break;

    case 'nfcCards':
      payload.dry_run = !checkbox(form, 'apply');
      break;

    case 'loyaltyBackfill':
      payload.apply = checkbox(form, 'apply');
      put('source_type', optionalText(form, 'source_type'));
      put('start_after_id', optionalText(form, 'cursor'));
      break;

    case 'loyaltyReconcile':
    case 'retentionScan':
      payload.apply = checkbox(form, 'apply');
      put('start_after_customer_id', optionalText(form, 'cursor'));
      break;

    case 'retentionPolicy': {
      const version = optionalInt(form, 'expected_current_version');
      if (version.ok && version.value != null) {
        payload.expected_current_version = version.value;
      }
      break;
    }
  }

  return payload;
}

/**
 * Parses the JSON field two jobs need (NFC card items, retention policy).
 *
 * A malformed paste is reported with the parser's own message rather than a
 * generic one — a trailing comma at position 412 is something the operator can
 * fix, "invalid JSON" is not.
 */
function parseJsonField(
  form: FormData,
  key: string,
): { ok: true; value: unknown } | { ok: false; message: string } {
  const raw = text(form, key);
  if (raw === '') return { ok: false, message: 'Preencha o campo JSON.' };
  try {
    return { ok: true, value: JSON.parse(raw) };
  } catch (caught) {
    const detail = caught instanceof Error ? caught.message : String(caught);
    return { ok: false, message: `JSON inválido: ${detail}` };
  }
}

export async function runJobAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const key = text(form, 'job');
  const path = JOB_BY_KEY[key];
  if (!path) return failure(form, 'Operação desconhecida.', 'job');

  const payload = jobPayload(key, form);

  if (key === 'nfcCards') {
    const parsed = parseJsonField(form, 'items');
    if (!parsed.ok) return failure(form, parsed.message, 'items');
    if (!Array.isArray(parsed.value)) {
      return failure(form, 'O campo items tem de ser um array JSON.', 'items');
    }
    if (parsed.value.length === 0) {
      return failure(form, 'Indique pelo menos um cartão.', 'items');
    }
    if (parsed.value.length > 200) {
      return failure(form, 'A API aceita no máximo 200 cartões por pedido.', 'items');
    }
    payload.items = parsed.value;
  }

  if (key === 'retentionPolicy') {
    const parsed = parseJsonField(form, 'policy');
    if (!parsed.ok) return failure(form, parsed.message, 'policy');
    payload.policy = parsed.value;
  }

  let result: JobResult;
  try {
    result = await runJob(path, payload);
  } catch (caught) {
    return describe(caught, form);
  }

  const applied = payload.apply === true || payload.dry_run === false;
  return {
    status: 'ok',
    message: applied
      ? 'Executado. As alterações foram aplicadas.'
      : 'Simulação concluída. Nada foi alterado.',
    result,
  };
}
