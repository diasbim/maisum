# MaisUm — Portal Web de Administração

Versão: 0.4 (RASCUNHO — a aguardar revisão, não aprovado para implementação)
Estado: **PENDENTE DE REVISÃO — NÃO IMPLEMENTAR**
Base: auditoria só de leitura do repositório no commit `60f5fd1`
Âmbito: portal de operações internas em `/admin/*` e a superfície de
autoatendimento do responsável do negócio.

---

## 0. Histórico de revisões

**v0.1** — Recomendava desbloquear o portal Flutter existente.

**v0.2** — Duas descobertas alteraram essa conclusão:

1. **O portal admin lê PostgreSQL. O app móvel escreve exclusivamente para
   Firestore. Hoje quase nada liga os dois** — e a tabela `merchants`, que
   alimenta o ecrã principal do portal, não tem nenhum escritor em todo o
   código (§3). Bloqueador mais grave, independente da escolha de frontend.
2. **O portal não partilha modelo de dados com o app móvel**, porque nem sequer
   partilha base de dados. O argumento de "reaproveitar os modelos Flutter" não
   se verifica (§6.1). Recomendação de frontend passou para Next.js.

**v0.3** — Análise da landing page (`docs/index.html`) contra o catálogo de
planos e as entitlements. Nova §4: o funil comercial é invisível ao portal, e
existem divergências entre o que é anunciado e o que é efetivamente
provisionado.

**v0.4** — As ações do lado da landing page passaram para
`docs/landing_page_recommendations.md`, que também confirma que a auditoria de
25 de agosto (`docs/WEBSITE_AUDIT.md`) foi substancialmente executada na
reescrita de 31 de agosto. Este plano mantém apenas o que é responsabilidade do
portal. A §4.3 ganhou uma causa raiz identificada: não existe fonte única do que
cada plano promete publicamente (Q8).

**v0.5** — Consola completa. Todas as superfícies do portal existem e as fases
5 e 6 estão implementadas, com seis endpoints de leitura novos na API para as
sustentar (§7). Três lacunas que o plano nunca tinha coberto foram fechadas:
não havia forma de ver os entitlements em vigor (só a contagem), de encontrar
um cliente para responder a uma disputa de pontos, nem de saber quem detém
acesso administrativo. A §9 perde Q1, respondida pela nova vista de acessos.
Continua em aberto o bloqueador de dados (Q2) e o CORS (B7).

**v0.6** — **Q2 respondida e B7 fechado.** Os negócios existem, em Firestore
`businesses`, não na tabela `merchants` — que continuava sem escritor. Passou a
ter um: `merchantProfilePostgresProjection`, um gatilho modelado no
`retentionDomainEventPostgresProjection` que já existia, mais um backfill para
os negócios anteriores. O bloqueador da §3 deixa de o ser.

O CORS passou de `cors: true` a uma lista explícita ancorada em
`maisum.tsintsivadigital.com`, configurável por `CORS_ALLOWED_ORIGINS`.

Pelo caminho: `admin.firestore.FieldPath` era indefinido sob o emulador, o que
partia os cinco handlers paginados. Passaram a importar `FieldPath` de
`firebase-admin/firestore`.

**v0.7** — **Consola migrada para Firestore.** Não existe PostgreSQL ligado em
produção: `.env.loyaltyos-fc4dd` não define `PG_CONNECTION_STRING`, que aparece
numa única linha em todo o repositório — a que a lê. Todos os endpoints `/admin`
devolviam 500 em produção.

Tudo o que a consola precisa já estava em Firestore, nos caminhos que o
`FirestoreSyncService._collectionMap` sincroniza. O router de administração
passou a lê-los e tem agora **zero** utilizações do `pool`. Sem junções: a lista
de negócios usa três *collection group queries* juntadas em memória, três
leituras por página em vez de três por negócio.

`admin_audit_events` era a única coisa sem casa em Firestore. Passou a coleção
de topo, fechada a clientes nas regras.

A projeção `businesses` → `merchants` da v0.6 foi retirada: já não há destino.

---

## 1. Resumo executivo

O que existe hoje:

- Um portal Flutter completo e testado (`AdminPortalShell`, 2 806 linhas), já
  desenhado como web-only.
- Treze endpoints `/admin/*` nas Cloud Functions, nove ligados ao cliente.
- Uma superfície web (`web/index.html`) que já se intitula "Portal de gestão".

O que impede o portal de funcionar ou de ser útil:

- **A camada de dados que o portal consulta está, na prática, vazia** (§3).
- **O funil comercial não existe no sistema** — todos os CTAs da landing page
  vão para uma caixa de WhatsApp, e o portal só conhece negócios já
  integrados (§4.1).
- **O que é anunciado diverge do que é provisionado** em pelo menos quatro
  pontos (§4.3).
- A autorização de admin é inconsistente entre Cloud Functions e regras do
  Firestore, e existe um bypass por chave estática (§5.3).
- O bundle Flutter web não arranca sequer (§5.2), embora isso deixe de importar
  se se adotar Next.js.

