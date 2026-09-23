'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';

import type { ActionState } from './action-state';
import { AdminApiError } from './admin-api';
import {
  affiliateFieldFor,
  expiresAtFrom,
  parseAffiliateName,
  parseAffiliatePhone,
  parseBenefit,
  parseUsageLimit,
  parseValidityDays,
  type Parsed,
} from './affiliate-form';
import { apiFailure, failure } from './form-result';
import {
  completeMyRecoveryTask,
  createMyAffiliate,
  decideMyAffiliateReward,
  setMyAffiliateActive,
  setMyAffiliateCodeEnabled,
  updateMyAffiliateCode,
} from './merchant-api';
import { getMerchantPermissions } from './merchant-session';

/**
 * What the business side of the portal is allowed to change.
 *
 * Kept apart from `actions.ts`, which is the internal console's mutations and
 * is guarded by the admin claim. Nothing here touches money, points or
 * customer records directly: those happen with the customer standing at the
 * counter and belong to the app. This file exists for bookkeeping about work
 * already done, and for the referral programme — who refers customers to this
 * business, what their code is worth, and which rewards the owner stands
 * behind.
 *
 * Server actions rather than route handlers, for the same reason as the
 * console's: the session cookie is read on the server and the ID token never
 * reaches the browser.
 *
 * Three rules hold across every affiliate action below.
 *
 * Nothing trusts the form for authorization: `requireOwner` asks the token,
 * and the API asks it again and is the one that decides. Nothing trusts the
 * form for a value either — the benefit, the limit and the dates are re-read
 * here and re-read again by the API, because a disabled input is a suggestion
 * and a POST is not.
 *
 * And every write says which pages it invalidated. These screens are server
 * rendered and cached per request; without the `revalidatePath` calls a code
 * would keep reading "Ativo" on the list after being disabled on its own page.
 */

export async function completeRecoveryTaskAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  const taskId = form.get('task_id');
  if (typeof taskId !== 'string' || taskId.trim() === '') {
    return { status: 'error', message: 'Não foi possível identificar a tarefa.' };
  }

  try {
    await completeMyRecoveryTask(taskId.trim());
  } catch (error) {
    if (error instanceof AdminApiError) {
      return { status: 'error', message: error.message };
    }
    return {
      status: 'error',
      message: 'Não foi possível concluir a tarefa. Tente de novo.',
    };
  }

  // The list is server-rendered and cached per request; without this the row
  // would still read "Pendente" until the next navigation.
  revalidatePath('/negocio/tarefas');
  revalidatePath('/negocio');
  return { status: 'ok', message: 'Tarefa concluída.' };
}

/* --------------------------------------------------------------- afiliados */

const AFFILIATES = '/negocio/afiliados';

function text(form: FormData, key: string): string {
  const value = form.get(key);
  return typeof value === 'string' ? value.trim() : '';
}

function checkbox(form: FormData, key: string): boolean {
  return form.get(key) === 'on' || form.get(key) === 'true';
}

/** A parser's refusal as the state the form renders, or null to carry on. */
function reject<T>(parsed: Parsed<T>, form: FormData): ActionState | null {
  return parsed.ok ? null : failure(form, parsed.message, parsed.field);
}

/**
 * The owner check, before anything is sent.
 *
 * The API refuses these writes for a manager anyway, with its own sentence.
 * Asking here first means the refusal names the rule rather than arriving as a
 * generic failure, and a form that was never meant to be submitted does not
 * reach the network at all.
 */
async function requireOwner(form: FormData): Promise<ActionState | null> {
  const permissions = await getMerchantPermissions();
  if (permissions.canManage) return null;
  return failure(
    form,
    permissions.reason ?? 'Não tem permissão para esta alteração.',
  );
}

function affiliatePath(affiliateId: string): string {
  return `${AFFILIATES}/${encodeURIComponent(affiliateId)}`;
}

/** Everything that could be showing this affiliate, after it changed. */
function revalidateAffiliate(affiliateId: string): void {
  revalidatePath(AFFILIATES);
  revalidatePath(`${AFFILIATES}/recompensas`);
  revalidatePath(affiliatePath(affiliateId));
  revalidatePath(`${affiliatePath(affiliateId)}/codigo`);
}

export async function createAffiliateAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  const denied = await requireOwner(form);
  if (denied) return denied;

  const name = parseAffiliateName(text(form, 'name'));
  const nameError = reject(name, form);
  if (nameError) return nameError;

  const phone = parseAffiliatePhone(text(form, 'phone'));
  const phoneError = reject(phone, form);
  if (phoneError) return phoneError;

  const benefit = parseBenefit(
    text(form, 'benefit_type'),
    text(form, 'benefit_value'),
  );
  const benefitError = reject(benefit, form);
  if (benefitError) return benefitError;

  const usageLimit = parseUsageLimit(text(form, 'usage_limit'));
  const usageError = reject(usageLimit, form);
  if (usageError) return usageError;

  const validity = parseValidityDays(text(form, 'validity_days'));
  const validityError = reject(validity, form);
  if (validityError) return validityError;

  if (!name.ok || !phone.ok || !benefit.ok || !usageLimit.ok || !validity.ok) {
    return failure(form, 'Reveja os campos do formulário.');
  }

  let created;
  try {
    created = await createMyAffiliate({
      name: name.value,
      phone: phone.value,
      benefitType: benefit.value.type,
      benefitValue: benefit.value.value,
      usageLimit: usageLimit.value,
      firstVisitOnly: checkbox(form, 'first_visit_only'),
      // One clock for the whole submit: reading the time twice is how a
      // validity window ends up a millisecond wide.
      expiresAt: expiresAtFrom(validity.value ?? 30, Date.now()),
    });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  if (created === null) {
    return failure(
      form,
      'O afiliado foi criado mas não foi possível ler o código. Atualize a lista.',
    );
  }

  revalidateAffiliate(created.id);

  // The code is minted by the server, so there is nothing to show — and
  // nothing to share — until it has answered. Landing on the affiliate's own
  // page is what puts the real code, and only then the share link, in front of
  // the owner. `redirect` throws, so it stays outside the try above.
  redirect(`${affiliatePath(created.id)}?novo=1`);
}

