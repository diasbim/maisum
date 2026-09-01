# Portal de administração MaisUm

Portal de operações internas. Next.js (App Router), TypeScript, Firebase Auth.

Contexto e decisões: `docs/web_admin_portal_code_plan.md`.

## Arranque

```bash
cd admin
npm install
cp .env.example .env.local   # preencher
npm run dev                  # http://localhost:3000
```

## Como está montado

**O portal não fala com PostgreSQL nem com Firestore.** Chama a API
`/admin/*` das Cloud Functions, no servidor, reencaminhando o ID token de quem
está autenticado.

Isto é deliberado:

- A autorização fica num só sítio, já endurecida (paridade da claim de admin,
  `ADMIN_API_KEY` restringida aos caminhos de automação).
- Os contratos de resposta estão definidos e testados em
  `functions/src/admin_api_contracts.ts`.
- Fica independente da questão em aberto sobre os dados em PostgreSQL (Q2 no
  plano). Quando essas queries forem reescritas, o portal não muda.
- Cada ação continua atribuível a uma pessoa no trilho de auditoria: o portal
  não tem credencial própria.

### Sessão

1. O browser autentica com email e palavra-passe (Firebase Auth) e obtém um ID
   token.
2. O token vai para `POST /api/session`, que o verifica com o Admin SDK, exige a
   claim de admin, e guarda-o num cookie **httpOnly**. Nenhum script na página
   lhe acede.
3. `SessionRefresher` reenvia o token a cada `onIdTokenChanged`, portanto o
   cookie acompanha a rotação horária dos tokens.
4. `src/middleware.ts` apenas verifica se o cookie existe, para redirecionar
   cedo. **Não é a barreira de segurança** — cada página em `/admin` chama
   `getAdminSession()`, que verifica o token e a claim no servidor.

`verifySessionToken` usa `checkRevoked: true`, portanto revogar acesso com
`functions/scripts/admin_claims.js --revoke` tem efeito imediato, não só quando
o token expirar.

### Predicado de admin duplicado

`src/lib/admin-claims.ts` repete `functions/src/admin_access.ts` porque o
bundler do Next não resolve imports de runtime fora da raiz da app. A
duplicação está guardada: `functions/src/admin_access.test.ts` lê este ficheiro
e falha se deixar de aceitar o mesmo conjunto de claims — tal como faz para o
`firestore.rules`.

Os **tipos** dos contratos são importados diretamente
(`@contracts/admin_api_contracts`), sem duplicação: são `import type`, apagados
na compilação, portanto nunca chegam a precisar de resolução em runtime.

## Comandos

```bash
npm run dev        # servidor de desenvolvimento
npm run build      # build de produção
npm run typecheck  # tsc --noEmit
```

## Estado

Consola completa. Onze superfícies:

| Secção | Rota | O que faz |
| --- | --- | --- |
| Visão geral | `/admin` | métricas agrupadas, negócios e auditoria recentes |
| Negócios | `/admin/merchants` | procura, filtro por estado, paginação |
| Detalhe | `/admin/merchants/[id]` | resumo, entitlements, auditoria do negócio |
| Planos | `/admin/plans` | catálogo e edição de planos, preços e funcionalidades |
| Reconciliação | `/admin/plans/reconciliacao` | anunciado contra provisionado |
| Clientes | `/admin/customers` | procura por telefone, cartão ou id |
| Livro de pontos | `/admin/customers/[id]` | entradas e saldo num negócio |
| Cartões NFC | `/admin/nfc` | consulta de cartão ou dos cartões de um cliente |
| Operações | `/admin/operations` | quatro trabalhos de manutenção |
| Retenção | `/admin/retention` | política e varrimento de classificações |
| Acessos | `/admin/access` | administradores da plataforma e contas de equipa |

### Como as páginas estão construídas

**Cada painel tem a sua fronteira `Suspense`.** As consultas vão para tabelas
diferentes e a mais lenta já não segura as outras: as métricas aparecem
primeiro e as tabelas preenchem por baixo. Os esqueletos têm o tamanho do
conteúdo que substituem, para a página não saltar quando os dados chegam.

**Filtros e procuras vivem no URL, não em estado de componente.** Uma vista
filtrada é colável numa conversa, recarregável e marcável — que é como um
operador passa um problema a outro.

**As mutações são server actions.** O cookie de sessão é lido no servidor e o
ID token nunca chega ao browser. Não existe um único `fetch` do cliente para a
API de administração.

**Trabalhos de manutenção simulam por omissão.** A caixa *Aplicar* é o único
controlo que altera dados de produção, e está destacada como tal; a mensagem de
resultado diz qual dos dois modos correu.

### Fronteiras deliberadas

**Não há listagem de clientes.** O id canónico é um HMAC do telefone, portanto
um telefone resolve para um registo sem varrimento — e não existe consulta que
enumere clientes por nome. Uma consola que não consegue enumerar a base de
clientes também não a consegue extrair.

**Os identificadores de cartão nunca saem inteiros do servidor.** Um UID é o
que um leitor apresenta para identificar um cliente; imprimi-lo tornaria o
ecrã de apoio uma fonte de credenciais utilizáveis. A API devolve os últimos
quatro caracteres.

**Conceder e revogar acesso administrativo continua na linha de comandos**
(`functions/scripts/admin_claims.js`). A vista de acessos responde a quem tem,
não concede. Revogar tem efeito imediato: a sessão verifica cada pedido contra
os tokens revogados.

### Por fazer

- **Q2**, o bloqueador de dados: não existe nenhum escritor para a tabela
  `merchants`. Se estiver vazia em produção, as superfícies de leitura ficam
  vazias — os negócios visíveis localmente são semeados.
- **B7**, CORS restrito à origem do portal. Depende do hostname.
- Fases 7 a 9: testes de ponta a ponta, CI e entrega, runbook.

## Design system

Os tokens vêm de `lib/designsystem.html` e vivem em `src/app/globals.css`:
cor (navy/dourado em `oklch`), tipografia (Bricolage Grotesque + Outfit),
raio, sombra, movimento, botões, campos, badges e cards.

Duas decisões ao aplicá-lo:

- **Só a parte genérica.** Esse ficheiro traz componentes de outro produto
  (job cards, mestre cards, testemunhos, passos de progresso, FAQ) que não têm
  lugar numa consola de operações. Ficaram de fora.
- **Só tema claro.** O sistema define uma única paleta clara. Inventar valores
  escuros poria o portal fora da marca, por isso `color-scheme: light`.

O sistema não define tabelas; as que existem seguem as suas superfícies e
neutros (cabeçalho `--off`, limites `--g100`, cartão sem padding via
`.card--flush`).

As fontes são carregadas por `next/font/google`, portanto ficam auto-hospedadas
no build — sem pedidos ao Google por cada visita e sem flash de fonte de
recurso.
