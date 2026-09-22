/**
 * One real prospecting run against Google Places, end to end, no Firestore.
 *
 * Discovery -> dedup -> qualify -> score -> the spend gate -> listing details
 * -> a second dedup on what those details revealed. The same functions the
 * pipeline calls, in the same order, over the real API — so what it prints is
 * what the product would have stored.
 *
 * Deliberately does not write to Firestore. The point is to see the numbers a
 * real campaign produces before one is run for real, and a harness that also
 * wrote would make "try it once" an act with consequences. It does write a
 * details cache, which is the opposite: it exists so that trying it twice is
 * free.
 *
 * It spends money. Hence the caps below, the running tally, and `--dry-run`.
 *
 *   GOOGLE_PLACES_API_KEY=... node scripts/prospecting_live_run.mjs
 *   ... node scripts/prospecting_live_run.mjs --dry-run
 *   ... node scripts/prospecting_live_run.mjs --city Matola --industry salon --max-spend 0.10
 *
 * Run it from `functions/`, after `npm run build`.
 */

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { PlacesProvider } from '../lib/prospecting_provider_places.js';
import {
  DEFAULT_GEOGRAPHY,
  DEFAULT_SCORING,
  DEFAULT_SETTINGS,
  OPERATION_COST_USD,
} from '../lib/prospecting_config.js';
import {
  compareForRank,
  meanRatingOf,
  qualify,
  scoreProspect,
  UNKNOWN_SIGNALS,
} from '../lib/prospecting_scoring.js';
import {
  dedupeCandidates,
  DUPLICATE_REASON_LABEL,
  SeenContacts,
} from '../lib/prospecting_dedup.js';
import { normalizeDomain, normalizePhone } from '../lib/prospecting_normalization.js';
import { operationalFrom } from '../lib/prospecting_pipeline.js';
import { DetailCache, EMPTY_CACHE } from '../lib/prospecting_detail_cache.js';

/* ------------------------------------------------------------------- args */

function arg(name, fallback) {
  const at = process.argv.indexOf(`--${name}`);
  return at === -1 ? fallback : (process.argv[at + 1] ?? fallback);
}

const flag = (name) => process.argv.includes(`--${name}`);

const CITY = arg('city', 'Maputo');
const INDUSTRY = arg('industry', 'barbershop');
const PAGE_SIZE = Number(arg('page-size', '20'));
const MAX_DETAILS = Number(arg('max-details', '5'));

/**
 * The hard ceiling for the run, in dollars.
 *
 * Checked before each paid call, not after. A cap that is noticed once it has
 * been crossed is a report, not a control.
 */
const MAX_SPEND = Number(arg('max-spend', '0.20'));
const DRY_RUN = flag('dry-run');
const CACHE_TTL_DAYS = Number(arg('cache-ttl-days', '30'));
const NO_CACHE = flag('no-cache');

/**
 * Replay the recorded Maputo run instead of calling Google.
 *
 * So that the arithmetic this harness exists to show — what deduplication and
 * the gate save — can be demonstrated and re-checked without paying for it
 * again, and without needing a key at all.
 */
const FIXTURE = flag('fixture');

const key = process.env.GOOGLE_PLACES_API_KEY;
if (!FIXTURE && (!key || key.trim() === '')) {
  console.error('GOOGLE_PLACES_API_KEY não está definida. Nada foi chamado.');
  console.error('Para ver a aritmética sem chave e sem custo: --fixture --dry-run');
  process.exit(1);
}

/* ------------------------------------------------------------------ cache */

const HERE = dirname(fileURLToPath(import.meta.url));
const CACHE_PATH = join(HERE, '.cache', 'places_details.json');

/**
 * Details already paid for, keyed by place id.
 *
 * Google permits the place id to be stored indefinitely; the fields beside it
 * are cached for a TTL because a phone number goes stale. Keyed by place id
 * and not by name, because the name is the thing that varies.
 */
function loadCacheData() {
  if (NO_CACHE) return EMPTY_CACHE;
  try {
    const raw = JSON.parse(readFileSync(CACHE_PATH, 'utf8'));
    return {
      byPlaceId: raw.byPlaceId ?? {},
      phoneToPlaceId: raw.phoneToPlaceId ?? {},
    };
  } catch {
    return EMPTY_CACHE;
  }
}

