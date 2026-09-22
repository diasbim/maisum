/**
 * One real prospecting run against Google Places, end to end, no Firestore.
 *
 * Discovery -> qualify -> score -> the spend gate -> listing details ->
 * re-score. The same functions the pipeline calls, in the same order, over the
 * real API — so what it prints is what the product would have stored.
 *
 * Deliberately does not write anything. The point is to see the numbers a real
 * campaign produces before one is run for real, and a harness that also wrote
 * to Firestore would make "try it once" an act with consequences.
 *
 * It spends money. That is the whole reason for the caps below and for the
 * running tally it prints: every paid call is counted as it happens, so the
 * bill is visible while it is being incurred rather than afterwards.
 *
 *   GOOGLE_PLACES_API_KEY=... node scripts/prospecting_live_run.mjs
 *   GOOGLE_PLACES_API_KEY=... node scripts/prospecting_live_run.mjs --city Matola --industry salon --max-details 3
 *
 * Run it from `functions/`, after `npm run build`.
 */

import { PlacesProvider } from '../lib/prospecting_provider_places.js';
import {
  DEFAULT_GEOGRAPHY,
  DEFAULT_SCORING,
  DEFAULT_SETTINGS,
  OPERATION_COST_USD,
  findIcpIndustry,
} from '../lib/prospecting_config.js';
import { qualify, scoreProspect, UNKNOWN_SIGNALS } from '../lib/prospecting_scoring.js';
import { operationalFrom } from '../lib/prospecting_pipeline.js';

/* ------------------------------------------------------------------- args */

function arg(name, fallback) {
  const at = process.argv.indexOf(`--${name}`);
  return at === -1 ? fallback : (process.argv[at + 1] ?? fallback);
}

const CITY = arg('city', 'Maputo');
const INDUSTRY = arg('industry', 'barbershop');
const PAGE_SIZE = Number(arg('page-size', '20'));
/**
 * How many businesses the second, dearer call is made for.
 *
 * Low on purpose. The gate is what this run exists to demonstrate, and
 * demonstrating it does not require paying for every lead that passes.
 */
const MAX_DETAILS = Number(arg('max-details', '5'));

const key = process.env.GOOGLE_PLACES_API_KEY;
if (!key || key.trim() === '') {
  console.error('GOOGLE_PLACES_API_KEY não está definida. Nada foi chamado.');
  process.exit(1);
}

/* ------------------------------------------------------------------ setup */

const places = new PlacesProvider({
  apiKey: key,
  searchCostUsd: OPERATION_COST_USD.SEARCH_BUSINESSES,
  detailCostUsd: OPERATION_COST_USD.FETCH_LISTING_DETAILS,
});

const settings = DEFAULT_SETTINGS;
let spent = 0;
const charge = (usd, what) => {
  spent += usd;
  console.log(`   💸 ${what}: $${usd.toFixed(3)} · acumulado $${spent.toFixed(3)}`);
};

const pad = (value, width) => String(value).padEnd(width);
const money = (usd) => `$${usd.toFixed(3)}`;

/* -------------------------------------------------------------- the run */

console.log('═'.repeat(78));
console.log(`CORRIDA REAL · ${INDUSTRY} em ${CITY} · limiar ${settings.minScoreForEnrichment}`);
console.log('═'.repeat(78));

/* --------------------------------------------------- estágio 1: descoberta */

console.log('\n■ ESTÁGIO 1 — pesquisa (campos baratos)\n');

/**
 * O que a Google respondeu, por extenso.
 *
 * O fornecedor deixa o corpo de fora do erro de propósito — pode nomear o
 * negócio pesquisado, e isso não pertence a um log de produção. Aqui não há
 * log de produção nenhum, e sem a mensagem um 403 não se distingue de outro:
 * chave restrita a um referrer, API por activar, facturação em falta e chave
 * errada chegam todos como o mesmo número.
 */
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
try {
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

console.log(`   ${found.length} negócios devolvidos\n`);

if (found.length === 0) {
  console.log('Nada encontrado. Experimente outra cidade ou setor.');
  process.exit(0);
}

/* ------------------------------------------- qualificação e pontuação */

console.log('■ QUALIFICAÇÃO E PONTUAÇÃO (grátis)\n');
console.log(
  `   ${pad('NEGÓCIO', 34)}${pad('AVAL.', 7)}${pad('REV.', 6)}${pad('PONTOS', 8)}BANDA`,
);
console.log('   ' + '─'.repeat(70));

const scored = [];
let rejected = 0;

for (const { company } of found) {
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
    rejected++;
    console.log(`   ${pad(company.name.slice(0, 32), 34)}— recusado: ${verdict.reason}`);
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

  const score = scoreProspect(signals, DEFAULT_SCORING, settings.geography);
  scored.push({ company, score, signals });

  console.log(
    `   ${pad(company.name.slice(0, 32), 34)}` +
      `${pad(company.rating ?? '—', 7)}` +
      `${pad(company.review_count ?? '—', 6)}` +
      `${pad(score.total, 8)}${score.band}`,
  );
}

scored.sort((left, right) => right.score.total - left.score.total);

/* ----------------------------------------------------------- o portão */

const passing = scored.filter(
  (entry) => entry.score.total >= settings.minScoreForEnrichment,
);
const below = scored.length - passing.length;

console.log('\n■ O PORTÃO DE CUSTO\n');
console.log(`   descobertos ............ ${found.length}`);
console.log(`   recusados na qualificação ${rejected}`);
console.log(`   abaixo do limiar ....... ${below}  ← custo zero, nunca são pagos`);
console.log(`   acima do limiar ........ ${passing.length}  ← só estes pagam o 2.º estágio`);
console.log(
  `\n   Sem o portão, ${found.length} detalhes custariam ` +
    `${money(found.length * OPERATION_COST_USD.FETCH_LISTING_DETAILS)}.` +
    `\n   Com o portão: ${money(passing.length * OPERATION_COST_USD.FETCH_LISTING_DETAILS)}.`,
);

/* ---------------------------------------------------- estágio 2: detalhes */

const toEnrich = passing.slice(0, MAX_DETAILS);
console.log(
  `\n■ ESTÁGIO 2 — ficha do negócio (campos caros) · ${toEnrich.length} de ${passing.length}\n`,
);

for (const entry of toEnrich) {
  const { company, signals, score } = entry;
  console.log(`   ${company.name}`);

  let detail;
  try {
    detail = await places.fetchListingDetail({ reference: company.source_reference });
    charge(places.lastCostUsd ?? 0, 'detalhes');
  } catch (error) {
    console.log(`     ✗ ${error.code ?? 'ERRO'}: ${error.detail ?? error.message}\n`);
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

/* ------------------------------------------------------------- a conta */

console.log('═'.repeat(78));
console.log(`GASTO REAL DESTA CORRIDA: ${money(spent)}`);
console.log(
  `Estimativas não verificadas contra fatura — ver ESTIMATES_VERIFIED.`,
);
console.log('═'.repeat(78));
