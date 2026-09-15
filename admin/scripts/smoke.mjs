/**
 * What the portal does, checked against a running one.
 *
 * The unit suite can say that `INVITED` has a translation. It cannot say that
 * the team page has a chip to filter by it, that an absent status draws a dash
 * rather than an invented "Ativo", or that a nullable flag is not collapsed
 * into "off" — those live in `.tsx` and are only true once a page has been
 * rendered with data. Three of the six bugs this suite was written after were
 * of exactly that kind, and no unit test could have caught any of them.
 *
 *   npm run smoke        (needs the emulators and `npm run dev` up)
 *
 * It seeds first, so it asserts against a fixture it controls rather than
 * whatever the last person left behind.
 */

import { initializeApp } from 'firebase/app';
import {
  connectAuthEmulator,
  getAuth,
  signInWithEmailAndPassword,
} from 'firebase/auth';

import { seed, CONTAS, NEGOCIO } from './seed-dev.mjs';

const BASE = process.env.SMOKE_BASE_URL ?? 'http://127.0.0.1:3000';
const AUTH_EMULATOR = 'http://127.0.0.1:9099';

let passaram = 0;
const falhas = [];
let seccao = '';

function grupo(nome) {
  seccao = nome;
  console.log('\n' + nome);
}

function check(o_que, ok, detalhe) {
  if (ok) {
    passaram++;
    console.log('  ok   ' + o_que);
  } else {
    falhas.push(seccao + ' > ' + o_que + (detalhe ? '  (' + detalhe + ')' : ''));
    console.log('  FALHOU ' + o_que + (detalhe ? '  (' + detalhe + ')' : ''));
  }
}

/* ------------------------------------------------------------------ o cliente */

let cookie = '';

async function pedir(caminho) {
  const res = await fetch(BASE + caminho, {
    headers: cookie ? { cookie } : {},
    redirect: 'manual',
  });
  const html = await res.text();

  // The shell arrives as HTML; each panel is streamed into the flight payload
  // afterwards. Reading only the first would miss every Suspense boundary,
  // which is where the error states and the tables actually are.
  const visivel = html
    .replace(/<script[\s\S]*?<\/script>/g, '')
    .replace(/<style[\s\S]*?<\/style>/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&#x2014;/g, '-');
  const fluxo = html.replace(/\\n/g, ' ').replace(/\\"/g, '"');
  const corpo = (html.match(/<tbody>([\s\S]*?)<\/tbody>/) || ['', ''])[1];

  return {
    status: res.status,
    destino: res.headers.get('location') ?? '',
    html,
    texto: visivel,
    tudo: visivel + ' ' + fluxo,
    linhas: corpo.split('<tr>').length - 1,
    /** Exactly what an operator reads in an error panel, and nothing else. */
    erros: [
      ...fluxo.matchAll(
        /"className":"state__message","children":\[[\s\S]{0,120}?," ","([^"]+)"\]/g,
      ),
    ].map((m) => m[1]),
  };
}

async function entrar({ email, password }) {
  const app = initializeApp({
    apiKey: 'demo-emulator-key',
    authDomain: 'loyaltyos-fc4dd.firebaseapp.com',
    projectId: 'loyaltyos-fc4dd',
  });
  const auth = getAuth(app);
  connectAuthEmulator(auth, AUTH_EMULATOR, { disableWarnings: true });

  const credencial = await signInWithEmailAndPassword(auth, email, password);
  const idToken = await credencial.user.getIdToken();
  const res = await fetch(BASE + '/api/session', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ idToken }),
  });
  const corpo = await res.json().catch(() => ({}));
  const cookies = (res.headers.getSetCookie ? res.headers.getSetCookie() : [])
    .map((c) => c.split(';')[0])
    .join('; ');
  return { status: res.status, corpo, cookies, uid: credencial.user.uid };
}

/**
 * The functions emulator kills its runtime when a trigger throws, and seeding
 * sales fires one. Without this the first request of the run can hit a dead
 * worker and fail for a reason that has nothing to do with the portal.
 */