Ordem de importância: **resolver a arquitetura de dados → endurecer o acesso →
construir o frontend → ligar operações e reconciliação comercial.**

---

## 2. Estado atual verificado

### 2.1 No app Flutter

| Área | Localização | Estado |
|---|---|---|
| Shell do portal | `lib/features/admin_portal/presentation/admin_portal_shell.dart` | Completo, 2 806 linhas, ficheiro único |
| Secções | `AdminPortalSection` — overview, merchants, plans, operations, selfService | As 5 renderizam |
| Rotas | `lib/app/router.dart:302-338` | `/admin`, `/admin/merchants`, `/admin/merchants/:id`, `/admin/plans`, `/admin/operations`, `/admin/self-service` |
| Guarda de acesso | `resolveAdminPortalRedirect`, `lib/app/router.dart:149-161` | Web-only: admin interno → portal completo; responsável → só autoatendimento |
| Cliente API | `lib/features/admin_portal/data/admin_portal_api.dart` | 9 métodos |
| Modelos | `lib/features/admin_portal/domain/` | 4 modelos, `fromJson` escrito à mão |
| Claim de admin | `isInternalAdminProvider`, `lib/features/auth/presentation/auth_controller.dart:234` | Lê custom claims do ID token |
| Testes | `test/unit/admin_portal/` | 5 ficheiros: predicado de acesso + 4 parsers |

### 2.2 No backend

`functions/src/index.ts:470` monta o `adminRouter` atrás de `isAdminRequest`.
Todas as queries são `pool.query(...)` — SQL direto contra PostgreSQL.

Ligados ao cliente Flutter: `GET /admin/merchants`, `GET /admin/merchants/:id`,
`GET /admin/audit-events`, `GET /admin/plans`,
`GET /admin/operations/summary`, `POST /admin/plans`, `POST /admin/prices`,
`POST /admin/plans/:planCode/features`,
`POST /admin/merchants/:merchantId/entitlements`.

**Sem qualquer UI — só alcançáveis por `curl` com chave de admin:**

- `POST /admin/customer-core/business-customers/backfill`
- `POST /admin/customer-core/nfc-cards/backfill`
- `POST /admin/loyalty/ledger/backfill`
- `POST /admin/loyalty/ledger/reconcile`
- `POST /admin/retention/policies`
- `POST /admin/retention/classifications/scan`

Nota: as respostas são `data: result.rows` — linhas Postgres em bruto, sem tipo
nem contrato. Os modelos Dart espelham à mão uma lista de colunas SQL, e nada
verifica essa relação em nenhuma das direções.

---

## 3. Arquitetura de dados — o bloqueador crítico

### 3.1 Os dois armazenamentos

**Firestore — autoritativo, escrito pelo app móvel.**
`businesses/{merchantId}` e as subcoleções `customers`, `sales`, `rewards`,
`redemptions`, `app_users`, `domain_events`. A única implementação de
`SyncTransport` no app é `FirestoreSyncService`
(`lib/core/services/firestore_sync_service.dart:13`).

**PostgreSQL — consultado pelo portal admin.**
25 tabelas em `functions/sql/schema.sql`: `merchants`, `customers`, `sales`,
`app_users`, `subscription_state`, `plans`, `plan_prices`, `plan_features`,
`entitlements`, `usage_events`, `usage_balances`, `admin_audit_events`,
`retention_domain_events`, entre outras.

### 3.2 A única ponte que existe

`retentionDomainEventPostgresProjection` (`functions/src/index.ts:3009`) copia
`businesses/{merchantId}/domain_events/{eventId}` → `retention_domain_events`.
Mais nada.

Todas as outras escritas Postgres — `upsertCustomer`, `upsertSale`,
`upsertAppUser`, `upsertSubscriptionState`, `upsertRetentionMetric` — são
chamadas **apenas** a partir de `POST /sync/:entityType/:entityId`
(`functions/src/index.ts:1676`), o caminho REST legado que o app já não usa.
O `docs/backend_bootstrap_contract.md` confirma-o: *"The Flutter app remains
Firebase OTP plus Firestore by default, but these endpoints are the contract
for the new backend path behind feature flags."*

### 3.3 A consequência

Não existe **nenhum** `INSERT INTO merchants` em todo o código — apenas o
`CREATE TABLE`. E `GET /admin/merchants` é
`FROM merchants m LEFT JOIN subscription_state ... LEFT JOIN app_users ...
LEFT JOIN usage_balances`. Com `merchants` vazia, os `LEFT JOIN` não salvam
nada: **o ecrã principal do portal devolve lista vazia.**

Além disso `app_users.merchant_id REFERENCES merchants(id)`, pelo que os
próprios upserts falhariam por violação de chave estrangeira.

Classificando as tabelas por origem real dos dados:

| Categoria | Tabelas | Estado |
|---|---|---|
| Nativas do servidor (escritas pela API) | `plans`, `plan_prices`, `plan_features`, `entitlements`, `admin_audit_events`, `feature_flags`, `remote_config` | Funcionam |
| Projetadas do Firestore | `retention_domain_events` | Funciona (1 trigger) |
| Esperam o caminho `/sync` legado | `merchants`, `customers`, `sales`, `app_users`, `subscription_state`, `usage_*`, `recovery_*`, `visit_reports`, `surveys*` | **Sem alimentação** |