export async function setAffiliateActiveAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  const denied = await requireOwner(form);
  if (denied) return denied;

  const affiliateId = text(form, 'affiliate_id');
  if (affiliateId === '') {
    return failure(form, 'Não foi possível identificar o afiliado.');
  }
  const active = checkbox(form, 'active');

  try {
    await setMyAffiliateActive({ affiliateId, active });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidateAffiliate(affiliateId);
  return {
    status: 'ok',
    message: active
      ? 'Afiliado reativado. O código volta a ser aceite no balcão.'
      : 'Afiliado desativado. O código deixa de ser aceite no balcão.',
  };
}

export async function saveAffiliateCodeAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  const denied = await requireOwner(form);
  if (denied) return denied;

  const codeId = text(form, 'code_id');
  const affiliateId = text(form, 'affiliate_id');
  if (codeId === '' || affiliateId === '') {
    return failure(form, 'Não foi possível identificar o código.');
  }

  const benefit = parseBenefit(
    text(form, 'benefit_type'),
    text(form, 'benefit_value'),
  );
  const benefitError = reject(benefit, form);
  if (benefitError) return benefitError;

  const usageLimit = parseUsageLimit(text(form, 'usage_limit'));
  const usageError = reject(usageLimit, form);
  if (usageError) return usageError;

  // Blank here means "leave the dates alone", which is not what it means on
  // the create form. Sending one end without the other would move a code that
  // has not started yet to today without anyone asking, so both travel
  // together or neither does.
  const validity = parseValidityDays(text(form, 'validity_days'), {
    optional: true,
  });
  const validityError = reject(validity, form);
  if (validityError) return validityError;

  if (!benefit.ok || !usageLimit.ok || !validity.ok) {
    return failure(form, 'Reveja os campos do formulário.');
  }

  const now = Date.now();
  try {
    await updateMyAffiliateCode({
      codeId,
      benefitType: benefit.value.type,
      benefitValue: benefit.value.value,
      usageLimit: usageLimit.value,
      firstVisitOnly: checkbox(form, 'first_visit_only'),
      validity:
        validity.value === null
          ? null
          : { startsAt: now, expiresAt: expiresAtFrom(validity.value, now) },
    });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidateAffiliate(affiliateId);
  return { status: 'ok', message: 'Código gravado.' };
}

export async function setAffiliateCodeEnabledAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  const denied = await requireOwner(form);
  if (denied) return denied;

  const codeId = text(form, 'code_id');
  const affiliateId = text(form, 'affiliate_id');
  if (codeId === '' || affiliateId === '') {
    return failure(form, 'Não foi possível identificar o código.');
  }
  const enabled = checkbox(form, 'enabled');

  try {
    await setMyAffiliateCodeEnabled({ codeId, enabled });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidateAffiliate(affiliateId);
  return {
    status: 'ok',
    message: enabled
      ? 'Código ativado. Volta a ser aceite no balcão.'
      : 'Código desativado. Deixa de ser aceite no balcão.',
  };
}

/**
 * Approving a reward, which is the owner standing behind points already owed.
 *
 * No value is sent and none is read: what the reward is worth was decided when
 * the sale was committed, from this business's own settings. Paying is not one
 * of the choices here — the API offers no transition to `PAID` from the
 * portal, and the plan leaves handing the points over to a person.
 */
export async function approveAffiliateRewardAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  return decideReward(form, 'approve');
}

/**
 * Cancelling one, which is the opposite and does not come back.
 *
 * The form carries a confirmation the operator has to tick, in the same shape
 * the console uses for a job that writes rather than simulates. `CANCELLED`
 * has no transition out of it, so the tick is the last place this can be
 * stopped.
 */
export async function cancelAffiliateRewardAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  if (!checkbox(form, 'confirm')) {
    return failure(
      form,
      'Confirme o cancelamento: uma recompensa cancelada não volta atrás.',
      'confirm',
    );
  }
  return decideReward(form, 'cancel');
}

async function decideReward(
  form: FormData,
  decision: 'approve' | 'cancel',
): Promise<ActionState> {
  const denied = await requireOwner(form);
  if (denied) return denied;

  const rewardId = text(form, 'reward_id');
  if (rewardId === '') {
    return failure(form, 'Não foi possível identificar a recompensa.');
  }

  let reward;
  try {
    reward = await decideMyAffiliateReward({ rewardId, decision });
  } catch (caught) {
    return apiFailure(caught, form, affiliateFieldFor);
  }

  revalidatePath(AFFILIATES);
  revalidatePath(`${AFFILIATES}/recompensas`);
  // Whose page to refresh comes off the answer rather than off the form: the
  // row that was clicked does not get to name it.
  const affiliateId = reward?.affiliate_id ?? text(form, 'affiliate_id');
  if (affiliateId !== '') revalidatePath(affiliatePath(affiliateId));

  return {
    status: 'ok',
    message:
      decision === 'approve'
        ? 'Recompensa aprovada. Os pontos ficam prontos para entrega.'
        : 'Recompensa cancelada.',
  };
}
