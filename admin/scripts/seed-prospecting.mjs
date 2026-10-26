/**
 * Development data for the prospecting console.
 *
 *   node scripts/seed-prospecting.mjs
 *
 * Twenty companies, ten decision makers, twenty prospects spread across the
 * pipeline, activity trails and a month of enrichment costs. Enough that every
 * screen has something on it and every empty state is reachable by filtering.
 *
 * Everything here is fictional, and visibly so. Domains are under `.test`,
 * which RFC 2606 reserves precisely so it can never resolve; phone numbers are
 * in a block that is not issued; the people are invented names attached to
 * businesses that do not exist. Nothing here is, or may become, the contact
 * detail of a real person or a real business in Maputo.
 *
 * It cannot reach production. The emulator host is set here rather than read
 * from the environment, and asserted to be loopback, so an unset variable
 * fails to connect instead of quietly writing to the real project.
 */

import admin from 'firebase-admin';
import { createHash, randomUUID } from 'node:crypto';

const FIRESTORE_EMULATOR = '127.0.0.1:8085';
const PROJECT_ID = 'loyaltyos-fc4dd';

function assertLoopback(host, name) {
  const hostname = host.split(':')[0];
  if (hostname !== '127.0.0.1' && hostname !== 'localhost' && hostname !== '::1') {
    throw new Error(
      `${name} is ${hostname}, which is not this machine. This script only ` +
        'ever writes to the emulators; refusing to run.',
    );
  }
}

assertLoopback(FIRESTORE_EMULATOR, 'firestore emulator');
process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR;

if (admin.apps.length === 0) admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

const NOW = Date.now();
const DAY = 86_400_000;

/* ------------------------------------------------------------ the fixtures */

/**
 * The same twenty businesses the fixture provider serves.
 *
 * Kept in step by hand rather than imported: this script runs against the
 * emulator with no build step, and the fixture module is TypeScript. The
 * seeded ids match, so a seeded lead and a discovered one are the same record.
 */
const COMPANIES = [
  ['fx-org-001', 'Barbearia Exemplo Central', 'barbershop', 'Maputo', 6, 'barbearia-exemplo.test', '+258840000101', ['ig', 'fb']],
  ['fx-org-002', 'Salão Exemplo Beleza', 'salon', 'Matola', 4, null, '+258840000102', ['ig']],
  ['fx-org-003', 'Spa Exemplo Bem-Estar', 'spa', 'Maputo', 12, 'spa-exemplo.test', '+258210000103', ['ig', 'li']],
  ['fx-org-004', 'Ginásio Exemplo Forma', 'gym', 'Maputo', 18, 'ginasio-exemplo.test', '+258840000104', ['ig', 'fb']],
  ['fx-org-005', 'Lavagem Auto Exemplo', 'car_wash', 'Matola', null, null, '+258840000105', ['fb']],
  ['fx-org-006', 'Restaurante Exemplo Sabor', 'restaurant', 'Maputo', 22, 'restaurante-exemplo.test', '+258210000106', ['ig', 'fb']],
  ['fx-org-007', 'Café Exemplo Aroma', 'cafe', 'Maputo', 5, null, null, ['ig']],
  ['fx-org-008', 'Barbearia Exemplo Matola', 'barbershop', 'Matola', 3, 'barbearia-matola-exemplo.test', '+258840000108', []],
  ['fx-org-009', 'Salão Exemplo Estilo', 'salon', 'Maputo', 8, null, '+258840000109', ['ig', 'fb']],
  ['fx-org-010', 'Clínica Exemplo Estética', 'spa', 'Maputo', 15, 'clinica-exemplo.test', '+258210000110', ['li']],
  ['fx-org-011', 'Ginásio Exemplo Matola', 'gym', 'Matola', null, null, '+258840000111', ['fb']],
  ['fx-org-012', 'Café Exemplo Matola', 'cafe', 'Matola', 7, null, '+258840000112', ['ig']],
  ['fx-org-013', 'Lavagem Exemplo Rápida', 'car_wash', 'Maputo', 9, 'lavagem-exemplo.test', '+258840000113', ['ig', 'fb']],
  ['fx-org-014', 'Restaurante Exemplo Matola', 'restaurant', 'Matola', 30, null, '+258840000114', ['fb']],
  ['fx-org-015', 'Barbearia Exemplo Bairro', 'barbershop', 'Maputo', 2, null, null, []],
  ['fx-org-016', 'Spa Exemplo Matola', 'spa', 'Matola', 6, null, '+258840000116', ['ig']],
  ['fx-org-017', 'Salão Exemplo Nova Imagem', 'salon', 'Maputo', 11, 'nova-imagem-exemplo.test', '+258840000117', ['ig', 'fb']],
  ['fx-org-018', 'Oficina Exemplo Motor', 'workshop', 'Maputo', 14, null, '+258840000118', []],
  ['fx-org-019', 'Barbearia Exemplo Beira', 'barbershop', 'Beira', 5, null, '+258840000119', []],
  ['fx-org-020', 'Mercearia Exemplo', 'retail', 'Maputo', 4, null, '+258840000120', []],
];