async function esperarApi(tentativas = 20) {
  for (let i = 0; i < tentativas; i++) {
    try {
      const res = await fetch(BASE + '/login');
      if (res.ok) return true;
    } catch {
      /* ainda a subir */
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

/* -------------------------------------------------------------------- a suite */

console.log('a semear…');
const { uid } = await seed({ quiet: true });
if (!(await esperarApi())) {
  console.error('O portal não respondeu em ' + BASE + '. `npm run dev` está a correr?');
  process.exit(1);
}

grupo('sessão');
const sessao = await entrar(CONTAS.dono);
check('o dono entra', sessao.status === 200, 'status=' + sessao.status);
check('é encaminhado para a área de negócio', sessao.corpo.area === 'merchant');
check('o cookie de sessão é emitido', /maisum_admin_session/.test(sessao.cookies));
cookie = sessao.cookies;

let r = await pedir('/');
check('a raiz leva ao negócio', r.status === 307 && r.destino.endsWith('/negocio'), r.destino);
r = await pedir('/admin');
check('a consola interna recusa um dono', r.status === 307 && r.destino.endsWith('/negocio'), r.destino);

grupo('painel');
r = await pedir('/negocio');
check('abre', r.status === 200);
// `/negocio` used to be the profile — the one page here that answers no
// question anyone signs in to ask.
check('é o painel, não o perfil', r.tudo.includes('Painel'));
check('mostra as vendas totais', /1\s?350|1350/.test(r.tudo), 'valor das 3 vendas');
check('mostra os clientes críticos', /Críticos/.test(r.tudo));
check('mostra o consumo do plano', /Mensagens WhatsApp|84%/.test(r.tudo));

grupo('perfil');
r = await pedir('/negocio/perfil');
check('abre no seu próprio endereço', r.status === 200);
check('mostra o negócio', r.texto.includes(NEGOCIO.nome));
check('mostra o telefone', r.texto.includes(NEGOCIO.telefone));
check('conta 2 ativos de 5 na equipa', /2 ativos de 5/.test(r.texto), (r.texto.match(/\d+ ativos de \d+/) || [''])[0]);

grupo('clientes');
r = await pedir('/negocio/clientes');
check('abre', r.status === 200);
check('conta os 32', /32 clientes/.test(r.texto), (r.texto.match(/\d+ clientes/) || [''])[0]);
check('a primeira página traz 25', r.linhas === 25, 'linhas=' + r.linhas);
check('há paginação', /offset=25/.test(r.html));
check('nenhum estado em inglês', !/\bACTIVE\b|\bBLOCKED\b|\bARCHIVED\b/.test(r.texto));
r = await pedir('/negocio/clientes?offset=25');
check('a segunda página traz os 7 restantes', r.linhas === 7, 'linhas=' + r.linhas);
r = await pedir('/negocio/clientes?status=BLOCKED');
check('o filtro de bloqueados encontra o Dino', r.linhas === 1 && r.texto.includes('Dino Bila'), 'linhas=' + r.linhas);
r = await pedir('/negocio/clientes?status=ARCHIVED');
check('o filtro de arquivados encontra a Carla', r.linhas === 1 && r.texto.includes('Carla Nhaca'), 'linhas=' + r.linhas);
r = await pedir('/negocio/clientes?search=' + encodeURIComponent('+258842222222'));
check('procura por telefone', r.texto.includes('Bruno Sitoe'), 'linhas=' + r.linhas);
r = await pedir('/negocio/clientes?search=zzznaoexiste');
check('procura sem resultados dá estado vazio', r.linhas === 0 && /corresponde/i.test(r.texto));
check('e oferece limpar os filtros', /Limpar filtros/i.test(r.texto));

grupo('cliente');
r = await pedir('/negocio/clientes/c1');
check('abre', r.status === 200);
check('mostra os pontos', /Pontos320/.test(r.texto));
check('traduz a fase para Fiel', r.texto.includes('Fiel'));
check('traduz a retenção para Saudável', /Saudável/.test(r.texto));
check('lista as 2 visitas', r.linhas === 2, 'linhas=' + r.linhas);
r = await pedir('/negocio/clientes/naoexiste');
check('um id inexistente dá 404', r.status === 404, 'status=' + r.status);

grupo('catálogo');
r = await pedir('/negocio/catalogo');
check('abre', r.status === 200);
check('lista os 3 itens', /3 itens/.test(r.texto));
check('respeita a ordem da app', r.texto.indexOf('Pao de forma') < r.texto.indexOf('Corte de cabelo'));
r = await pedir('/negocio/catalogo?status=SERVICE');
check('separa serviços de produtos', r.linhas === 1 && r.texto.includes('Corte de cabelo'), 'linhas=' + r.linhas);
r = await pedir('/negocio/catalogo?status=INACTIVE');
check('lê is_active guardado como 0', r.linhas === 1 && /Inativo/.test(r.texto), 'linhas=' + r.linhas);

grupo('recompensas');
r = await pedir('/negocio/recompensas');
check('abre', r.status === 200);
check('lista as 2', /2 recompensas/.test(r.texto));
check('a mais barata primeiro', r.texto.indexOf('Cafe gratis') < r.texto.indexOf('Bolo com 50%'));
r = await pedir('/negocio/recompensas?status=INACTIVE');
check('filtra as inativas', r.linhas === 1 && r.texto.includes('Bolo com 50%'), 'linhas=' + r.linhas);

grupo('equipa');
r = await pedir('/negocio/equipa');
check('abre', r.status === 200);
check('lista os 5', /5 membros/.test(r.texto));
check('o proprietário vem primeiro', r.texto.indexOf('Propriet') < r.texto.indexOf('Colaborador'));
check('traduz INVITED para Convidado', r.texto.includes('Convidado') && !/\bINVITED\b/.test(r.texto));
check('sem estado guardado desenha um traço, não "Ativo"', /<span class="muted">—<\/span>/.test(r.html));
check('quem nunca entrou diz "Nunca"', r.texto.includes('Nunca'));
// The chip has to be asserted separately from the filtering. Asking for
// ?status=INVITED by hand works whether or not anything on the page offers
// it, so a check that only did that passed happily while the chip was
// missing — which was the actual bug.
check('o chip de convidados existe na página', /href="\/negocio\/equipa\?status=INVITED"/.test(r.html));
r = await pedir('/negocio/equipa?status=INVITED');
check('e filtra para o convidado', r.linhas === 1 && r.texto.includes('+258847777777'), 'linhas=' + r.linhas);
r = await pedir('/negocio/equipa?status=ACTIVE');
check('o filtro de ativos concorda com a contagem do perfil', r.linhas === 2, 'linhas=' + r.linhas);

grupo('plano');
r = await pedir('/negocio/plano');
check('abre', r.status === 200);
check('traduz PAST_DUE', r.texto.includes('Pagamento em atraso') && !/PAST_DUE/.test(r.texto));
check('e pinta-o de vermelho', /badge-red">Pagamento em atraso/.test(r.html));
check('sem flag guardada desenha um traço, não "Inativo"', /Cópia de segurança na nuvem<\/td><td><span class="muted">/.test(r.html));
check('estados em caixa de frase', !/>ATIVO</.test(r.html));
check(
  'nenhuma chave de funcionalidade chega em bruto',
  !/engage_manage_recovery|cloud_backup|whatsapp_automation|retention_core/.test(r.texto),
);
// The entitlements the plans actually use carry no ceiling, so the column
// stood at "Sem limite" on every row of every plan.
check(
  'a coluna Limite some quando nada a preenche',
  !/<th scope="col">Limite<\/th>/.test(r.html),
);
// One window per metric. The fixture seeds a closed month at 5/5 alongside
// the open one at 3/5; listing both showed the same measure twice and let a
// period that ended fill the dashboard.
// The fixture seeds two windows for Campanhas: the open month at 3 of 5, and
// the month before it, full, at 5 of 5. Only the first may reach the screen.
//
// Matched by proximity rather than by slicing the page between its two
// headings: both panels stream, so the headings land in the HTML and the rows
// arrive afterwards in the flight payload, and anything between the headings
// is just the headings. "Campanhas" also names a feature in the table below,
// so the row is identified by the numbers beside it, not by the word.
check(
  'mostra a janela corrente do consumo',
  /Campanhas[^0-9]{0,4}3[^0-9]{0,6}60/.test(r.tudo),
  '3 de 5, 60%',
);
check(
  'e não a que já fechou',
  !/Campanhas[^0-9]{0,4}5[^0-9]{0,6}100/.test(r.tudo),
  'a janela fechada ainda aparece',
);

grupo('vendas');
r = await pedir('/negocio/vendas');
check('abre', r.status === 200);
check('lista as 3', r.linhas === 3, 'linhas=' + r.linhas);
check('soma o total sobre todas, não sobre a página', /1\s?350|1350/.test(r.tudo));
check('marca a venda por confirmar', r.tudo.includes('Por confirmar'));
r = await pedir('/negocio/vendas?status=CONFIRMED');
check('filtra por estado', r.linhas === 2, 'linhas=' + r.linhas);
r = await pedir('/negocio/vendas');
check('nomeia o cliente de cada venda', r.tudo.includes('Ana Matola'));
r = await pedir('/negocio/vendas?search=Ana');
check('e procura pelo nome, não só pelo id', r.linhas === 2, 'linhas=' + r.linhas);

grupo('resgates');
r = await pedir('/negocio/resgates');
check('abre', r.status === 200);
check('lista os 2', r.linhas === 2, 'linhas=' + r.linhas);
check('mostra os pontos gastos', r.tudo.includes('100'));
check('nomeia a recompensa, não o id', r.tudo.includes('Cafe gratis') && !/>r1</.test(r.html));
check('traduz o estado do resgate', r.tudo.includes('Levantado') && !/CONSUMED/.test(r.texto));
r = await pedir('/negocio/resgates?search=Cafe');
check('e procura por nome da recompensa', r.linhas === 2, 'linhas=' + r.linhas);

grupo('marcações');
r = await pedir('/negocio/marcacoes');
check('abre', r.status === 200);
check('lista as 3', r.linhas === 3, 'linhas=' + r.linhas);
check('traduz o estado guardado em minúsculas', r.tudo.includes('Faltou') && !/\bmissed\b/.test(r.texto));
r = await pedir('/negocio/marcacoes?status=MISSED');
check('filtra quem faltou', r.linhas === 1, 'linhas=' + r.linhas);

grupo('bónus de retorno');
r = await pedir('/negocio/bonus');
check('abre', r.status === 200);
check('lista os 3', r.linhas === 3, 'linhas=' + r.linhas);
check('traduz o tipo', r.tudo.includes('Pontos extra') && !/EXTRA_POINTS/.test(r.texto));
check('desconto sai em meticais, pontos não', /50\s?MZN/.test(r.tudo) && /100 pontos/.test(r.tudo));

grupo('clientes em risco');
r = await pedir('/negocio/retencao');
check('abre', r.status === 200);
// The board exists to say who to call. It used to say `c3`.
check('nomeia quem contactar', r.tudo.includes('Ana Matola'));
check('e não o id do cliente', !/<code>c[0-9]+<\/code>/.test(r.html));
check('lista os 4', r.linhas === 4, 'linhas=' + r.linhas);
check('traduz a cor guardada para o que significa', r.tudo.includes('Crítico') && !/\bred\b/.test(r.texto));
check('o mais urgente vem primeiro', r.tudo.indexOf('Crítico') < r.tudo.indexOf('Saudável'));
r = await pedir('/negocio/retencao?status=RED');
check('filtra os críticos', r.linhas === 1, 'linhas=' + r.linhas);

grupo('tarefas de recuperação');
r = await pedir('/negocio/tarefas');
check('abre', r.status === 200);
check('lista as 3', r.linhas === 3, 'linhas=' + r.linhas);
check('traduz prioridade e estado', r.tudo.includes('Alta') && r.tudo.includes('Pendente'));
r = await pedir('/negocio/tarefas?status=OPEN');
check('filtra as pendentes', r.linhas === 2, 'linhas=' + r.linhas);

grupo('relatórios de visita');
r = await pedir('/negocio/visitas');
check('abre', r.status === 200);
check('lista os 3', r.linhas === 3, 'linhas=' + r.linhas);
// Stored as 'Needs Promotion', with a space, which the label table keys for.
check('traduz um resultado com espaço no valor', r.tudo.includes('Só volta com promoção'));

grupo('inquéritos');
r = await pedir('/negocio/inqueritos');
check('abre', r.status === 200);
check('lista os 2', r.linhas === 2, 'linhas=' + r.linhas);
check('conta as respostas de cada um', /\b3\b/.test(r.tudo) && /\b0\b/.test(r.tudo));

grupo('livro de pontos');
r = await pedir('/negocio/clientes/c1');
check('o cliente abre', r.status === 200);
check('tem um livro de pontos', r.tudo.includes('Livro de pontos'));
check('traduz o tipo de movimento', r.tudo.includes('Ganhou') && r.tudo.includes('Trocou'));
check('o sinal do resgate aparece', r.tudo.includes('-100'));
check('mostra o saldo depois de cada movimento', r.tudo.includes('275'));

grupo('consumo do plano');
r = await pedir('/negocio/plano');
check('tem um painel de consumo', r.tudo.includes('Consumo'));
check('traduz a medida', r.tudo.includes('Respostas a inquéritos'));
check('mostra a percentagem usada', /84%/.test(r.tudo), '42 de 50');
check('sem limite não vira percentagem', /Sem limite/.test(r.tudo));

grupo('navegação');
r = await pedir('/negocio');
for (const seccao of ['Vendas', 'Marcações', 'Resgates', 'Bónus de retorno', 'Tarefas', 'Inquéritos']) {
  check('o menu leva a ' + seccao, r.tudo.includes(seccao));
}

grupo('quem entra onde');
const interno = await entrar(CONTAS.interno);
check('o interno entra na consola', interno.status === 200 && interno.corpo.area === 'admin', JSON.stringify(interno.corpo));
const ninguem = await entrar(CONTAS.ninguem);
check('quem não tem negócio nem claim é recusado', ninguem.status === 403, 'status=' + ninguem.status);
check('e não recebe cookie nenhum', !/maisum_admin_session/.test(ninguem.cookies));

grupo('terminar sessão');
const antes = await pedir('/negocio');
check('antes: o negócio abre', antes.status === 200);
const saida = await fetch(BASE + '/api/session', { method: 'DELETE', headers: { cookie } });
const limpo = (saida.headers.getSetCookie ? saida.headers.getSetCookie() : []).join(' ');
check('sair responde 200', saida.status === 200, 'status=' + saida.status);
check('o cookie é apagado', /maisum_admin_session=;/.test(limpo) && /Max-Age=0/i.test(limpo));
check('e continua httpOnly ao ser apagado', /HttpOnly/i.test(limpo));
cookie = '';
const depois = await pedir('/negocio');
check('depois: o negócio manda para o login', depois.status === 307 && /\/login/.test(depois.destino), depois.destino);

/* ------------------------------------------------------------------- o resumo */

console.log('\n' + '-'.repeat(60));
if (falhas.length === 0) {
  console.log(passaram + ' verificações, todas passaram.');
  process.exit(0);
}
console.log(passaram + ' passaram, ' + falhas.length + ' falharam:\n');
falhas.forEach((f) => console.log('  - ' + f));
process.exit(1);
