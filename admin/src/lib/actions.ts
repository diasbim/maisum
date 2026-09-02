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


function failure(message: string): ActionState {
  return { status: 'error', message };
}

/**
 * Turns a thrown error into a state the form can render.
 *
 * `AdminApiError` already carries the API's own `message`, which is the part an
 * operator can act on ("Plan version not found"), so it is passed through
 * rather than replaced with a generic string.
 */
function describe(caught: unknown): ActionState {
  if (caught instanceof AdminApiError) {
    return failure(caught.message);
  }
  return failure('Erro inesperado. A operacao pode nao ter sido aplicada.');
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

  if (!merchantId) return failure('Negocio em falta.');
  if (!featureKey) return failure('Indique a chave da funcionalidade.');

  const limit = optionalInt(form, 'limit_value');
  if (!limit.ok) return failure('O limite tem de ser um numero inteiro.');

  try {
    await upsertEntitlement({
      merchantId,
      featureKey,
      isEnabled: checkbox(form, 'is_enabled'),
      limitValue: limit.value,
      unit: optionalText(form, 'unit'),
    });
  } catch (caught) {
    return describe(caught);
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

  if (!planCode) return failure('Indique o codigo do plano.');
  if (!name) return failure('Indique o nome do plano.');
  if (!version.ok) return failure('A versao tem de ser um numero inteiro.');

  const isActive = checkbox(form, 'is_active');

  try {
    await upsertPlan({ planCode, version: version.value, name, isActive });
  } catch (caught) {
    return describe(caught);
  }

  revalidatePath('/admin/plans');
  revalidatePath('/admin/plans/reconciliacao');
  return {
    status: 'ok',
    // Activating a version deactivates the others for that code. That happens
    // server-side and is easy to miss, so it is stated back.
    message: isActive
      ? `Plano ${planCode} v${version.value} gravado e activo. As outras versoes deste codigo foram desactivadas.`
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

  if (!planCode) return failure('Indique o codigo do plano.');
  if (!pricingVersion.ok) {
    return failure('A versao de preco tem de ser um numero inteiro.');
  }
  if (!amount.ok) return failure('O valor tem de ser um numero inteiro.');
  if (amount.value < 0) return failure('O valor nao pode ser negativo.');

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
    return describe(caught);
  }

  revalidatePath('/admin/plans');
  return {
    status: 'ok',
    message: `Preco ${amount.value} ${currency} gravado para ${planCode}.`,
  };
}

export async function savePlanFeatureAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const planCode = text(form, 'plan_code');
  const featureKey = text(form, 'feature_key');
  const planVersion = requiredInt(form, 'plan_version');

  if (!planCode) return failure('Indique o codigo do plano.');
  if (!featureKey) return failure('Indique a chave da funcionalidade.');
  if (!planVersion.ok) {
    return failure('A versao do plano tem de ser um numero inteiro.');
  }

  const limit = optionalInt(form, 'limit_value');
  if (!limit.ok) return failure('O limite tem de ser um numero inteiro.');

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
    return describe(caught);
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
    return { ok: false, message: `JSON invalido: ${detail}` };
  }
}

export async function runJobAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const key = text(form, 'job');
  const path = JOB_BY_KEY[key];
  if (!path) return failure('Operacao desconhecida.');

  const payload = jobPayload(key, form);

  if (key === 'nfcCards') {
    const parsed = parseJsonField(form, 'items');
    if (!parsed.ok) return failure(parsed.message);
    if (!Array.isArray(parsed.value)) {
      return failure('O campo items tem de ser um array JSON.');
    }
    if (parsed.value.length === 0) {
      return failure('Indique pelo menos um cartao.');
    }
    if (parsed.value.length > 200) {
      return failure('A API aceita no maximo 200 cartoes por pedido.');
    }
    payload.items = parsed.value;
  }

  if (key === 'retentionPolicy') {
    const parsed = parseJsonField(form, 'policy');
    if (!parsed.ok) return failure(parsed.message);
    payload.policy = parsed.value;
  }

  let result: JobResult;
  try {
    result = await runJob(path, payload);
  } catch (caught) {
    return describe(caught);
  }

  const applied = payload.apply === true || payload.dry_run === false;
  return {
    status: 'ok',
    message: applied
      ? 'Executado. As alteracoes foram aplicadas.'
      : 'Simulacao concluida. Nada foi alterado.',
    result,
  };
}
