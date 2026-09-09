/**
 * The local development fixture: one business, with the edges that break things.
 *
 * The README says the businesses visible locally are seeded, but nothing in
 * the repository seeded them — so every person who wanted to see the portal
 * work invented their own data, and the smoke suite had nothing stable to
 * assert against. This is that fixture, written down.
 *
 * The data is deliberately awkward. A team member with no stored status, an
 * entitlement with no stored flag, a customer in each relationship state: each
 * one is a bug this portal has actually shipped, and a fixture of only tidy
 * rows would not have caught any of them.
 *
 *   node scripts/seed-dev.mjs
 *
 * It cannot reach production. The emulator hosts are set here rather than read
 * from the environment, and asserted to be loopback, so an unset variable
 * fails to connect instead of quietly writing to the real project.
 */

import admin from 'firebase-admin';

const AUTH_EMULATOR = '127.0.0.1:9099';
const FIRESTORE_EMULATOR = '127.0.0.1:8085';
const PROJECT_ID = 'loyaltyos-fc4dd';

/** Refuses anything that is not the loopback interface. */
function assertLoopback(host, name) {
  const hostname = host.split(':')[0];
  if (hostname !== '127.0.0.1' && hostname !== 'localhost' && hostname !== '::1') {
    throw new Error(
      `${name} is ${hostname}, which is not this machine. This script only ` +
        'ever writes to the emulators; refusing to run.',
    );
  }
}

assertLoopback(AUTH_EMULATOR, 'auth emulator');
assertLoopback(FIRESTORE_EMULATOR, 'firestore emulator');

process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR;
process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR;

export const CONTAS = {
  /** Runs a business. The account the portal is meant for. */
  dono: { email: 'dono@teste.local', password: 'teste123456' },
  /** Internal staff: reaches the console, never the business area. */
  interno: { email: 'staff@teste.local', password: 'teste123456' },
  /** Authenticated and entitled to nothing, which is its own screen. */
  ninguem: { email: 'ninguem@teste.local', password: 'teste123456' },
};

export const NEGOCIO = {
  nome: 'Padaria Central',
  telefone: '+258840000001',
};

const DIA = 86400000;

/** Filler, so the 25-row page size is actually crossed. */
const OUTROS_CLIENTES = [
  'Elias Cossa', 'Fatima Tembe', 'Gito Mabjaia', 'Helena Zandamela',
  'Ivan Chirindza', 'Joana Macuacua', 'Kevin Nhantumbo', 'Lucia Manhica',
  'Mario Bucuane', 'Nadia Cuna', 'Osvaldo Muianga', 'Paula Chissano',
  'Quito Massingue', 'Rita Mondlane', 'Samuel Guambe', 'Telma Xavier',
  'Ubaldo Simango', 'Vera Langa', 'Wilson Matsinhe', 'Xenia Come',
  'Yara Fumo', 'Zito Baloi', 'Alda Sumbana', 'Bento Chauque',
  'Celia Mahumane', 'Dulce Nhaca', 'Edgar Timba', 'Flavia Sitoe',
];

async function conta(auth, { email, password }, claims) {
  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, { password });
  } catch {
    user = await auth.createUser({ email, password, emailVerified: true });
  }
  await auth.setCustomUserClaims(user.uid, claims ?? {});
  return user.uid;
}

/** Empties a subcollection, so re-seeding is not additive. */
async function limpar(biz, nome) {
  const snapshot = await biz.collection(nome).get();
  for (const doc of snapshot.docs) await doc.ref.delete();
}