Os endpoints de *backfill* e *reconcile* listados em §2.2 existem precisamente
porque este problema de reconciliação já tinha sido antecipado.

### 3.4 Opções

**Opção D1 — O portal lê Firestore para as entidades autoritativas**
(negócios, clientes, vendas) e Postgres apenas para o que é nativo do servidor:
planos, preços, entitlements, auditoria, `retention_domain_events`.

- Sem pipeline novo; dados sempre corretos e autoritativos; reaproveita as
  regras de segurança existentes.
- Custo: Firestore não faz agregações. O `COUNT(DISTINCT ...) FILTER (...)` com
  quatro joins de `/admin/merchants` não se replica sem contadores
  desnormalizados. Pesquisa por texto é limitada.

**Opção D2 — Completar a projeção Firestore → Postgres**, estendendo o padrão
de `retentionDomainEventPostgresProjection` a `businesses`, `customers`,
`sales`. Postgres passa a ser o *read model* analítico; Firestore continua
autoritativo.

- É exatamente a arquitetura que o README já declara. O portal já está escrito
  contra Postgres. Agregações e pesquisa funcionam bem.
- Custo: um trigger por escrita (invocações, latência, custo), consistência
  eventual, e um backfill inicial — para o qual os endpoints já existem.

**Opção D3 — Dual-write do cliente** (app escreve Firestore *e* REST `/sync`).
**Não recomendada.** Num cliente offline-first, dual-write sem transação
distribuída significa divergência silenciosa decidida por um telemóvel sem
rede.

**Recomendação: D1 agora, D2 quando o volume justificar.** À escala de piloto
— dezenas ou centenas de negócios — ler Firestore diretamente é mais simples e
sempre correto. A projeção para Postgres é a resposta certa quando as queries
analíticas começarem a doer, e o caminho já está pavimentado.

**Consequência para o portal:** com D1, as queries de `adminRouter` para
merchants e o resumo de operações têm de ser reescritas contra Firestore. Isto
é trabalho de backend, contabilizado na Fase 1.

---

## 4. Alinhamento comercial com a landing page

Análise de `docs/index.html` (105 KB) contra `functions/sql/seed_plans.sql`,
`functions/sql/seed_plan_features.sql` e
`lib/features/subscription/domain/feature_keys.dart`.

### 4.1 O funil comercial é invisível ao portal

A landing page não capta leads. Todos os CTAs comerciais apontam para
`https://wa.me/258823262347` (5 links, 9 localizações distintas de CTA), e a
secção de planos diz explicitamente *"Conversa direta, sem formulário e sem
compromisso."*

Consequência: **todo o topo do funil vive numa única caixa de WhatsApp e não
existe em lado nenhum do sistema.** O portal só conhece negócios que já
concluíram o onboarding. Não há forma de responder a "quantas conversas
iniciadas viraram negócios ativos?", nem de saber quantos contactos estão em
negociação.

Existem 22 eventos nomeados de Plausible (`data-plausible-event`,
`data-cta-type`, `data-cta-location`) — portanto os cliques são medidos, mas de
forma anónima e num sistema separado, sem qualquer ligação ao negócio que
eventualmente se regista.

**Proposta:** uma noção mínima de *prospect* no portal — mesmo alimentada
manualmente pela pessoa que responde ao WhatsApp: contacto, origem do CTA,
estado da conversa, e ligação ao `merchantId` quando converte. Sem isto, o
portal mede operação mas não mede negócio.

### 4.2 Os preços são negociados caso a caso — o portal é a ferramenta comercial

A landing page recusa deliberadamente publicar preços: *"As condições são
confirmadas consigo, sem publicar preços antes de perceber a sua operação."*

Mas `seed_plans.sql` tem uma tabela de preços mensais em MZN:
`free` 0, `starter` 2000, `pro` 3500, `business` 5000, `growth` 5000.

Ou seja, existe preço de tabela **interno** e negociação **externa**. Isto
eleva a importância de `POST /admin/prices` e
`POST /admin/merchants/:merchantId/entitlements`: são o mecanismo através do
qual um acordo comercial é efetivamente provisionado.

O portal precisa, para essa parte: histórico de alterações de preço e de
entitlements por negócio (quem alterou, quando, porquê), e visibilidade do
**desvio face ao preço de tabela**. O trilho existe em `admin_audit_events`,
mas nunca é apresentado nesse enquadramento.

### 4.3 Divergências entre o anunciado e o provisionado

Quatro, todas verificadas:

| # | Anunciado na landing | Provisionado no sistema |
|---|---|---|
| 1 | "Gestão de equipa" listada como diferenciador do **Business** | Não existe nenhuma feature key para gestão de equipa. `staff_management_screen.dart` não referencia `FeatureKeys`, e `lib/app/router.dart` gate `/staff-management` apenas por `_ownerOnlyRoutes` (papel de responsável). **Todos os planos têm gestão de equipa.** |
| 2 | **Free** lista apenas perfis de clientes, registo de vendas, pontos e recompensas | `seed_plan_features.sql` dá `whatsapp_automation: true` ao Free. Capacidade concedida sem ser anunciada. |
| 3 | **Starter** promete "Mais capacidade para crescer" | `limit_value` é `NULL` em **todas** as linhas de `seed_plan_features.sql`. Nenhuma quota está configurada, apesar de `usage_balances.limit_value` existir e de `upsertPlanFeature` já aceitar `limitValue` e `unit`. A promessa de capacidade não tem contrapartida técnica. |
| 4 | A landing mostra **4 planos** | A base tem **5**: existe um plano `growth` (`Growth`, 5000 MZN — igual ao Business) em `seed_plans.sql:22` e em `seed_plan_features.sql`, que não é anunciado. |

Nenhuma destas é catastrófica isoladamente, mas em conjunto são um risco
comercial e potencialmente legal: são promessas públicas que o sistema não
cumpre, ou capacidades concedidas sem intenção.

**Causa raiz:** a tabela de planos vive como HTML dentro de um ficheiro de
105 KB, e o provisionamento vive em `seed_plans.sql` e `seed_plan_features.sql`.
Nada liga os dois, e a divergência só se descobre por leitura manual cruzada.

**Proposta, em duas partes:**

- *Do lado do site* — extrair a definição pública dos planos para um ficheiro
  estruturado que passe a gerar os cartões da landing page. Detalhe e opções em
  `docs/landing_page_recommendations.md` §2.
- *Do lado do portal* — um ecrã de reconciliação "anunciado vs provisionado" na
  secção de planos, confrontando esse ficheiro com a matriz plano ×
  funcionalidade que já vem de `GET /admin/plans` (Fase 5.1).

A primeira parte é pré-requisito da segunda: sem fonte declarada do que é
público (Q8), não há com o que reconciliar.

**Divisão de responsabilidades:** corrigir cada uma das quatro divergências é
decisão de produto, tratada em `docs/landing_page_recommendations.md` §1 (L1–L4).
Este plano cobre apenas torná-las visíveis e detetáveis em CI.

### 4.4 Notas menores

- A FAQ diz que *"a automação completa de lembretes ainda está em
  desenvolvimento"*, mas a feature key chama-se `whatsapp_automation` e está
  ativa em todos os planos. Divergência de nomenclatura, não de comportamento.
- O portal não mostra nada do funil (Plausible). Uma ligação para o dashboard
  Plausible a partir da visão geral resolve 80% do valor sem integração.
- **Fora de âmbito, mas registado:** o `README.md` afirma
  `applicationId: com.loyaltyos.loyaltyos`; o build
  (`android/app/build.gradle:34`) e o link da landing page usam
  `com.tsintsivadigital.maisum`. O README está desatualizado.

---

## 5. Bloqueadores

### 5.1 Dados (crítico)

Ver §3. Independente da escolha de frontend. **Nada no portal mostra dados
reais até isto estar resolvido.**

### 5.2 Build web em Flutter — *só relevante se se escolher Flutter*

Registados para completude; desaparecem com Next.js.

- **B1** — `lib/firebase_options.dart:9` é
  `if (kIsWeb) throw UnsupportedError('Web not supported.');`, e
  `lib/main.dart:61` chama-o no ramo `kIsWeb`. Rebenta antes do primeiro frame.
- **B2** — `lib/main.dart:34` chama `registerBackgroundSync()` sem guarda;
  `workmanager` não existe na lista de plugins web de
  `.flutter-plugins-dependencies`.
- **B3** — `sqflite` e `path_provider` também não existem em web. O
  `_OwnerSyncPanel` do autoatendimento lê `syncControllerProvider`, que é
  suportado por sqflite.
- **B4** — `lib/core/network/json_api_transport_web.dart` usa `dart:html`,
  já marcado `deprecated_member_use` no próprio ficheiro.

### 5.3 Segurança e autorização (crítico, independente do frontend)

- **B5** — `functions/src/index.ts:2933` aceita as claims `admin`, `is_admin`,
  `internal_admin`, `role=='admin'` e `role=='internal_admin'`.
  `firestore.rules:10-12` aceita apenas `admin`, `is_admin` e `role=='admin'`
  — **`internal_admin` não é honrado pelas regras**. Um admin autorizado pelas
  Functions é recusado pelo Firestore. Torna-se bloqueante com a Opção D1.
- **B6** — `hasValidAdminApiKey` permite que um header estático partilhado
  contorne toda a identidade.
- **B7** — `functions/src/index.ts:2716` é `cors: true` (qualquer origem).
- **B8** — Não existe ferramenta neste repositório para atribuir a claim
  `internal_admin`.

### 5.4 Entrega

- **B9** — `firebase.json` tem `hosting.public: "docs"` (site de marketing).
  Não há alvo para o portal, e `.github/workflows/deploy.yml` nunca corre
  `flutter analyze`, `flutter test` nem build.