const cache = new DetailCache(loadCacheData(), { ttlDays: CACHE_TTL_DAYS });

function saveCache() {
  if (NO_CACHE) return;
  try {
    mkdirSync(dirname(CACHE_PATH), { recursive: true });
    writeFileSync(CACHE_PATH, JSON.stringify(cache.snapshot(), null, 2), 'utf8');
  } catch (error) {
    console.error(`   (não foi possível gravar a cache: ${error.message})`);
  }
}

/* ------------------------------------------------------------------ setup */

const places =
  key && key.trim() !== ''
    ? new PlacesProvider({
        apiKey: key,
        searchCostUsd: OPERATION_COST_USD.SEARCH_BUSINESSES,
        detailCostUsd: OPERATION_COST_USD.FETCH_LISTING_DETAILS,
      })
    : null;

const settings = DEFAULT_SETTINGS;
const DETAIL_COST = OPERATION_COST_USD.FETCH_LISTING_DETAILS;

let spent = 0;

const charge = (usd, what) => {
  spent += usd;
  console.log(`   💸 ${what}: $${usd.toFixed(3)} · acumulado $${spent.toFixed(3)}`);
};

/** Whether one more paid call fits. Asked before the call, never after. */
const affords = (usd) => spent + usd <= MAX_SPEND + 1e-9;

const pad = (value, width) => String(value).padEnd(width);
const money = (usd) => `$${usd.toFixed(3)}`;

/* -------------------------------------------------------------- the run */

console.log('═'.repeat(78));
console.log(
  `CORRIDA ${DRY_RUN ? 'SIMULADA' : 'REAL'} · ${INDUSTRY} em ${CITY} · ` +
    `limiar ${settings.minScoreForEnrichment} · tecto ${money(MAX_SPEND)}`,
);
console.log('═'.repeat(78));

if (DRY_RUN) {
  console.log('\n⚠ --dry-run: o estágio 2 não é chamado. Nada é pago por detalhes.');
}

/* --------------------------------------------------- estágio 1: descoberta */

console.log('\n■ ESTÁGIO 1 — pesquisa (campos baratos)\n');

