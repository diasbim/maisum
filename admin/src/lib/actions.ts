'use server';

import { revalidatePath } from 'next/cache';

import type { ActionState } from './action-state';
import {
  affiliateFieldFor,
  expiresAtFrom,
  parseAffiliateName,
  parseAffiliatePhone,
  parseBenefit,
  parseUsageLimit,
  parseValidityDays,
} from './affiliate-form';
// Shared with the form primitives and covered by form-result.test.ts.
import { apiFailure, describe, failure } from './form-result';
import {
  createAffiliate,
  JOB_PATHS,
  type JobPath,
  type JobResult,
  linkAffiliateToMerchant,
  runJob,
  setAffiliateStatus,
  unlinkAffiliateFromMerchant,
  updateAffiliateName,
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

/* --------------------------------------------------------------- afiliados */

/**
 * The console's writes against the referral programme.
 *
 * What the console governs is the person and their reach: the identity behind
 * a phone, whether they may refer for anybody at all, and which businesses
 * they are attached to. What a code is worth inside one business is the
 * owner's decision and is made in `/negocio/afiliados` — the one exception is
 * the benefit a link is created with, which has to be stated because a code
 * cannot exist without one.
 *
 * Every one of these is recorded by the API in the audit trail, with the state
 * before and after and the name of the operator who asked, because the
 * portal forwards their own token rather than holding a credential of its own.
 */

const ADMIN_AFFILIATES = '/admin/afiliados';

function adminAffiliatePath(affiliateId: string): string {
  return `${ADMIN_AFFILIATES}/${encodeURIComponent(affiliateId)}`;
}

export async function createGlobalAffiliateAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const name = parseAffiliateName(text(form, 'name'));
  if (!name.ok) return failure(form, name.message, name.field);

  const phone = parseAffiliatePhone(text(form, 'phone'));
  if (!phone.ok) return failure(form, phone.message, phone.field);

  let created;
  try {
    created = await createAffiliate({ name: name.value, phone: phone.value });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidatePath(ADMIN_AFFILIATES);
  if (created) revalidatePath(adminAffiliatePath(created.id));

  return {
    status: 'ok',
    // The id is derived from the phone, so it is the one thing worth reading
    // back: it is how this person is addressed everywhere else.
    message: created
      ? `Afiliado ${created.name} criado (${created.id}).`
      : 'Afiliado criado.',
  };
}

export async function renameAffiliateAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const affiliateId = text(form, 'affiliate_id');
  if (!affiliateId) return failure(form, 'Indique o afiliado.', 'affiliate_id');

  const name = parseAffiliateName(text(form, 'name'));
  if (!name.ok) return failure(form, name.message, name.field);

  try {
    await updateAffiliateName({ affiliateId, name: name.value });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidatePath(ADMIN_AFFILIATES);
  revalidatePath(adminAffiliatePath(affiliateId));
  return {
    status: 'ok',
    // The code was minted from the name it was created with and does not
    // change. Saying so here stops the next question.
    message: `Nome gravado. Os códigos já emitidos mantêm-se como estão.`,
  };
}

const AFFILIATE_STATUSES = new Set(['ACTIVE', 'INACTIVE', 'SUSPENDED']);

export async function setGlobalAffiliateStatusAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const affiliateId = text(form, 'affiliate_id');
  if (!affiliateId) return failure(form, 'Indique o afiliado.', 'affiliate_id');

  const status = text(form, 'status').toUpperCase();
  if (!AFFILIATE_STATUSES.has(status)) {
    return failure(form, 'Estado inválido.', 'status');
  }

  // Suspension reaches every business this person refers for, which is not
  // obvious from a button on one page.
  if (status === 'SUSPENDED' && !checkbox(form, 'confirm')) {
    return failure(
      form,
      'Confirme a suspensão: o afiliado deixa de poder indicar em todos os negócios.',
      'confirm',
    );
  }

  try {
    await setAffiliateStatus({
      affiliateId,
      status: status as 'ACTIVE' | 'INACTIVE' | 'SUSPENDED',
    });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidatePath(ADMIN_AFFILIATES);
  revalidatePath(adminAffiliatePath(affiliateId));
  return {
    status: 'ok',
    message:
      status === 'SUSPENDED'
        ? 'Afiliado suspenso em toda a plataforma.'
        : status === 'ACTIVE'
          ? 'Afiliado reativado.'
          : 'Afiliado marcado como inativo.',
  };
}

export async function linkAffiliateAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const affiliateId = text(form, 'affiliate_id');
  if (!affiliateId) return failure(form, 'Indique o afiliado.', 'affiliate_id');

  const merchantId = text(form, 'merchant_id');
  if (!merchantId) return failure(form, 'Indique o id do negócio.', 'merchant_id');

  // A link without a code is not a link: the code is what a customer says at
  // the counter, and it cannot be minted without a benefit.
  const benefit = parseBenefit(
    text(form, 'benefit_type'),
    text(form, 'benefit_value'),
  );
  if (!benefit.ok) return failure(form, benefit.message, benefit.field);

  const usageLimit = parseUsageLimit(text(form, 'usage_limit'));
  if (!usageLimit.ok) return failure(form, usageLimit.message, usageLimit.field);

  const validity = parseValidityDays(text(form, 'validity_days'));
  if (!validity.ok) return failure(form, validity.message, validity.field);

  try {
    await linkAffiliateToMerchant({
      affiliateId,
      merchantId,
      benefitType: benefit.value.type,
      benefitValue: benefit.value.value,
      usageLimit: usageLimit.value,
      firstVisitOnly: checkbox(form, 'first_visit_only'),
      expiresAt: expiresAtFrom(validity.value ?? 30, Date.now()),
    });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidatePath(ADMIN_AFFILIATES);
  revalidatePath(adminAffiliatePath(affiliateId));
  revalidatePath(`/admin/merchants/${merchantId}/afiliados`);
  revalidatePath('/negocio/afiliados');
  return { status: 'ok', message: `Afiliado ligado ao negócio ${merchantId}.` };
}

export async function unlinkAffiliateAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const affiliateId = text(form, 'affiliate_id');
  if (!affiliateId) return failure(form, 'Indique o afiliado.', 'affiliate_id');

  const merchantId = text(form, 'merchant_id');
  if (!merchantId) return failure(form, 'Indique o id do negócio.', 'merchant_id');

  if (!checkbox(form, 'confirm')) {
    return failure(
      form,
      'Confirme a desativação: o código deste afiliado deixa de ser aceite neste negócio.',
      'confirm',
    );
  }

  try {
    await unlinkAffiliateFromMerchant({ affiliateId, merchantId });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidatePath(ADMIN_AFFILIATES);
  revalidatePath(adminAffiliatePath(affiliateId));
  revalidatePath(`/admin/merchants/${merchantId}/afiliados`);
  revalidatePath('/negocio/afiliados');
  return {
    status: 'ok',
    // Nothing is erased, and that is the part an operator needs to know: the
    // history stays and re-linking brings the same person back.
    message: `Ligação desativada. O histórico mantém-se e o código foi desativado.`,
  };
}