---

## 6. Decisão de frontend

### 6.1 Porquê Next.js e não Flutter web

O argumento que sustentava a v0.1 — partilhar modelos de domínio com o app
móvel — não se verifica:

- O portal e o app **não partilham base de dados** (§3). O portal é uma
  superfície de relatório sobre Postgres; o app é Firestore + sqflite.
- Não existe contrato tipado. As respostas são linhas SQL em bruto, espelhadas
  à mão em Dart. A fonte de verdade do contrato é **TypeScript**, num pacote
  `functions/` que já corre `tsc --strict` com testes. Um portal Next.js pode
  importar esses tipos diretamente — o argumento de type-safety corre ao
  contrário do que a v0.1 assumia.
- A única parte que partilharia código — `/admin/self-service` — é redundante:
  os responsáveis já têm `subscription_admin_screen.dart` em
  `/subscription-admin` e `staff_management_screen.dart` em
  `/staff-management` no app móvel.

Acresce que uma consola de operações é feita de tabelas, filtros, formulários e
paginação — exatamente onde o Flutter web é mais fraco. O CanvasKit descarrega
alguns MB antes da primeira linha pintar (relevante em ligações moçambicanas), e
o render em canvas custa pesquisa na página, seleção nativa de texto,
copiar-colar de células e preenchimento automático de palavra-passe no login.

Do lado da segurança, Next.js com server components e Firebase Admin SDK
permite pôr a fronteira de autorização no servidor com cookies de sessão
`httpOnly`, em vez do modelo atual em que o cliente guarda um ID token. Com a
Opção D1 isto torna-se decisivo: uma página consulta Firestore *e* Postgres no
servidor e junta os resultados, sem expor nenhum dos dois ao browser.

**Quando eu recomendaria manter Flutter:** se o portal fosse só para o fundador,
cinco ecrãs de leitura, necessário esta semana, sem previsão de crescer.
Desbloquear o shell existente seriam 1–2 dias contra 2–4 semanas até paridade.
Não é o caso: já existem backfills, reconciliação de ledger e políticas de
retenção na API.

### 6.2 Custo honesto desta escolha

- Um segundo artefacto de deploy e um segundo caminho de CI.
- As ~2 800 linhas do shell Flutter passam a material de referência, não código.
- O toolchain TypeScript **não** é custo novo — já é mantido em `functions/`.

### 6.3 O que fazer ao código Flutter existente

Com Next.js, `lib/features/admin_portal/`, as rotas `/admin/*` em
`lib/app/router.dart` e o `resolveAdminPortalRedirect` tornam-se código morto
(já são inalcançáveis em mobile por desenho). Recomendo removê-los num PR
dedicado, **depois** de o portal Next.js atingir paridade, preservando os
modelos de `domain/` como referência para escrever os contratos TypeScript.
Manter os testes de `test/unit/admin_portal/` até esse momento.

---

## 7. Plano por fases

Fases 1–3 são pré-requisitos. As restantes podem ser reordenadas por prioridade
de produto.

### Fase 0 — Decisões (sem código)

- [ ] Confirmar a recomendação de dados: **D1** (§3.4).
- [ ] Confirmar a recomendação de frontend: **Next.js** (§6).
- [ ] Definir o hostname do portal (ex. `admin.maisum.co.mz`) — determina a
      lista de origens permitidas em CORS.
- [ ] Definir quem é admin interno e como a claim é atribuída (Q1).
- [ ] Decidir se `/admin/self-service` entra neste marco ou fica adiado (Q4).
- [ ] Decidir se a gestão de *prospects* entra neste marco (Q9).
- [ ] Decidir o destino do plano `growth` (Q10).
- [ ] Verificar se é necessária entrada em
      `docs/app_feature_decision_register.md` antes de implementar (Q5).

### Fase 1 — Fundação de dados

Sem isto o portal não tem o que mostrar. É trabalho de backend, em
`functions/`, e é independente do frontend.

1. Reescrever `GET /admin/merchants` e `GET /admin/merchants/:merchantId`
   contra Firestore (`businesses/{merchantId}`), mantendo em Postgres apenas o
   enriquecimento nativo do servidor: `subscription_state`, `entitlements`,
   `plan_*`.
2. Reescrever `GET /admin/operations/summary` do mesmo modo. As métricas de
   `AdminOperationsSummary` (`merchant_count`, `active_staff_count`,
   `usage_events_24h`, `open_recovery_task_count`, `visit_reports_24h`,
   `survey_responses_24h`) têm de ser reclassificadas uma a uma por origem —
   algumas são nativas de Postgres e continuam válidas.