async function explainFailure() {
  try {
    const probe = await fetch('https://places.googleapis.com/v1/places:searchText', {
      method: 'POST',
      headers: {
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': 'places.id',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ textQuery: 'teste' }),
    });
    const detail = await probe.json().catch(() => null);
    const error = detail?.error ?? {};
    console.error('');
    console.error(`   Google respondeu HTTP ${probe.status} ${error.status ?? ''}`);
    if (error.message) console.error(`   "${error.message}"`);
    for (const item of error.details ?? []) {
      if (item.reason) console.error(`   motivo ..... ${item.reason}`);
      if (item.metadata?.service) console.error(`   serviço .... ${item.metadata.service}`);
    }
  } catch (probeError) {
    console.error(`   Não foi possível obter a mensagem: ${probeError.message}`);
  }
}

let found;
if (FIXTURE) {
  const { MAPUTO_RUN } = await import('../lib/prospecting_dedup_fixture.js');
  found = MAPUTO_RUN.map((row) => ({
    company: {
      name: row.name,
      industry: 'barbershop',
      city: CITY,
      province: 'Maputo',
      country: DEFAULT_GEOGRAPHY.country,
      website: null,
      phone: null,
      rating: row.rating,
      review_count: row.reviewCount,
      has_opening_hours: null,
      has_photos: null,
      business_status: 'OPERATIONAL',
      latitude: row.latitude,
      longitude: row.longitude,
      source_reference: row.sourceReference,
    },
  }));
  // The recorded run's own search call, so the tally starts where it did.
  spent += OPERATION_COST_USD.SEARCH_BUSINESSES;
  console.log(
    `   (--fixture: a corrida gravada de Maputo, sem chamar a Google) ` +
      `pesquisa ${money(OPERATION_COST_USD.SEARCH_BUSINESSES)}`,
  );
} else {
try {
  if (places === null) throw new Error('sem chave');
  if (!affords(OPERATION_COST_USD.SEARCH_BUSINESSES)) {
    console.error(`✗ O tecto de ${money(MAX_SPEND)} não cobre sequer a pesquisa.`);
    process.exit(1);
  }
  found = await places.searchBusinesses({
    industries: [INDUSTRY],
    city: CITY,
    province: null,
    country: DEFAULT_GEOGRAPHY.country,
    employeeMin: null,
    employeeMax: null,
    limit: PAGE_SIZE,
    cursor: null,
  });
} catch (error) {
  console.error('');
  console.error(
    `✗ A pesquisa falhou: ${error.code ?? 'ERRO'} (${error.detail ?? error.message})`,
  );
  if (error.code === 'NOT_CONFIGURED') {
    console.error('');
    console.error('   A chave foi enviada — o arranque já a tinha validado.');
    console.error('   Um 403 aqui é a Google a recusá-la, não a sua ausência.');
  }
  await explainFailure();
  process.exit(1);
}
charge(places.lastCostUsd ?? 0, 'pesquisa');
}

console.log(`   ${found.length} negócios devolvidos\n`);

if (found.length === 0) {
  console.log('Nada encontrado. Experimente outra cidade ou setor.');
  process.exit(0);
}

/* --------------------------------------------------------- deduplicação 1 */

const { kept, duplicates } = dedupeCandidates(
  found.map(({ company }) => ({
    sourceReference: company.source_reference,
    name: company.name,
    reviewCount: company.review_count,
    latitude: company.latitude,
    longitude: company.longitude,
    company,
  })),
  { radiusMetres: settings.dedupRadiusMetres },
);

console.log('■ DEDUPLICAÇÃO (grátis, antes de pagar seja o que for)\n');
console.log(`   ${found.length} listagens → ${kept.length} negócios distintos`);
if (duplicates.length > 0) {
  console.log(`   ${duplicates.length} copias descartadas antes do estágio 2\n`);
} else {
  console.log('   nenhuma cópia encontrada\n');
}

/* ------------------------------------------- qualificação e pontuação */

console.log('■ QUALIFICAÇÃO E PONTUAÇÃO (grátis)\n');

const meanRating = meanRatingOf(kept.map((entry) => ({ rating: entry.company.rating })));
const scoreContext = {
  meanRating,
  priorCount: settings.bayesianPriorCount,
  noRatingPenalty: settings.noRatingPenalty,
};
console.log(
  `   média da corrida: ${meanRating === null ? '—' : meanRating.toFixed(2)} · ` +
    `prior m=${settings.bayesianPriorCount} · penalização sem avaliação: ${settings.noRatingPenalty}\n`,
);
console.log(
  `   ${pad('NEGÓCIO', 34)}${pad('AVAL.', 7)}${pad('REV.', 6)}${pad('POND.', 7)}${pad('PONTOS', 8)}BANDA`,
);
console.log('   ' + '─'.repeat(78));

const scored = [];
const rejected = [];

for (const entry of kept) {
  const company = entry.company;
  const verdict = qualify(
    {
      name: company.name,
      businessType: company.industry,
      city: company.city,
      province: company.province,
      country: company.country,
    },
    settings.geography,
  );

  if (!verdict.qualified) {
    rejected.push({ name: company.name, reason: verdict.reason });
    continue;
  }

  const signals = {
    ...UNKNOWN_SIGNALS,
    businessType: company.industry,
    city: company.city,
    province: company.province,
    country: company.country,
    websiteUrl: company.website,
    hasContactChannel: company.phone !== null,
    reachableContact: company.phone !== null,
    rating: company.rating,
    reviewCount: company.review_count,
    hasOpeningHours: company.has_opening_hours,
    hasPhotos: company.has_photos,
    isOperational: operationalFrom(company.business_status),
  };

  const score = scoreProspect(signals, DEFAULT_SCORING, settings.geography, scoreContext);

  if (score.total <= settings.minScoreForEnrichment) {
    rejected.push({
      name: company.name,
      reason:
        score.evidencePenalty > 0
          ? `${score.total} pontos — sem avaliações (−${score.evidencePenalty})`
          : `${score.total} pontos, não passa ${settings.minScoreForEnrichment}`,
    });
    continue;
  }

  scored.push({ company, score, signals });

  console.log(
    `   ${pad(company.name.slice(0, 32), 34)}` +
      `${pad(company.rating ?? '—', 7)}` +
      `${pad(company.review_count ?? '—', 6)}` +
      `${pad(score.bayesianRating === null ? '—' : score.bayesianRating.toFixed(2), 7)}` +
      `${pad(score.total, 8)}${score.band}`,
  );
}

scored.sort((left, right) =>
  compareForRank(
    {
      score: left.score.total,
      reviewCount: left.company.review_count,
      rating: left.company.rating,
      name: left.company.name,
    },
    {
      score: right.score.total,
      reviewCount: right.company.review_count,
      rating: right.company.rating,
      name: right.company.name,
    },
  ),
);

/* ----------------------------------------------------------- o portão */

console.log('\n■ O PORTÃO DE CUSTO\n');
console.log(`   descobertos ............ ${found.length}`);
console.log(`   cópias do mesmo negócio  ${duplicates.length}  ← nunca chegam a ser pagas`);
console.log(`   recusados ............... ${rejected.length}`);
console.log(`   acima do limiar ......... ${scored.length}  ← só estes pagam o 2.º estágio`);

if (rejected.length > 0) {
  console.log('\n   Porquê:');
  for (const entry of rejected) {
    console.log(`     ${pad(entry.name.slice(0, 32), 34)}${entry.reason}`);
  }
}

console.log(
  `\n   Sem portão nem dedup, ${found.length} detalhes custariam ` +
    `${money(found.length * DETAIL_COST)}.`,
);

/* ---------------------------------------------------- estágio 2: detalhes */

const planned = scored.slice(0, MAX_DETAILS);

if (DRY_RUN) {
  /**
   * How many of the planned calls the ceiling actually pays for.
   *
   * The plan is only useful if it is the plan the real run would follow. A
   * dry run that lists eight businesses and a total above `--max-spend`,
   * while the real run would stop at five, is not a preview — it is a
   * different answer to the same question, and the operator finds out which
   * one was right by spending money.
   */
  const affordable = Math.max(0, Math.floor((MAX_SPEND - spent) / DETAIL_COST));
  const willRun = planned.slice(0, affordable);
  const cutOff = planned.slice(affordable);

  console.log(`\n■ ESTÁGIO 2 PLANEADO (não executado) · ${willRun.length} negócios\n`);
  for (const entry of willRun) {
    console.log(
      `   ${pad(entry.company.name.slice(0, 40), 42)}${entry.score.total} pts · ${entry.score.band}`,
    );
  }

  if (cutOff.length > 0) {
    console.log(`\n   ⛔ Fora do tecto de ${money(MAX_SPEND)} — não seriam consultados:\n`);
    for (const entry of cutOff) {
      console.log(
        `   ${pad(entry.company.name.slice(0, 40), 42)}${entry.score.total} pts`,
      );
    }
    console.log(`\n   Suba --max-spend para ${money(spent + planned.length * DETAIL_COST)} para os incluir.`);
  }

  const estimate = willRun.length * DETAIL_COST;
  console.log(`\n   Custo estimado do estágio 2: ${money(estimate)}`);
  console.log(`   Já gasto na pesquisa ......: ${money(spent)}`);
  console.log(`   Total previsto ............: ${money(spent + estimate)}  (tecto ${money(MAX_SPEND)})`);
} else {
  console.log(
    `\n■ ESTÁGIO 2 — ficha do negócio (campos caros) · até ${planned.length} de ${scored.length}\n`,
  );

  const seen = new SeenContacts();
  const postDuplicates = [];
  /** The ranked leads not yet in a slot, used to refill one a duplicate frees. */
  const queue = scored.slice(MAX_DETAILS);
  let slots = planned.slice();
  let index = 0;
  let paid = 0;

  while (index < slots.length) {
    const entry = slots[index];
    index++;
    const { company, signals, score } = entry;
    console.log(`   ${company.name}`);

    const placeId = company.source_reference;
    let detail = cache.get(placeId);

    if (detail !== null) {
      console.log(`     ♻ em cache — nada foi pago`);
    } else {
      if (!affords(DETAIL_COST)) {
        console.log(
          `     ⛔ tecto de ${money(MAX_SPEND)} atingido — a corrida pára aqui, ` +
            `com ${slots.length - index + 1} por consultar\n`,
        );
        break;
      }
      try {
        detail = await places.fetchListingDetail({ reference: placeId });
        charge(places.lastCostUsd ?? 0, 'detalhes');
        paid++;
        cache.put(placeId, detail, normalizePhone(detail.phone, DEFAULT_GEOGRAPHY.country));
      } catch (error) {
        console.log(`     ✗ ${error.code ?? 'ERRO'}: ${error.detail ?? error.message}\n`);
        continue;
      }
    }

    const phone = normalizePhone(detail.phone, DEFAULT_GEOGRAPHY.country);
    const domain = normalizeDomain(detail.website);
    const repeat = seen.observe({ phone, domain });

    if (repeat.duplicate) {
      postDuplicates.push({
        name: company.name,
        reason: repeat.by === 'phone' ? 'mesmo telefone' : 'mesmo domínio',
      });
      console.log(
        `     ⚠ duplicado revelado pela ficha (${repeat.by === 'phone' ? 'telefone' : 'domínio'})`,
      );
      // The call is bought and cannot be returned. The next one can go to a
      // different business instead, which is the only part still in hand.
      const replacement = queue.shift();
      if (replacement !== undefined && affords(DETAIL_COST)) {
        slots.push(replacement);
        console.log(`     ↻ promovido para o lugar livre: ${replacement.company.name}\n`);
      } else {
        console.log('');
      }
      continue;
    }

    const rescored = scoreProspect(
      {
        ...signals,
        websiteUrl: detail.website ?? signals.websiteUrl,
        hasContactChannel: detail.phone !== null || signals.hasContactChannel,
        reachableContact: detail.phone !== null,
        hasOpeningHours: detail.hasOpeningHours,
        hasPhotos: detail.hasPhotos,
      },
      DEFAULT_SCORING,
      settings.geography,
      scoreContext,
    );

    console.log(`     telefone ... ${detail.phone ?? '—'}`);
    console.log(`     site ....... ${detail.website ?? '—'}`);
    console.log(`     horário .... ${detail.hasOpeningHours ? 'sim' : 'não'}`);
    console.log(`     fotografias  ${detail.hasPhotos ? 'sim' : 'não'}`);
    console.log(
      `     pontuação .. ${score.total} → ${rescored.total} (${rescored.band})` +
        `${detail.phone !== null ? '  → PRONTO A CONTACTAR' : '  → parcial, sem telefone'}`,
    );
    if (rescored.unknowns.length > 0) {
      console.log(`     por saber .. ${rescored.unknowns.join(', ')}`);
    }
    console.log();
  }

  if (postDuplicates.length > 0) {
    duplicates.push(
      ...postDuplicates.map((entry) => ({
        candidate: { name: entry.name },
        duplicateOf: { name: '—' },
        reason: entry.reason,
      })),
    );
  }

  saveCache();
  void paid;
}

/* --------------------------------------------------- duplicados ignorados */

if (duplicates.length > 0) {
  console.log('\n■ DUPLICADOS IGNORADOS\n');
  console.log(`   ${pad('NEGÓCIO', 34)}${pad('MOTIVO', 34)}FUNDIDO EM`);
  console.log('   ' + '─'.repeat(74));
  for (const entry of duplicates) {
    const reason = DUPLICATE_REASON_LABEL[entry.reason] ?? entry.reason;
    console.log(
      `   ${pad(entry.candidate.name.slice(0, 32), 34)}` +
        `${pad(reason.slice(0, 32), 34)}` +
        `${entry.duplicateOf.name}`,
    );
  }
}

/* ------------------------------------------------------------- a conta */

const avoidedByDedup = duplicates.length;
const savedUsd = (avoidedByDedup + cache.hits) * DETAIL_COST;

console.log('\n■ POUPANÇA\n');
console.log(`   cópias nunca consultadas ... ${avoidedByDedup}`);
console.log(`   respostas vindas da cache .. ${cache.hits}`);
console.log(
  `   chamadas evitadas .......... ${avoidedByDedup + cache.hits} × ${money(DETAIL_COST)} = ${money(savedUsd)}`,
);

console.log('\n' + '═'.repeat(78));
console.log(
  `${DRY_RUN ? 'GASTO ATÉ AQUI' : 'GASTO REAL DESTA CORRIDA'}: ${money(spent)}` +
    `   (tecto ${money(MAX_SPEND)})`,
);
console.log('Estimativas não verificadas contra fatura — ver ESTIMATES_VERIFIED.');
console.log('═'.repeat(78));