const PEOPLE = [
  ['fx-org-001', 'Arlindo', 'Proprietário', 'OWNER', 'arlindo@barbearia-exemplo.test', 'VERIFIED', '+258840000201', 0.9],
  ['fx-org-003', 'Célia', 'Directora Geral', 'DIRECTOR', 'celia@spa-exemplo.test', 'VERIFIED', null, 0.85],
  ['fx-org-004', 'Nelson', 'Gerente', 'MANAGER', 'nelson@ginasio-exemplo.test', 'GUESSED', null, 0.4],
  ['fx-org-006', 'Inês', 'Fundadora', 'FOUNDER', 'ines@restaurante-exemplo.test', 'VERIFIED', '+258840000204', 0.92],
  ['fx-org-009', 'Ramos', 'Proprietário', 'OWNER', null, 'UNKNOWN', '+258840000205', 0.7],
  ['fx-org-010', 'Dulce', 'CEO', 'C_LEVEL', 'dulce@clinica-exemplo.test', 'VERIFIED', null, 0.88],
  ['fx-org-013', 'Hélder', 'Gerente Geral', 'MANAGER', null, 'UNKNOWN', '+258840000207', 0.55],
  ['fx-org-017', 'Telma', 'Proprietária', 'OWNER', 'telma@nova-imagem-exemplo.test', 'VERIFIED', '+258840000208', 0.95],
  ['fx-org-002', 'Anabela', 'Atendimento', 'STAFF', null, 'UNKNOWN', '+258840000209', 0.3],
  ['fx-org-008', 'Jorge', 'Dono', 'OWNER', null, 'UNKNOWN', '+258840000210', 0.8],
];

/**
 * Where each seeded lead sits.
 *
 * Spread across the pipeline on purpose, and including all four kinds of dead
 * end — so the list filters, the terminal-status branch, and the two
 * compliance blocks are all reachable without anyone having to create them by
 * hand.
 */
const PIPELINE = {
  'fx-org-001': ['READY_TO_CONTACT', 'COMPLETE'],
  'fx-org-002': ['SCORED', 'NO_RESULT'],
  'fx-org-003': ['CONTACTED', 'COMPLETE'],
  'fx-org-004': ['SCORED', 'PARTIAL'],
  'fx-org-005': ['SCORED', 'NOT_STARTED'],
  'fx-org-006': ['INTERESTED', 'COMPLETE'],
  'fx-org-007': ['SCORED', 'NO_RESULT'],
  'fx-org-008': ['READY_TO_CONTACT', 'COMPLETE'],
  'fx-org-009': ['REPLIED', 'COMPLETE'],
  'fx-org-010': ['DEMO', 'COMPLETE'],
  'fx-org-011': ['SCORED', 'NOT_STARTED'],
  'fx-org-012': ['SCORED', 'BELOW_THRESHOLD'],
  'fx-org-013': ['CONTACTED', 'COMPLETE'],
  'fx-org-014': ['SCORED', 'BUDGET_BLOCKED'],
  'fx-org-015': ['SCORED', 'NOT_STARTED'],
  'fx-org-016': ['TRIAL', 'COMPLETE'],
  'fx-org-017': ['CUSTOMER', 'COMPLETE'],
  'fx-org-018': ['NOT_A_FIT', 'NOT_STARTED'],
  'fx-org-019': ['NOT_A_FIT', 'NOT_STARTED'],
  'fx-org-020': ['DO_NOT_CONTACT', 'NOT_STARTED'],
};