3. ~~Definir contratos TypeScript explícitos para todas as respostas
   `/admin/*`~~ — **feito.** `functions/src/admin_api_contracts.ts` define os
   DTOs e os mappers; os cinco endpoints de leitura deixaram de devolver
   `data: result.rows`. Normaliza duas coisas que os clientes tinham de
   adivinhar: colunas `BIGINT` (todos os timestamps deste schema) chegavam do
   `node-pg` como **string** e passam a ser `number | null`; colunas ausentes e
   `NULL` passam a ser sempre `null`, nunca `undefined`, para a chave sobreviver
   à serialização. Verifiquei que a mudança é retrocompatível com o cliente
   Flutter existente — todos os seus leitores (`_readInt`, `_readDate`,
   `_readBool`) já aceitavam `int`, `num` e `String`. 19 testes novos.
4. Decidir o destino das tabelas Postgres órfãs da §3.3: remover do schema, ou
   manter documentadas como reservadas para o caminho de backend futuro.
5. Documentar a decisão de arquitetura de dados em `docs/`.

Aceitação: `GET /admin/merchants` devolve os negócios reais de um projeto de
teste; contratos tipados publicados; testes em `functions/` a cobrir as novas
queries.

### Fase 2 — Endurecimento de acesso

Fase de segurança, a rever isoladamente.

1. ~~**Reconciliar as duas definições de admin** (B5)~~ — **feito.**
   `functions/src/admin_access.ts` é agora o predicado canónico; `index.ts`
   delega nele, `firestore.rules` passou a aceitar `internal_admin` e
   `role=='internal_admin'`, e normaliza o `role` com `trim().lower()` como o
   módulo. `admin_access.test.ts` lê o `firestore.rules` e falha se divergirem —
   verifiquei que a deteção funciona removendo a claim de propósito. O
   predicado Dart já coincidia e ficou com referência cruzada.
2. ~~**Restringir `ADMIN_API_KEY`** (B6)~~ — **feito, com alteração de
   comportamento.** A chave passou a ser aceite apenas nos caminhos de
   `ADMIN_API_KEY_PATHS` (backfills, reconcile, scan). Deixou de servir leituras
   e escritas comerciais. Além disso é resolvida **uma só vez** no middleware e
   guardada em `req.adminKeyGranted`: antes, `isAdminRequest()` relia o header
   em `requestCanAccessMerchant()`, pelo que um utilizador autenticado com o
   header podia contornar o isolamento entre negócios em caminhos fora de
   `/admin/*`. A comparação passou a ser em tempo constante.
3. **Fechar o CORS** (B7) para a origem do portal, pelo menos em `/admin/*`.
   **Pendente** — depende do hostname (Fase 0).
4. ~~**Ferramenta de atribuição de claims** (B8)~~ — **feito.**
   `functions/scripts/admin_claims.js` com `--list`, `--grant`, `--revoke`.
   Exige `--yes`, valida antes de tocar na rede, revoga refresh tokens ao
   remover acesso, e limpa todas as grafias aceites em vez de só uma. Importa o
   módulo canónico para não duplicar a constante. **A persistência em
   `admin_audit_events` ficou de fora até Q2 estar respondida** — a tabela é
   PostgreSQL e não faz sentido escrever nela antes de confirmar o seu estado;
   por agora o script imprime uma linha `AUDIT` para registo manual.
5. **Política de sessão**: timeout de inatividade e reautenticação em mutações
   privilegiadas (overrides de entitlement, escrita de planos e preços).
   **Pendente** — pertence ao frontend (Fase 3).
6. **Cobertura de auditoria**: confirmar que todos os endpoints mutantes
   escrevem em `admin_audit_events`. O portal já mostra estes eventos, pelo que
   lacunas são invisíveis por omissão. **Pendente.**

Aceitação: não-admin autenticado recebe 403 da API *e* é redirecionado; admin
interno lê Firestore e chama Functions com a mesma claim; CORS restrito;
concessão de claim documentada e auditada.

### Fase 3 — Esqueleto Next.js e autenticação — **implementada**

Em `admin/`. Ver `admin/README.md`. **Desvio face ao que esta fase previa
(ponto 4):** o portal **não** acede a Firestore e PostgreSQL diretamente —
chama a API `/admin/*` das Cloud Functions no servidor, reencaminhando o ID
token do utilizador. Razões: a autorização fica num só sítio (já endurecida na
Fase 2), os contratos já existem lá, cada ação continua atribuível a uma pessoa
na auditoria, e o portal fica **independente da Q2** — quando as queries forem
reescritas, não muda nada aqui.


1. App Next.js (App Router) em `admin/` no mesmo repositório, ou repositório
   próprio — decidir na Fase 0 (Q6).
2. Autenticação: Firebase Auth no cliente, troca por **cookie de sessão
   `httpOnly`** verificado no servidor com o Admin SDK. Para pessoal interno,
   recomendo email/SSO em vez de OTP por telefone com reCAPTCHA (Q3).
   `AppConstants.allowTestPhoneAuthBypass` não pode ter equivalente aqui.
3. Middleware que verifica a claim de admin em todas as rotas `/admin/*`, antes
   de renderizar.
4. Acesso a dados em server components: Admin SDK para Firestore e `pg` para
   Postgres, ambos no servidor. O browser nunca fala com nenhum dos dois.