export async function seed({ quiet = false } = {}) {
  const log = quiet ? () => {} : (...args) => console.log(...args);

  if (admin.apps.length === 0) admin.initializeApp({ projectId: PROJECT_ID });
  const auth = admin.auth();
  const db = admin.firestore();

  const uid = await conta(auth, CONTAS.dono);
  await conta(auth, CONTAS.interno, { admin: true });
  await conta(auth, CONTAS.ninguem);
  log('contas prontas; negócio =', uid);

  const biz = db.collection('businesses').doc(uid);
  const agora = Date.now();

  for (const nome of [
    'customers',
    'sales',
    'merchant_items',
    'rewards',
    'app_users',
    'redemptions',
    'appointments',
    'loyalty_ledger',
    'usage_balances',
    'customer_risk_scores',
    'recovery_tasks',
    'visit_reports',
    'surveys',
    'survey_responses',
    'return_bonuses',
  ]) {
    await limpar(biz, nome);
  }

  await biz.set({
    merchant_name: NEGOCIO.nome,
    name: NEGOCIO.nome,
    owner_user_id: uid,
    phone: NEGOCIO.telefone,
    city: 'Maputo',
    created_at: agora - 90 * DIA,
    updated_at: agora,
  });

  // One customer per relationship state, so each filter has something to find.
  const clientes = [
    { id: 'c1', name: 'Ana Matola', phone: '+258841111111', total_points: 320, total_visits: 12, total_spent: 4800, average_spend: 400, lifecycle_stage: 'LOYAL', retention_status: 'HEALTHY', relationship_status: 'ACTIVE', dias: 2 },
    { id: 'c2', name: 'Bruno Sitoe', phone: '+258842222222', total_points: 45, total_visits: 2, total_spent: 600, average_spend: 300, lifecycle_stage: 'NEW', retention_status: 'AT_RISK', relationship_status: 'ACTIVE', dias: 25 },
    { id: 'c3', name: 'Carla Nhaca', phone: '+258843333333', total_points: 0, total_visits: 1, total_spent: 150, average_spend: 150, lifecycle_stage: 'NEW', retention_status: 'LOST', relationship_status: 'ARCHIVED', dias: 190 },
    { id: 'c4', name: 'Dino Bila', phone: '+258844444444', total_points: 80, total_visits: 4, total_spent: 900, average_spend: 225, lifecycle_stage: 'REGULAR', retention_status: 'INACTIVE', relationship_status: 'BLOCKED', dias: 60 },
  ];
  for (const { id, dias, ...resto } of clientes) {
    await biz.collection('customers').doc(id).set({
      ...resto,
      first_visit_at: agora - (dias + 60) * DIA,
      last_visit_at: agora - dias * DIA,
      created_at: agora - (dias + 60) * DIA,
      updated_at: agora,
      synced: 1,
    });
  }

  let lote = db.batch();
  OUTROS_CLIENTES.forEach((nome, i) => {
    lote.set(biz.collection('customers').doc('p' + (i + 10)), {
      name: nome,
      phone: '+2588' + String(50000000 + i),
      total_points: (i * 17) % 400,
      total_visits: (i % 9) + 1,
      total_spent: 100 + i * 55,
      average_spend: 100 + i,
      lifecycle_stage: 'ACTIVE',
      retention_status: 'HEALTHY',
      relationship_status: 'ACTIVE',
      first_visit_at: agora - (100 - i) * DIA,
      last_visit_at: agora - (i + 3) * DIA,
      created_at: agora - (100 - i) * DIA,
      updated_at: agora,
      synced: 1,
    });
  });
  await lote.commit();

  for (const venda of [
    { id: 's1', customer_id: 'c1', amount: 450, points: 45, dias: 2, confirmation_status: 'CONFIRMED' },
    { id: 's2', customer_id: 'c1', amount: 300, points: 30, dias: 9, confirmation_status: 'CONFIRMED' },
    { id: 's3', customer_id: 'c2', amount: 600, points: 60, dias: 25, confirmation_status: 'PENDING' },
  ]) {
    const { id, dias, ...resto } = venda;
    await biz.collection('sales').doc(id).set({
      ...resto,
      cancellation_status: 'ACTIVE',
      created_at: agora - dias * DIA,
    });
  }

  // is_active as 0/1: the app syncs SQLite rows, and a web client that read
  // these as JSON booleans would show every inactive item as active.
  for (const item of [
    { id: 'i1', name: 'Pao de forma', type: 'PRODUCT', default_price: 80, is_active: 1, display_order: 1 },
    { id: 'i2', name: 'Corte de cabelo', type: 'SERVICE', default_price: 350, is_active: 1, display_order: 2 },
    { id: 'i3', name: 'Cafe descontinuado', type: 'PRODUCT', default_price: 60, is_active: 0, display_order: 3 },
  ]) {
    const { id, ...resto } = item;
    await biz.collection('merchant_items').doc(id).set({
      ...resto,
      created_at: agora - 60 * DIA,
      updated_at: agora,
    });
  }

  for (const premio of [
    { id: 'r1', name: 'Cafe gratis', description: 'Um cafe por conta da casa', points_required: 100, is_active: 1 },
    { id: 'r2', name: 'Bolo com 50%', description: 'Metade do preco em qualquer bolo', points_required: 250, is_active: 0 },
  ]) {
    const { id, ...resto } = premio;
    await biz.collection('rewards').doc(id).set({
      ...resto,
      created_at: agora - 60 * DIA,
      updated_at: agora,
    });
  }

  // t4 is INVITED, which had no translation and no filter chip. t5 has no
  // status at all, which the team page used to draw as "Ativo" while the
  // profile card counted it as not active.
  for (const membro of [
    { id: 't1', phone: '+258840000001', role: 'OWNER', status: 'ACTIVE', last_login_at: agora - 3600000 },
    { id: 't2', phone: '+258845555555', role: 'STAFF', status: 'ACTIVE', last_login_at: agora - DIA },
    { id: 't3', phone: '+258846666666', role: 'STAFF', status: 'INACTIVE', last_login_at: null },
    { id: 't4', phone: '+258847777777', role: 'STAFF', status: 'INVITED', last_login_at: null },
    { id: 't5', phone: '+258848888888', role: 'STAFF', last_login_at: null },
  ]) {
    const { id, ...resto } = membro;
    await biz.collection('app_users').doc(id).set({
      ...resto,
      created_at: agora - 60 * DIA,
      updated_at: agora,
    });
  }

  // No `is_enabled`: the plan page used to read "not stored" as "switched off"
  // and tell a business a feature they pay for was disabled.
  await biz.collection('entitlements').doc('zz_sem_flag').set({
    feature_key: 'sem_flag_guardada',
    limit_value: null,
    updated_at: agora,
  });

  /* -------------------------------------- the surfaces the portal now shows */

  for (const resgate of [
    { id: 'g1', customer_id: 'c1', reward_id: 'r1', points_spent: 100, dias: 5 },
    { id: 'g2', customer_id: 'c2', reward_id: 'r1', points_spent: 100, dias: 20 },
  ]) {
    const { id, dias, ...resto } = resgate;
    await biz.collection('redemptions').doc(id).set({
      ...resto,
      redeemed_at: agora - dias * DIA,
      created_at: agora - dias * DIA,
    });
  }

  // Lowercase, as the app writes them; the filter upper-cases both sides.
  for (const marcacao of [
    { id: 'm1', customer_id: 'c1', dias: -3, status: 'scheduled', reminder_sent: 0 },
    { id: 'm2', customer_id: 'c2', dias: 10, status: 'completed', reminder_sent: 1 },
    { id: 'm3', customer_id: 'c4', dias: 4, status: 'missed', reminder_sent: 1 },
  ]) {
    const { id, dias, ...resto } = marcacao;
    await biz.collection('appointments').doc(id).set({
      ...resto,
      source: 'manual',
      scheduled_date: agora - dias * DIA,
      created_at: agora - (dias + 5) * DIA,
      updated_at: agora,
    });
  }

  // The ledger behind Ana's 320 points, so the balance column has a story.
  for (const entrada of [
    { id: 'l1', entry_type: 'EARN', points_delta: 45, balance_after: 320, dias: 2, source_type: 'SALE', source_id: 's1' },
    { id: 'l2', entry_type: 'REDEEM', points_delta: -100, balance_after: 275, dias: 5, source_type: 'REDEMPTION', source_id: 'g1' },
    { id: 'l3', entry_type: 'EARN', points_delta: 30, balance_after: 375, dias: 9, source_type: 'SALE', source_id: 's2' },
    { id: 'l4', entry_type: 'BASELINE', points_delta: 345, balance_after: 345, dias: 80, source_type: 'BACKFILL', source_id: 'b1' },
  ]) {
    const { id, dias, ...resto } = entrada;
    await biz.collection('loyalty_ledger').doc(id).set({
      ...resto,
      customer_id: 'c1',
      occurred_at: agora - dias * DIA,
      created_at: agora - dias * DIA,
    });
  }

  // One with a ceiling and one without: the panel must not draw "no limit" as
  // a share that is permanently full.
  const inicio = agora - 15 * DIA;
  const fim = agora + 15 * DIA;
  for (const consumo of [
    { id: 'u1', metric_key: 'whatsapp_messages', used: 42, limit_value: 50 },
    { id: 'u2', metric_key: 'campaigns', used: 3, limit_value: 5 },
    { id: 'u3', metric_key: 'sales', used: 128, limit_value: null },
  ]) {
    const { id, ...resto } = consumo;
    await biz.collection('usage_balances').doc(id).set({
      ...resto,
      window_start: inicio,
      window_end: fim,
      soft_limit: 1,
      updated_at: agora,
    });
  }

  // Risk levels are stored as colour names.
  for (const risco of [
    { id: 'k1', customer_id: 'c3', risk_level: 'red', days_since_visit: 190, priority: 90 },
    { id: 'k2', customer_id: 'c4', risk_level: 'orange', days_since_visit: 60, priority: 60 },
    { id: 'k3', customer_id: 'c2', risk_level: 'yellow', days_since_visit: 25, priority: 30 },
    { id: 'k4', customer_id: 'c1', risk_level: 'green', days_since_visit: 2, priority: 5 },
  ]) {
    const { id, ...resto } = risco;
    await biz.collection('customer_risk_scores').doc(id).set({
      ...resto,
      updated_at: agora,
    });
  }

  for (const tarefa of [
    { id: 'y1', customer_id: 'c3', priority: 'high', status: 'open', dias: -2, notes: 'Nao vem desde marco' },
    { id: 'y2', customer_id: 'c4', priority: 'medium', status: 'open', dias: -5, notes: null },
    { id: 'y3', customer_id: 'c2', priority: 'low', status: 'completed', dias: 3, notes: 'Ligou, vem sabado' },
  ]) {
    const { id, dias, ...resto } = tarefa;
    await biz.collection('recovery_tasks').doc(id).set({
      ...resto,
      due_at: agora - dias * DIA,
      created_at: agora - 10 * DIA,
      updated_at: agora,
    });
  }

  // Stored with a space in the value, which is why the label table keys do too.
  for (const relatorio of [
    { id: 'v1', customer_id: 'c2', result: 'Returned', dias: 3, notes: 'Voltou no sabado' },
    { id: 'v2', customer_id: 'c4', result: 'Needs Promotion', dias: 8, notes: 'So volta com desconto' },
    { id: 'v3', customer_id: 'c3', result: 'Lost Customer', dias: 15, notes: null },
  ]) {
    const { id, dias, ...resto } = relatorio;
    await biz.collection('visit_reports').doc(id).set({
      ...resto,
      visited_at: agora - dias * DIA,
      created_at: agora - dias * DIA,
      updated_at: agora,
    });
  }

  for (const inquerito of [
    { id: 'q1', title: 'Como foi o atendimento?', description: 'Tres perguntas rapidas', is_active: 1, dias: 30 },
    { id: 'q2', title: 'Inquerito de Natal', description: null, is_active: 0, dias: 120 },
  ]) {
    const { id, dias, ...resto } = inquerito;
    await biz.collection('surveys').doc(id).set({
      ...resto,
      created_at: agora - dias * DIA,
      updated_at: agora,
    });
  }

  // Three answers to one survey and none to the other: the count is the only
  // reason the list is worth opening.
  for (const [i, resposta] of [
    { survey_id: 'q1', customer_id: 'c1', channel: 'whatsapp' },
    { survey_id: 'q1', customer_id: 'c2', channel: 'in-app' },
    { survey_id: 'q1', customer_id: null, channel: 'manual' },
  ].entries()) {
    await biz.collection('survey_responses').doc('a' + i).set({
      ...resposta,
      submitted_at: agora - (i + 1) * DIA,
      created_at: agora - (i + 1) * DIA,
      updated_at: agora,
    });
  }

  for (const bonus of [
    { id: 'b1', customer_id: 'c2', type: 'DISCOUNT', value: 50, status: 'ACTIVE', dias: 5 },
    { id: 'b2', customer_id: 'c1', type: 'EXTRA_POINTS', value: 100, status: 'REDEEMED', dias: 20 },
    { id: 'b3', customer_id: 'c4', type: 'FREE_SERVICE', value: 1, status: 'EXPIRED', dias: 90 },
  ]) {
    const { id, dias, ...resto } = bonus;
    await biz.collection('return_bonuses').doc(id).set({
      ...resto,
      issued_at: agora - dias * DIA,
      expires_at: agora - dias * DIA + 30 * DIA,
      redeemed_at: resto.status === 'REDEEMED' ? agora - (dias - 2) * DIA : null,
      created_at: agora - dias * DIA,
      updated_at: agora,
    });
  }

  // The state a merchant most needs to understand, and the one that used to
  // reach them as the English `PAST_DUE`.
  await esperarBootstrap(biz);
  const subs = await biz.collection('subscription_state').get();
  const refs = subs.empty
    ? [biz.collection('subscription_state').doc('current')]
    : subs.docs.map((d) => d.ref);
  for (const ref of refs) {
    await ref.set(
      { status: 'PAST_DUE', plan_code: 'free', plan_name: 'Free', updated_at: agora },
      { merge: true },
    );
  }

  log('semeado: 32 clientes, 3 vendas, 3 itens, 2 recompensas, 5 na equipa,');
  log('         2 resgates, 3 marcacoes, 4 movimentos, 3 consumos, 4 riscos,');
  log('         3 tarefas, 3 relatorios, 2 inqueritos, 3 bonus');
  return { uid, ...CONTAS };
}