/* ------------------------------------------------------------- normalising */

/** The same FNV-1a the store uses, so a seeded lookup key matches a live one. */
function fnv1a(value) {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  const mask = 0xffffffffffffffffn;
  for (let index = 0; index < value.length; index++) {
    hash = (hash ^ BigInt(value.charCodeAt(index))) & mask;
    hash = (hash * prime) & mask;
  }
  return hash.toString(36);
}

function fold(value) {
  return (value ?? '')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function lookupId(kind, value) {
  return `${kind.toLowerCase()}_${fnv1a(value)}`;
}

/* ------------------------------------------------------------------- seed */

function socialUrls(flags, slug) {
  return {
    instagram_url: flags.includes('ig') ? `https://instagram.com/${slug}` : null,
    facebook_url: flags.includes('fb') ? `https://facebook.com/${slug}` : null,
    linkedin_url: flags.includes('li') ? `https://linkedin.com/company/${slug}` : null,
  };
}

function scoreFor(industry, employees, hasSite, socials, hasContact, hasDecisionMaker) {
  const icp = ['barbershop', 'salon', 'spa', 'gym', 'car_wash', 'restaurant', 'cafe'];
  const single = ['gym'];

  let fit = 0;
  if (icp.includes(industry)) fit += 20 + 10;
  if (employees !== null && employees >= 3 && employees <= 20) fit += 5;
  fit += 5; // target geography; every seeded lead but Beira is in one

  let digital = 0;
  if (hasSite) digital += 5;
  if (socials > 0) digital += 5;
  if (hasContact) digital += 5;
  if (hasSite && socials >= 2) digital += 5;

  let retention = 0;
  if (icp.includes(industry)) retention += 10;
  if (icp.includes(industry) && !single.includes(industry)) retention += 5;

  const commercial = hasDecisionMaker ? 10 : 0;

  const total = Math.min(40, fit) + Math.min(20, digital) + Math.min(25, retention) + commercial;
  const band = total >= 80 ? 'PRIORITY' : total >= 60 ? 'GOOD' : total >= 40 ? 'NURTURE' : 'LOW_FIT';

  return {
    total,
    fit: Math.min(40, fit),
    digital: Math.min(20, digital),
    retention: Math.min(25, retention),
    commercial,
    band,
  };
}

export async function seedProspecting() {
  const batch = db.batch();
  let writes = 0;
  const usage = [];

  for (const [orgId, name, industry, city, employees, domain, phone, socialFlags] of COMPANIES) {
    const slug = fold(name).replace(/\s+/g, '_');
    const socials = socialUrls(socialFlags, slug);
    const companyId = orgId;
    const person = PEOPLE.find((entry) => entry[0] === orgId) ?? null;
    const isDecisionMaker = person !== null && person[3] !== 'STAFF';

    const [status, enrichment] = PIPELINE[orgId] ?? ['SCORED', 'NOT_STARTED'];
    const score = scoreFor(
      industry,
      employees,
      domain !== null,
      socialFlags.length,
      phone !== null,
      isDecisionMaker,
    );

    const company = {
      id: companyId,
      name,
      legal_name: null,
      domain,
      website: domain === null ? null : `https://${domain}`,
      industry,
      industry_raw: industry,
      employee_count: employees,
      city,
      province: city === 'Beira' ? 'Sofala' : city === 'Matola' ? 'Maputo' : 'Maputo Cidade',
      country: 'Moçambique',
      address: null,
      phone,
      email: null,
      whatsapp: phone,
      ...socials,
      source: 'SEED',
      source_reference: orgId,
      provider_org_id: orgId,
      created_at: NOW - 20 * DAY,
      updated_at: NOW - 2 * DAY,
    };

    batch.set(db.collection('prospect_companies').doc(companyId), company);
    writes++;

    // The lookup documents, so a re-discovery of the same business finds the
    // seeded record instead of creating a second one.
    const keys = [];
    keys.push(['PROVIDER_ORG', `seed/${orgId}`]);
    if (domain !== null) keys.push(['DOMAIN', domain]);
    if (phone !== null) keys.push(['PHONE', phone]);
    keys.push(['NAME_CITY', `${fold(name)}@${fold(city)}`]);

    for (const [kind, value] of keys) {
      batch.set(db.collection('prospect_company_lookup').doc(lookupId(kind, value)), {
        kind,
        value,
        company_id: companyId,
        created_at: NOW - 20 * DAY,
      });
      writes++;
    }

    const spend = enrichment === 'COMPLETE' ? 0.2 : enrichment === 'PARTIAL' ? 0.1 : 0;

    batch.set(db.collection('prospects').doc(companyId), {
      id: companyId,
      company_id: companyId,
      status,
      source: 'SEED',
      source_reference: orgId,
      lead_score: status === 'NOT_A_FIT' ? null : score.total,
      business_fit_score: score.fit,
      digital_presence_score: score.digital,
      retention_potential_score: score.retention,
      commercial_opportunity_score: score.commercial,
      band: status === 'NOT_A_FIT' ? null : score.band,
      ai_summary: null,
      ai_reasoning: null,
      recommended_pitch: null,
      recommended_channel: null,
      enrichment_status: enrichment,
      last_enriched_at: spend > 0 ? NOW - 3 * DAY : null,
      spend_usd: spend,
      decision_maker_count: isDecisionMaker ? 1 : 0,
      has_reachable_contact:
        person !== null && (person[6] !== null || person[5] === 'VERIFIED'),
      suspected_merchant_id: null,
      disqualify_reason:
        orgId === 'fx-org-018'
          ? 'NOT_TARGET_INDUSTRY'
          : orgId === 'fx-org-019'
            ? 'OUT_OF_GEOGRAPHY'
            : null,
      status_source: 'seed',
      status_changed_at: NOW - 4 * DAY,
      last_activity_at: NOW - Math.floor(Math.random() * 10) * DAY,
      created_at: NOW - 20 * DAY,
      updated_at: NOW - 2 * DAY,
    });
    writes++;

    if (person !== null) {
      const [, first, title, seniority, email, emailStatus, personPhone, confidence] = person;
      const contactId = `fx-per-${orgId.slice(-3)}`;
      batch.set(
        db.collection('prospects').doc(companyId).collection('contacts').doc(contactId),
        {
          id: contactId,
          prospect_id: companyId,
          first_name: first,
          last_name: null,
          job_title: title,
          seniority,
          email,
          email_status: emailStatus,
          phone: personPhone,
          linkedin_url: null,
          provider_person_id: contactId,
          confidence_score: confidence,
          is_decision_maker: seniority !== 'STAFF',
          created_at: NOW - 3 * DAY,
          updated_at: NOW - 3 * DAY,
        },
      );
      writes++;
    }

    const trail = [
      ['DISCOVERED', `Descoberto via seed.`, NOW - 20 * DAY],
      ['SCORED', `Pontuação ${score.total}.`, NOW - 19 * DAY],
    ];
    if (spend > 0) trail.push(['ENRICHED', 'Pesquisa concluída.', NOW - 3 * DAY]);
    if (isDecisionMaker) {
      trail.push(['DECISION_MAKER_FOUND', '1 decisor encontrado.', NOW - 3 * DAY]);
    }
    if (['CONTACTED', 'REPLIED', 'INTERESTED', 'DEMO', 'TRIAL', 'CUSTOMER'].includes(status)) {
      trail.push(['OUTREACH_SENT', 'Mensagem enviada por WhatsApp.', NOW - 2 * DAY]);
    }

    for (const [type, description, at] of trail) {
      const id = randomUUID();
      batch.set(
        db.collection('prospects').doc(companyId).collection('activities').doc(id),
        {
          id,
          prospect_id: companyId,
          type,
          channel: type === 'OUTREACH_SENT' ? 'WHATSAPP' : null,
          description,
          metadata: {},
          created_at: at,
          created_by: 'seed',
        },
      );
      writes++;
    }

    if (spend > 0) {
      usage.push([companyId, 'FIND_DECISION_MAKERS', 0.05, true, null]);
      usage.push([companyId, 'ENRICH_PERSON', 0.1, enrichment === 'COMPLETE', enrichment === 'COMPLETE' ? null : 'NO_RESULT']);
      usage.push([companyId, 'RESEARCH_COMPANY', 0.03, true, null]);
      usage.push([companyId, 'ANALYZE_LEAD', 0.05, true, null]);
    }
  }

  // A month of costs, including the failures — providers charge for calls that
  // return nothing, and a seeded log that only held successes would not look
  // like a real one.
  const monthKey = new Date(NOW + 2 * 3_600_000).toISOString().slice(0, 7);
  const dayKey = new Date(NOW + 2 * 3_600_000).toISOString().slice(0, 10);
  let monthTotal = 0;

  for (const [prospectId, operation, cost, success, errorCode] of usage) {
    const id = randomUUID();
    batch.set(db.collection('prospecting_usage').doc(id), {
      id,
      provider: 'fixtures',
      operation,
      prospect_id: prospectId,
      estimated_cost: cost,
      actual_cost: null,
      credits_used: null,
      success,
      error_code: errorCode,
      correlation_id: 'seed',
      month_key: monthKey,
      day_key: dayKey,
      created_at: NOW - 3 * DAY,
    });
    monthTotal = Math.round((monthTotal + cost) * 10_000) / 10_000;
    writes++;
  }

  batch.set(db.collection('prospecting_spend').doc(monthKey), {
    period: monthKey,
    kind: 'month',
    total_usd: monthTotal,
    calls: usage.length,
    updated_at: NOW,
  });
  batch.set(db.collection('prospecting_spend').doc(dayKey), {
    period: dayKey,
    kind: 'day',
    total_usd: 0,
    calls: 0,
    updated_at: NOW,
  });
  writes += 2;

  await batch.commit();
  return { writes, companies: COMPANIES.length, usage: usage.length, monthTotal };
}

/**
 * Run from the command line rather than imported.
 *
 * The smoke suite imports `seedProspecting` and calls it itself, so this
 * module must not seed on import — and must not call `process.exit` when it is
 * being used as a library.
 */
const invokedDirectly = (process.argv[1] ?? '')
  .split('\\')
  .join('/')
  .endsWith('seed-prospecting.mjs');

if (invokedDirectly) {
  seedProspecting()
    .then((summary) => {
      console.log(
        `Prospeção semeada: ${summary.companies} negócios, ${summary.usage} ` +
          `chamadas (${summary.monthTotal.toFixed(2)} USD este mês), ` +
          `${summary.writes} escritas.`,
      );
      console.log(
        'Ligue PROSPECTING_FIXTURES_ENABLED=true e AI_PROSPECTING_ENABLED=true para as ver.',
      );
      process.exit(0);
    })
    .catch((error) => {
      console.error('Falhou a semear a prospeção:', error);
      process.exit(1);
    });
}