5. Consumir os contratos tipados de `functions/src/admin_api_contracts.ts`
   (Fase 1.3, já concluída). Decidir como: referência de path do TypeScript
   entre pacotes, ou um passo que copie os tipos. Preferir o primeiro — a
   duplicação é exatamente o que a Fase 1.3 veio eliminar.
6. `noindex, nofollow` e `robots.txt` na origem do portal.

Aceitação: login funcional, sessão em cookie, não-admin bloqueado no
middleware, uma página a ler dados reais.

### Fase 4 — Superfícies de leitura — **implementada**

Rotas: `/admin` (visão geral), `/admin/merchants` (diretório com pesquisa e
paginação), `/admin/merchants/[merchantId]` (detalhe), `/admin/plans`
(catálogo) e `/admin/audit` (trilho paginado). Navegação entre secções no
cabeçalho. Estados vazio/erro centralizados em `src/app/admin/ui.tsx`, para
não voltarem a divergir como no shell Flutter.

**Paginação ligada**, que era a lacuna principal: pesquisa e `offset` vivem na
URL, portanto uma vista filtrada é partilhável e sobrevive a um reload.
Verificado com 37 negócios — página 1 mostra 1–25, página 2 mostra 26–37.

Um negócio inexistente devolve 404; uma falha da API **não** é apresentada como
"não existe", para não mandar o operador investigar um problema de dados que é
na verdade uma indisponibilidade.


Paridade com o que o shell Flutter já mostra: visão geral com métricas,
diretório de negócios, detalhe do negócio, catálogo de planos, trilho de
auditoria.

Incluir o que falta hoje: **paginação**. `getMerchants` e `getAuditEvents`
aceitam `limit`/`offset`, mas a UI atual não passa nenhum e mostra só as
primeiras 50 linhas. Tabelas com ordenação, filtros e estados vazio/erro
consistentes.

### Fase 5 — Reconciliação comercial — **implementada**

Decorre da §4. Barata, e é o que transforma o portal de painel de leitura em
ferramenta comercial.

1. **Matriz "anunciado vs provisionado"** (§4.3): a matriz plano ×
   funcionalidade de `GET /admin/plans` confrontada com `docs/plans.json`.
   Assinalar divergências. **Desbloqueada** — a fonte declarada e a lógica de
   reconciliação já existem em `tool/check_plan_catalog.dart`, incluindo
   resolução transitiva da herança entre planos; o portal reaproveita as regras,
   apresentando-as sobre dados vivos em vez do seed. Corrigir cada divergência é
   trabalho de produto (L1–L5), não do portal.
2. **Histórico comercial por negócio** (§4.2): alterações de preço e de
   entitlements, com autor, data e desvio face ao preço de tabela. Os dados já
   estão em `admin_audit_events`; falta o enquadramento.
3. **Editor de quotas**: `upsertPlanFeature` já aceita `limitValue` e `unit`,
   mas nenhuma quota está configurada (§4.3, ponto 3). Expor o campo, ou
   decidir explicitamente que as quotas não são usadas e remover a promessa da
   landing page.
4. **Prospects** (se Q9 for afirmativo): contacto, origem do CTA, estado da
   conversa, ligação ao `merchantId` quando converte. Entrada manual é
   suficiente para começar. Depende de a origem ser recuperável do lado do
   site — ver `docs/landing_page_recommendations.md` §3, que propõe fechá-la
   sem introduzir formulário, respeitando a decisão registada em
   `WEBSITE_INFORMATION_ARCHITECTURE.md`.
5. **Ligação ao Plausible** a partir da visão geral (§4.4). Um link, não uma
   integração.

### Fase 6 — Superfície de operações — **implementada**

Ligar os seis endpoints órfãos da §2.2 como um painel explícito e auditável de
"executar operação", não botões soltos:

- Backfill de customer-core (business-customers, cartões NFC)
- Backfill e reconciliação do ledger de fidelização
- Upsert de política de retenção
- Varrimento de classificação

Cada um precisa de âmbito por negócio, um passo de confirmação que nomeie o
raio de impacto, estado em execução/resultado, e o evento de auditoria
resultante devolvido ao ecrã. São operações em lote sobre o ledger canónico — a
UI tem de o tornar óbvio.

### Fase 7 — Testes

- Testes de componente por secção contra uma camada de dados falsa.
- Testes do middleware de autorização em toda a matriz {admin, responsável,
  staff, anónimo}.
- Testes em `functions/` para a autorização do `adminRouter`, incluindo a
  reconciliação de claims da Fase 2.1.
- Testes das regras do Firestore para o predicado de admin.
- Testes das novas queries da Fase 1.
- Teste que falha se a matriz de entitlements divergir da fonte declarada da
  landing page (Fase 5.1) — transforma a §4.3 numa regressão detetável.

### Fase 8 — CI e entrega

- Workflow para o portal: lint, typecheck, testes, build.
- Alvo de Firebase Hosting separado do site `docs/` (configuração multi-site),
  ou Vercel — decidir na Fase 0 (Q7).
- Canais de pré-visualização em PR; promoção manual para produção.
- Estender o workflow existente com `flutter analyze --no-fatal-infos` e
  `flutter test`, que hoje nunca correm em CI.