/**
 * Waits for `merchantPolicyBootstrapOnBusinessWrite` to write the plan.
 *
 * Writing the business fires that trigger, and it writes `subscription_state`
 * itself. Overriding the status before it lands would simply be overwritten,
 * which is the kind of race that makes a fixture flaky.
 */
async function esperarBootstrap(biz, tentativas = 25) {
  for (let i = 0; i < tentativas; i++) {
    const snapshot = await biz.collection('subscription_state').get();
    if (!snapshot.empty) return true;
    await new Promise((resolve) => setTimeout(resolve, 400));
  }
  return false;
}

const executadoDirectamente =
  process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/').split('/').pop());

if (executadoDirectamente) {
  seed()
    .then(({ uid }) => {
      console.log('\nEntrar em http://localhost:3000');
      console.log('  negócio  ' + CONTAS.dono.email + '  /  ' + CONTAS.dono.password);
      console.log('  interno  ' + CONTAS.interno.email + '  /  ' + CONTAS.interno.password);
      console.log('  sem acesso  ' + CONTAS.ninguem.email);
      console.log('  id do negócio  ' + uid);
      process.exit(0);
    })
    .catch((erro) => {
      console.error('\nseed falhou:', erro.message);
      console.error('Os emuladores estão a correr? firebase emulators:start --only auth,functions,firestore');
      process.exit(1);
    });
}
