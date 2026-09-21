'use server';

import { revalidatePath } from 'next/cache';

import type { ActionState } from './action-state';
import { apiFailure, describe, failure, snapshot } from './form-result';
import { parseSearchForm } from './prospecting-form';
import {
  AdminApiError,
  analyzeLead,
  cancelSearch,
  enrichLead,
  findDecisionMakers,
  generateOutreach,
  markContacted,
  saveProspectingSettings,
  setLeadStatus,
  startSearch,
} from './prospecting-api';

/**
 * Every mutation the prospecting console can perform.
 *
 * Server actions rather than route handlers, like the rest of the portal: the
 * session cookie is read on the server and the ID token never reaches the
 * browser. There is no client-side fetch to the prospecting API at all.
 *
 * Each one revalidates the path it changed. Without that, an operator who
 * enriches a lead sees the old panel until they reload, and concludes the
 * button did nothing and presses it again — which, on these endpoints, costs
 * money.
 */

function text(form: FormData, key: string): string {
  const value = form.get(key);
  return typeof value === 'string' ? value.trim() : '';
}

function optionalText(form: FormData, key: string): string | null {
  const value = text(form, key);
  return value === '' ? null : value;
}

/* ------------------------------------------------------------- the search */

export async function startSearchAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const parsed = parseSearchForm(form);

  if (!parsed.ok) {
    // Keyed to the field, so a five-field form says which one is wrong.
    const fieldErrors: Record<string, string> = {};
    for (const error of parsed.errors) fieldErrors[error.field] = error.message;
    return {
      status: 'error',
      message: 'Corrija os campos assinalados.',
      values: snapshot(form),
      fieldErrors,
    };
  }

  try {
    const job = await startSearch({
      industries: parsed.values.industries,
      city: parsed.values.city,
      size: parsed.values.size,
      maxLeads: parsed.values.maxLeads,
      minScore: parsed.values.minScore,
    });

    revalidatePath('/admin/prospecao');
    return {
      status: 'ok',
      message: `Procura iniciada. ${job.progress_label}.`,
      result: { job_id: job.id },
    };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}

export async function cancelSearchAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const jobId = text(form, 'jobId');
  if (jobId === '') return failure(form, 'Trabalho não indicado.');

  try {
    await cancelSearch(jobId);
    revalidatePath('/admin/prospecao');
    return { status: 'ok', message: 'Procura cancelada.' };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}

/* --------------------------------------------------------- the lead actions */

export async function findDecisionMakersAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const prospectId = text(form, 'prospectId');
  if (prospectId === '') return failure(form, 'Lead não indicado.');

  try {
    const result = await findDecisionMakers(prospectId);
    revalidatePath(`/admin/prospecao/${prospectId}`);

    // A search that found nobody is reported as what it is. Calling it a
    // success would invite a retry at the same cost for the same answer.
    const message =
      result.decision_makers_found > 0
        ? `${result.decision_makers_found} decisor(es) encontrado(s).`
        : 'Nenhum decisor encontrado para este negócio.';

    return { status: 'ok', message, result: { ...result } };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}

export async function enrichLeadAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const prospectId = text(form, 'prospectId');
  if (prospectId === '') return failure(form, 'Lead não indicado.');

  try {
    const result = await enrichLead(prospectId);
    revalidatePath(`/admin/prospecao/${prospectId}`);
    return {
      status: 'ok',
      message: `Pesquisa concluída. Pontuação ${result.score}.`,
      result: { ...result },
    };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}

export async function analyzeLeadAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const prospectId = text(form, 'prospectId');
  if (prospectId === '') return failure(form, 'Lead não indicado.');

  const force = form.get('force') === 'on' || form.get('force') === 'true';

  try {
    const analysis = await analyzeLead(prospectId, force);
    revalidatePath(`/admin/prospecao/${prospectId}`);

    // Saying so matters: an operator who pressed "analisar" and saw nothing
    // change needs to know the answer was already there, not that the button
    // failed.
    const cached = analysis.from_cache === true;
    return {
      status: 'ok',
      message: cached
        ? 'Análise já existente — nada foi cobrado.'
        : 'Análise gerada.',
    };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}