### Fase 9 — Runbook e limpeza

- Nota em `docs/`: como conceder e revogar `internal_admin`, o que faz cada
  operação da Fase 6 e quando a executar, como ler o trilho de auditoria, e o
  caminho de incidente se um backfill correr mal.
- PR dedicado a remover `lib/features/admin_portal/`, as rotas `/admin/*` e
  `resolveAdminPortalRedirect`, depois de atingida a paridade (§6.3).
- Corrigir o `applicationId` desatualizado no README (§4.4).

---

## 8. Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| Reescrita das queries para Firestore perde agregações que o SQL fazia | Métricas da visão geral degradadas ou lentas | Fase 1.2 reclassifica métrica a métrica; contadores desnormalizados onde necessário; D2 quando o volume justificar |
| Divergência entre Firestore e Postgres em dados que existem em ambos | Números do portal não batem com o app | Fase 1.4 decide explicitamente o destino das tabelas órfãs |
| Claim não reconciliada entre regras e Functions | Admin chama a API mas não lê Firestore; falhas parciais confusas | Fase 2.1, predicado único com testes — bloqueante com D1 |
| Promessas públicas não cumpridas pelo sistema (§4.3) | Risco comercial e potencialmente legal | Fase 5.1 torna-as visíveis; Fase 7 torna-as uma regressão detetável |
| Funil comercial só existe no WhatsApp | Impossível medir conversão ou prever receita | Fase 5.4, se Q9 for afirmativo |
| Operações da Fase 6 executadas no negócio errado | Ledger de fidelização corrompido | Âmbito explícito, confirmação que nomeia o alvo, eco de auditoria |
| `cors: true` com chave de admin estática | API admin alcançável de qualquer origem com um header vazado | Fase 2.2 / 2.3 |
| Portal Next.js e app móvel divergem no contrato | Erros em runtime | Contratos TypeScript da Fase 1.3 como fonte única |
| Dois artefactos de deploy | Sobrecarga de manutenção | Aceite conscientemente (§6.2) |

---

## 9. Perguntas em aberto

- **Q1** — Como é atribuída hoje a claim `internal_admin`? Não encontrei script,
  Function nem procedimento documentado neste repositório.
- **Q2** — Confirmar qual é o estado real dos dados em produção no PostgreSQL.
  A análise da §3 é estática, feita sobre o código; se existir um caminho de
  povoamento fora deste repositório (job manual, ETL, backend Spring Boot
  anterior), a §3.3 muda. **Esta é a verificação mais importante antes de
  aprovar o plano.**
- **Q3** — Login do pessoal interno: OTP por telefone com reCAPTCHA, ou
  email/SSO?
- **Q4** — `/admin/self-service` entra neste marco? É redundante com os ecrãs
  móveis existentes (§6.1) e traz utilizadores externos para a mesma origem.
- **Q5** — O portal precisa de entrada em
  `docs/app_feature_decision_register.md` antes de implementar?
- **Q6** — Next.js no mesmo repositório (`admin/`) ou repositório separado?
- **Q7** — Alojamento: Firebase Hosting (multi-site) ou Vercel?
- ~~**Q8** — Qual passa a ser a fonte declarada do que cada plano promete
  publicamente?~~ **Resolvida.** É `docs/plans.json`, validada por
  `dart run tool/check_plan_catalog.dart` contra a landing page e contra
  `functions/sql/seed_plan*.sql`. A Fase 5.1 está desbloqueada. As decisões de
  produto associadas (L1–L5) continuam abertas em
  `docs/landing_page_recommendations.md` §6, e estão registadas no bloco
  `openDecisions` do próprio `plans.json`.
- **Q9** — A gestão de *prospects* (§4.1) entra neste marco, ou o funil
  continua no WhatsApp por agora?
- **Q10** — O que fazer ao plano `growth` (§4.3, ponto 4): anunciar, desativar,
  ou manter como plano interno? Se for interno, o portal deve marcá-lo como
  tal.

---

## 10. Fora de âmbito

- Qualquer alteração ao motor de sincronização offline-first do app móvel.
- Superfícies web viradas ao cliente final.
- Substituição do site de marketing em `docs/`.
- Dashboards de BI para além das métricas já existentes em
  `AdminOperationsSummary`.
- Corrigir as divergências da §4.3 no produto — o portal torna-as visíveis;
  a decisão sobre cada uma é de produto, e está em
  `docs/landing_page_recommendations.md` §1.
- Alterações à landing page em si — ver
  `docs/landing_page_recommendations.md`.

---

## 11. Sequenciamento

Fase 0 (decisões) → Fase 1 (dados) → Fase 2 (segurança) são estritamente
ordenadas: sem a Fase 1 o portal não tem dados, e sem a Fase 2 não pode ser
exposto. A Fase 3 pode começar em paralelo com a Fase 2 usando dados de teste.
A Fase 5 depende de Q8. As Fases 7 e 8 correm ao lado das Fases 4 a 6, não
depois.
