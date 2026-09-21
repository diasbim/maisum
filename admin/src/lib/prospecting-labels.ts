/**
 * What an operator reads, and the tone it is shown in.
 *
 * The API already sends a label with every coded value, and the console shows
 * that label — this file holds only what the API cannot decide: which colour a
 * status is, what an empty panel should say, and how a claim's provenance is
 * worded. Duplicating the labels themselves would be a second vocabulary to
 * keep in step; deciding the colour on the server would put presentation in
 * the contract.
 *
 * `merchant-labels.ts` keeps the same arrangement for the business area.
 */

export type Tone = 'green' | 'amber' | 'red' | 'navy';

/**
 * A pipeline status as a badge tone.
 *
 * Green is progress, amber is waiting on somebody, red is a stop. The two
 * compliance stops are red rather than neutral on purpose: they are the ones
 * an operator must not mistake for "not started".
 */
export function statusTone(status: string): Tone {
  switch (status) {
    case 'CUSTOMER':
    case 'TRIAL':
    case 'INTERESTED':
    case 'DEMO':
      return 'green';
    case 'CONTACTED':
    case 'REPLIED':
    case 'READY_TO_CONTACT':
      return 'amber';
    case 'DO_NOT_CONTACT':
    case 'OPTED_OUT':
    case 'NOT_A_FIT':
    case 'LOST':
      return 'red';
    default:
      return 'navy';
  }
}

/** A score band as a tone. Mirrors the bands in the scoring configuration. */
export function bandTone(band: string | null): Tone {
  switch (band) {
    case 'PRIORITY':
      return 'green';
    case 'GOOD':
      return 'amber';
    case 'LOW_FIT':
      return 'red';
    default:
      return 'navy';
  }
}

/**
 * The enrichment state as a tone.
 *
 * `BUDGET_BLOCKED` is amber, not red. Nothing went wrong: the cap did its job,
 * and showing it as an error would send an operator looking for a fault that
 * does not exist.
 */
export function enrichmentTone(status: string): Tone {
  switch (status) {
    case 'COMPLETE':
      return 'green';
    case 'PARTIAL':
    case 'IN_PROGRESS':
    case 'BUDGET_BLOCKED':
      return 'amber';
    case 'FAILED':
      return 'red';
    default:
      return 'navy';
  }
}

/**
 * How a claim was arrived at, in words.
 *
 * The distinction between a fact and an inference is the module's central
 * discipline, and it has to survive into the sentence an operator reads before
 * they repeat it to a customer. "Observado" and "Dedução" are deliberately not
 * synonyms.
 */
export function claimLabel(type: string): string {
  switch (type) {
    case 'FACT':
      return 'Observado';
    case 'INFERENCE':
      return 'Dedução';
    default:
      return 'Desconhecido';
  }
}

export function claimTone(type: string): Tone {
  return type === 'FACT' ? 'green' : 'amber';
}

/**
 * What an empty leads list should say.
 *
 * Three different empties, because the way out of each is different: run a
 * search, clear the filter, or wait for the one that is running. A single
 * "sem resultados" leaves the operator to work out which of the three they are
 * looking at.
 */
export function emptyLeadsMessage(input: {
  filtered: boolean;
  jobRunning: boolean;
}): string {
  if (input.jobRunning) {
    return 'A procura está a correr. Os negócios aparecem aqui à medida que são encontrados.';
  }
  if (input.filtered) {
    return 'Nenhum lead corresponde a estes filtros.';
  }
  return 'Ainda não há leads. Comece por procurar negócios.';
}

/**
 * What the enrichment panel says when it has nothing.
 *
 * `NO_RESULT` is the common case and it is not a failure — most small
 * businesses in Maputo have no findable decision maker, and an operator who
 * reads this as an error will keep retrying it at cost.
 */
export function enrichmentEmptyMessage(status: string): string {
  switch (status) {
    case 'NO_RESULT':
      return 'Não foi encontrado nenhum decisor para este negócio. Isto é comum e não é um erro — o contacto do negócio continua utilizável.';
    case 'BUDGET_BLOCKED':
      return 'O orçamento de prospeção foi atingido, por isso o enriquecimento pago está em pausa. Nada foi cobrado por este lead.';
    case 'BELOW_THRESHOLD':
      return 'Este lead está abaixo da pontuação mínima para enriquecimento pago. Suba a pontuação mínima nas definições, ou enriqueça outro lead.';
    case 'FAILED':
      return 'O enriquecimento falhou. Pode tentar de novo.';
    case 'NOT_STARTED':
      return 'Ainda não foi procurado nenhum decisor para este negócio.';
    default:
      return 'Sem decisores registados.';
  }
}

/**
 * Whether a lead should carry the "already a customer" warning, and what it
 * says.
 *
 * Two different things wear this: a prospect the system closed as
 * `EXISTING_CUSTOMER` because a phone matched, and one merely *suspected* by
 * name. The second needs a person to decide, and the wording has to make that
 * clear rather than stating it as a fact.
 */
export function customerWarning(input: {
  status: string;
  suspectedMerchantId: string | null;
}): { tone: Tone; text: string } | null {
  if (input.status === 'EXISTING_CUSTOMER') {
    return {
      tone: 'red',
      text: 'Este negócio já é cliente MaisUm — o telefone coincide com um negócio registado. Está fora da aquisição.',
    };
  }

  if (input.suspectedMerchantId !== null) {
    return {
      tone: 'amber',
      text: 'O nome deste negócio coincide com o de um cliente MaisUm. Confirme antes de contactar: pode ser o mesmo negócio, ou apenas o mesmo nome.',
    };
  }

  return null;
}

/**
 * A relative time, for the timeline.
 *
 * Coarse on purpose. "há 3 dias" is what an operator needs to know about a
 * lead's last activity; the exact minute is noise, and it is in the tooltip.
 */
export function relativeTime(millis: number | null, nowMillis: number): string {
  if (millis === null || !Number.isFinite(millis)) return '—';

  const delta = nowMillis - millis;
  if (delta < 0) return 'agora';

  const minutes = Math.floor(delta / 60_000);
  if (minutes < 1) return 'agora';
  if (minutes < 60) return `há ${minutes} min`;

  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `há ${hours} h`;

  const days = Math.floor(hours / 24);
  if (days < 31) return `há ${days} ${days === 1 ? 'dia' : 'dias'}`;

  const months = Math.floor(days / 30);
  return `há ${months} ${months === 1 ? 'mês' : 'meses'}`;
}

/**
 * The share of the monthly budget that is gone, as a percentage.
 *
 * Clamped to a hundred: a month that overshot its cap by a rounding error
 * should not render a bar wider than its track.
 */
export function budgetUsedPercent(spent: number, budget: number): number {
  if (!Number.isFinite(budget) || budget <= 0) return 0;
  return Math.max(0, Math.min(100, Math.round((spent / budget) * 100)));
}