export async function generateOutreachAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const prospectId = text(form, 'prospectId');
  const channel = text(form, 'channel');
  if (prospectId === '' || channel === '') {
    return failure(form, 'Indique o lead e o canal.');
  }

  try {
    const draft = await generateOutreach(prospectId, channel);
    revalidatePath(`/admin/prospecao/${prospectId}`);

    return {
      status: 'ok',
      message: draft.truncated
        ? 'Mensagem gerada, mas foi cortada no limite do canal. Reveja o fim antes de enviar.'
        : 'Mensagem gerada. Reveja antes de enviar.',
      // The draft is returned rather than stored on the page, so the copy
      // control has something to copy without a second round trip.
      result: { ...draft },
    };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}

export async function markContactedAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const prospectId = text(form, 'prospectId');
  const channel = text(form, 'channel');
  if (prospectId === '' || channel === '') {
    return failure(form, 'Indique o lead e o canal.');
  }

  try {
    await markContacted({
      prospectId,
      channel,
      note: optionalText(form, 'note'),
    });
    revalidatePath(`/admin/prospecao/${prospectId}`);
    revalidatePath('/admin/prospecao');
    return { status: 'ok', message: 'Registado como contactado.' };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}

export async function setLeadStatusAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const prospectId = text(form, 'prospectId');
  const status = text(form, 'status');
  if (prospectId === '' || status === '') {
    return failure(form, 'Indique o lead e o novo estado.');
  }

  try {
    await setLeadStatus({ prospectId, status, note: optionalText(form, 'note') });
    revalidatePath(`/admin/prospecao/${prospectId}`);
    revalidatePath('/admin/prospecao');
    return { status: 'ok', message: 'Estado atualizado.' };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}

/* ----------------------------------------------------------- the settings */

/**
 * A settings change.
 *
 * Only the fields that were sent are patched, and every one of them is parsed
 * rather than coerced: a monthly budget of `"cinquenta"` must not become zero,
 * which would silently turn paid enrichment off for the whole month.
 */
export async function saveProspectingSettingsAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const patch: Record<string, unknown> = {};
  const fieldErrors: Record<string, string> = {};

  const number = (key: string, label: string) => {
    const raw = text(form, key);
    if (raw === '') return;
    const parsed = Number(raw.replace(',', '.'));
    if (!Number.isFinite(parsed) || parsed < 0) {
      fieldErrors[key] = `${label} tem de ser um número.`;
      return;
    }
    patch[key] = parsed;
  };

  number('monthlyBudgetUsd', 'O orçamento mensal');
  number('dailyBudgetUsd', 'O orçamento diário');
  number('maxEnrichmentCostPerLeadUsd', 'O custo máximo por lead');
  number('minScoreForEnrichment', 'A pontuação mínima');
  number('maxProspectsPerSearch', 'O máximo por procura');

  const cities = text(form, 'cities');
  if (cities !== '') {
    patch.cities = cities
      .split(',')
      .map((entry) => entry.trim())
      .filter((entry) => entry !== '');
  }

  if (Object.keys(fieldErrors).length > 0) {
    return {
      status: 'error',
      message: 'Corrija os campos assinalados.',
      values: snapshot(form),
      fieldErrors,
    };
  }
  if (Object.keys(patch).length === 0) {
    return failure(form, 'Nada para guardar.');
  }

  try {
    await saveProspectingSettings(patch);
    revalidatePath('/admin/prospecao/definicoes');
    revalidatePath('/admin/prospecao');
    return { status: 'ok', message: 'Definições guardadas.' };
  } catch (caught) {
    if (caught instanceof AdminApiError) return apiFailure(caught, form);
    return describe(caught, form);
  }
}
