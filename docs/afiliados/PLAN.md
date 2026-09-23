# MaisUm Afiliados — Plano de implementação

**Fase original:** 0 — Avaliação

**Estado original:** A aguardar aprovação antes da Fase 1

**Estado atual (2026-09-15):** Fases 1-9 concluídas. O registo pós-implementação
fica em §15, preservando este cabeçalho como histórico da avaliação inicial.

**Data:** 2026-09-15

**Fonte:** `../MaisUm_Afiliados_Agent_Prompt.md`

## 1. Objetivo e trabalho do utilizador

O responsável do negócio gere quem indica novos clientes e aprova recompensas; o operador de caixa valida, opcionalmente, um código durante a venda; depois ambos veem o estado real da indicação sem interromper o fluxo normal de fidelização.

### Ação principal por superfície

| Superfície | Utilizador | Ação principal |
| --- | --- | --- |
| Nova venda | Operador de caixa | Confirmar venda |
| Lista de afiliados | Responsável do negócio | Adicionar afiliado |
| Novo afiliado | Responsável do negócio | Criar afiliado |
| Detalhe do afiliado | Responsável do negócio | Partilhar código |
| Configuração do código | Responsável do negócio | Guardar alterações |
| Recompensas pendentes | Responsável do negócio ou administrador | Aprovar recompensa |
| Métricas | Responsável do negócio | Consultar desempenho |
| Diretório global | Administrador interno | Gerir afiliado |

Uma venda sem código continuará com os mesmos passos, persistência e tempo de execução atuais.

### Fora do âmbito

Não serão implementados pagamentos automáticos, M-Pesa/eMola, carteira, login ou portal do afiliado, marketplace, hierarquia/MLM, negociação de comissão, campanhas, tracking publicitário, deteção de fraude por IA, app de cliente, multi-filial, contabilidade ou leaderboard.

## 2. Estado do repositório verificado

### 2.1 Orientações e documentação

- Não existem `AGENTS.md` ou `CLAUDE.md` no repositório.
- `README.md` define o Flutter como aplicação operacional, offline-first, com Firestore como armazenamento remoto atual.
- `docs/backend_bootstrap_contract.md` confirma que o transporte REST/PostgreSQL é um caminho alternativo atrás de flags; não é o caminho normal atual.
- `admin/README.md` confirma que o portal Next.js chama apenas a API das Cloud Functions e não acede diretamente ao Firestore ou PostgreSQL.
- `docs/web_admin_portal_code_plan.md` descreve a separação entre Firestore autoritativo e PostgreSQL analítico. Algumas referências históricas a consultas SQL já foram substituídas no código por leitores Firestore.
- `docs/app_feature_decision_register.md` e `docs/feature_decision_framework.md` são as superfícies de governação que deverão receber a decisão final da funcionalidade na Fase 9.

### 2.2 Stack efetiva

| Camada | Stack e convenções atuais |
| --- | --- |
| Aplicação móvel | Flutter, Dart, Riverpod, GoRouter, Freezed/JSON, SQLite (`sqflite`), Workmanager, Firebase Auth/Firestore, `url_launcher` |
| Backend | Node.js 22, TypeScript, Express, Firebase Functions/Admin SDK, Firestore e `pg` |
| Portal | Next.js 16 App Router, React 19, TypeScript, server components e server actions |
| Dados locais | Migrações SQLite incrementais em `lib/core/database/app_migrations.dart`; versão atual no código: 29 |
| Dados remotos operacionais | Firestore, sobretudo `businesses/{merchantId}/...` |
| Dados analíticos/legados | PostgreSQL por `functions/sql/schema.sql` e pelo caminho REST de sync |
| Testes | `flutter_test`, testes Dart de integração, Node test runner para Functions e portal |

Não há ORM, framework de validação HTTP, rate limiter ou runner formal de migrações SQL. Não será introduzida uma dependência apenas para esta funcionalidade.

### 2.3 Pontos de extensão existentes

- A venda local, os pontos normais do cliente e a fila de sync são persistidos numa transação por `SaleRepository`.
- `SyncService`, `SyncDao`, `FirestoreSyncService` e `BackgroundSync` já cobrem fila, tentativas, reconciliação e sincronização ao recuperar conectividade.
- O Customer Core já normaliza telefone e faz associação por telefone/identidade.
- O saldo confirmado do cliente é projetado pelo `loyalty_ledger`; `total_points` é compatibilidade.
- O Retention Engine já tem regras, registo idempotente de execuções e o gancho de venda concluída.
- A fila `notification_queue` já guarda tentativas e erros no dispositivo; o backend aceita enfileiramento idempotente, mas não possui consumidor com retry e entrega automática.
- A auditoria administrativa já passa por `recordAuditEvent`.
- O backend já separa rotas `/admin` e `/merchant`, com autenticação Firebase e isolamento por negócio.
- O portal já possui componentes reutilizáveis de página, painel, cartões, métricas, tabelas, formulários, alertas, estados vazios e esqueletos.
- O design system Flutter já fornece `MaisumButton`, `MaisumTextField`, `MaisumSurface`, `MaisumModal`, `MaisumToast`, `LoadingButton`, `MaisumAppBar`, `MaisumSheetHeader` e `ValidationState`.

### 2.4 Lacunas confirmadas

1. `Sale` contém apenas `amount`, `points`, itens e metadados de confirmação/cancelamento. Não representa valor bruto, desconto, tipo/valor do benefício ou código.
2. As regras Firestore de venda rejeitam campos fora do conjunto atual.
3. A fila de sync não possui `idempotencyKey` explícita nem todos os metadados exigidos pelo plano.
4. Não existe serviço autoritativo para conceder pontos promocionais ao cliente; há leitura do ledger e mutações locais, mas a nova concessão deve ser server-owned.
5. Não existe consumidor backend da fila WhatsApp com retry.
6. Não existe rate limiting de pedidos HTTP.
7. Não existem entidades, contratos, regras, índices ou testes de afiliados.
8. O mecanismo de migração SQLite só executa `up`; o SQL PostgreSQL é hoje um schema idempotente, não uma sequência formal de migrations.

### 2.5 Defaults preservados

| Configuração | Valor inicial |
| --- | --- |
| `firstVisitOnly` | `true` |
| Validade do código | 30 dias desde a criação |
| `usageLimit` | `null` |
| Percentagem permitida | 1–50% |
| `affiliateFirstSaleRewardPoints` | obrigatório ao ativar afiliados |
| `affiliateReturnRewardEnabled` | `false` |
| `affiliateReturnRewardPoints` | configurável por negócio |
| `returnWindowDays` | 30 desde a primeira venda qualificável |
| `affiliateRewardApprovalRequired` | `true` |

## 3. Decisões

### D1 — Autoridade dos dados

O Firestore continuará autoritativo para vendas, clientes, afiliados, códigos, atribuições, recompensas e eventos operacionais. SQLite será a projeção local offline. PostgreSQL receberá tabelas/projeções para análise e compatibilidade do backend, mas nunca participará da transação crítica da venda.

Motivo: este é o caminho utilizado pelo produto em produção e evita um dual-write controlado pelo telemóvel.

### D2 — Organização no Firestore

Serão usadas coleções server-owned:

```text
affiliates/{affiliateId}
affiliate_code_lookup/{normalizedCode}
businesses/{merchantId}/affiliate_merchants/{affiliateId}
businesses/{merchantId}/affiliate_codes/{codeId}
businesses/{merchantId}/affiliate_attributions/{attributionId}
businesses/{merchantId}/affiliate_rewards/{rewardId}
businesses/{merchantId}/affiliate_events/{eventId}
businesses/{merchantId}/affiliate_fraud_signals/{signalId}
businesses/{merchantId}/affiliate_rate_limits/{bucketId}
```

- O documento global do afiliado garante identidade única por telefone normalizado.
- `affiliate_code_lookup` usa o código normalizado como chave e permite unicidade/collision retry numa transação.
- O vínculo afiliado–negócio e o código usam identificadores determinísticos para garantir um único registo por par.
- A app e o portal nunca escrevem diretamente nessas coleções; todas as mutações passam pelas Cloud Functions.
- As regras Firestore negarão acesso direto e os índices cobrirão as consultas aprovadas.

### D3 — Identidade e privacidade

- Reutilizar a normalização moçambicana já existente.
- Derivar a identidade global do afiliado no servidor a partir do telefone normalizado, usando o mesmo padrão HMAC da identidade canónica quando aplicável.
- Nunca usar o telefone completo em logs, chaves de idempotência, métricas ou eventos analíticos.
- Não haverá eliminação física no MVP: desativação/suspensão preserva auditoria e histórico.

### D4 — Semântica monetária da venda

Foi solicitada decisão ao utilizador porque o modelo atual não suporta desconto; não houve resposta disponível. Fica adotada, sujeita à aprovação deste plano, a opção mais compatível:

- `amount` mantém o significado de valor líquido efetivamente pago.
- Uma venda com benefício monetário adiciona `gross_amount`, `referral_benefit_type`, `referral_benefit_value`, `referral_benefit_amount`, `affiliate_code_id` e o estado de confirmação da indicação.
- Vendas sem código mantêm o payload atual; os novos campos são nulos/ausentes e `amount` não muda.
- Pontos normais de fidelização são calculados sobre `amount`, isto é, o valor líquido.
- Percentagens são calculadas em centavos no servidor e arredondadas para a menor unidade monetária antes da persistência.
- `POINTS` não altera `amount`; cria uma entrada promocional separada no ledger do cliente.

### D5 — Venda online com código

Será introduzido um comando server-owned e idempotente para a venda com indicação. A transação Firestore:

1. bloqueia logicamente os documentos por meio da transação;
2. repete toda a validação;
3. cria a venda e o benefício/ledger;
4. cria atribuição e recompensa, quando aplicável;
5. incrementa o uso apenas para uma aquisição confirmada;
6. grava eventos e auditoria;
7. devolve a projeção canónica para o SQLite.

Uma rejeição de regra não grava a venda. A interface preserva os dados e oferece continuar a mesma venda sem o código. Falha de rede muda explicitamente para o caminho offline quando o cache permite.

Vendas sem código continuam pelo caminho local + sync atual.

### D6 — Pontos do cliente e pontos do afiliado

- Benefícios `POINTS` do cliente serão entradas server-owned no `loyalty_ledger`, com origem e chave de idempotência próprias.
- Recompensas do afiliado nunca serão gravadas no ledger do cliente.
- O saldo do afiliado será a soma de recompensas `APPROVED` com `valueType = POINTS`.
- O MVP não expõe pagamento, carteira nem conversão monetária.

### D7 — Serviços de domínio

O backend usa funções e módulos, não classes de serviço. Os nomes propostos no prompt serão implementados como funções puras e módulos coesos:

- gestão e vínculo de afiliados;
- geração e gestão de códigos;
- validação e cálculo de benefício;
- atribuição e idempotência;
- criação/aprovação/cancelamento de recompensa;
- métricas;
- reação a retorno e reversão.

Handlers HTTP apenas autenticam, validam o envelope, chamam o domínio e traduzem o resultado.

`firstVisitOnly = false` permite aplicar benefício a cliente existente, mas não cria atribuição nem recompensa. A mesma separação será coberta por testes unitários e de integração.

### D8 — Configuração do negócio

Adicionar `affiliate_config` ao mecanismo de configuração do negócio, com:

- `enabled`;
- `first_sale_reward_points`;
- `return_reward_enabled`;
- `return_reward_points`;
- `return_window_days`;
- `reward_approval_required`;
- `notifications_enabled`.

Ativar afiliados exige `first_sale_reward_points > 0`. Os restantes valores recebem os defaults do prompt. Uma feature flag `affiliates` controlará rollout, sem transformar o recurso em entitlement pago nesta entrega.

### D9 — RBAC

- Operadores autenticados do negócio podem validar código e concluir uma venda.
- Apenas `OWNER` e administrador interno podem criar/editar/desativar afiliados e códigos, vincular/desvincular e aprovar/cancelar recompensas.
- Um responsável só consulta dados dos negócios devolvidos por `fetchMyBusinesses`.
- Administradores têm diretório global, suspensão e visão por negócio.
- Não será criado login, sessão ou claim de afiliado.

### D10 — API

Seguir os namespaces atuais:

```text
POST/GET       /merchant/affiliates
GET/PATCH      /merchant/affiliates/:affiliateId
POST           /merchant/affiliates/:affiliateId/activate
POST           /merchant/affiliates/:affiliateId/deactivate
POST/GET       /merchant/affiliate-codes
GET/PATCH      /merchant/affiliate-codes/:codeId
POST           /merchant/affiliate-codes/:codeId/enable
POST           /merchant/affiliate-codes/:codeId/disable
POST           /merchant/referrals/validate-code
GET            /merchant/referrals
GET            /merchant/referrals/:attributionId
GET            /merchant/affiliate-rewards
POST           /merchant/affiliate-rewards/:rewardId/approve
POST           /merchant/affiliate-rewards/:rewardId/cancel
GET            /merchant/affiliates/metrics
GET            /merchant/affiliates/:affiliateId/metrics
POST           /merchant/referral-sales/commit

POST/GET/PATCH /admin/affiliates...
POST/DELETE    /admin/affiliates/:affiliateId/merchants/:merchantId
```

O contexto do negócio vem da sessão autenticada, nunca de um identificador de confiança enviado pelo cliente. Não haverá endpoint público de atribuição.

### D11 — Rate limiting

Como não existe middleware atual e adicionar uma dependência não resolve distribuição entre instâncias, `validate-code` usará buckets Firestore transacionais por negócio, utilizador/dispositivo e janela. Excesso responde `429` sem revelar se o código existe.

### D12 — Offline e idempotência

- A fila existente será estendida com `local_id`, `idempotency_key`, `last_sync_error` e os tipos de operação de afiliados.
- As chaves seguirão exatamente os formatos do prompt, usando telefone apenas após derivação HMAC quando armazenadas/logadas.
- Criação offline gera código local marcado `PROVISIONAL`; partilha fica desativada até confirmação.
- Código em cache pode conceder benefício offline e deixa venda `PENDING_SYNC`.
- Código fora do cache é guardado como intenção, sem conceder benefício monetário local.
- Se uma intenção sem benefício for validada no sync, pode criar atribuição/recompensa; benefício `POINTS` pode ser creditado pelo servidor, mas desconto monetário não é aplicado retroativamente.
- Rejeição no sync mantém venda e benefício já concedido, cria atribuição `REJECTED`, não cria recompensa e regista sinal de fraude.
- Aprovação/cancelamento de recompensa exige ligação; nunca ocorre offline.
- O servidor decide colisões por ordem de receção, unicidade transacional e as regras do prompt.

### D13 — Retention Engine e notificações

- Usar a lista única de eventos em contratos Dart e TypeScript: `AFFILIATE_CREATED`, `AFFILIATE_CODE_CREATED`, `REFERRAL_CODE_VALIDATED`, `REFERRAL_ATTRIBUTED`, `REFERRAL_REJECTED`, `AFFILIATE_REWARD_CREATED`, `AFFILIATE_REWARD_APPROVED`, `AFFILIATE_REWARD_CANCELLED` e `REFERRED_CUSTOMER_RETURNED`.
- Publicar `REFERRAL_ATTRIBUTED`, `REFERRED_CUSTOMER_RETURNED` e `AFFILIATE_REWARD_CREATED` só depois da transação da venda.
- Estender o motor atual, sem criar um segundo motor.
- Reutilizar `notification_queue`, acrescentando um worker idempotente, backoff, limite de tentativas, estado terminal e log estruturado.
- Falha de WhatsApp nunca reverte venda, atribuição ou recompensa.
- Partilha manual de código usa `url_launcher`/WhatsApp e continua disponível sem provedor automático.

### D14 — Métricas

- `conversionRate = confirmedAttributions / uniqueValidationAttempts`.
- Replays com a mesma chave de idempotência contam uma vez.
- Expor contagens de indicados/confirmados/retornados e contagem + total de pontos pendentes/aprovados.
- Calcular `lastActivityAt` pelo evento mais recente.
- Evitar colocar PII em payloads analíticos.

### D15 — Rollout seguro

- A funcionalidade nasce atrás da flag `affiliates`.
- O fluxo de venda só mostra o convite de código quando a flag está ativa e o cliente pode ser novo.
- O caminho sem código permanece coberto por teste de regressão e não chama a nova API.
- Backfill não cria atribuições retroativas.

## 4. Modelo de dados implementável

Os nomes públicos seguem o prompt; armazenamento local/SQL usa `snake_case` e contratos JSON usam o padrão já existente.

### 4.1 Entidades principais

- `Affiliate`: identidade global, telefone normalizado, estado e timestamps.
- `AffiliateMerchant`: vínculo e estado por negócio.
- `AffiliateCode`: código normalizado, benefício, validade, limite, uso, elegibilidade e estado.
- `AffiliateAttribution`: aquisição única por negócio/cliente, primeira venda, estado e motivo.
- `AffiliateReward`: recompensa única por atribuição/tipo e respetiva aprovação/cancelamento.
- `AffiliateEvent`: append-only, com metadados mínimos.
- `AffiliateFraudSignal`: append-only, severidade operacional, tipo, referências e metadados sem PII.

### 4.2 Garantias

- Códigos têm formato `AFI-{NAME}-{XXXX}`; o primeiro nome é ASCII-folded, em maiúsculas, limitado a oito caracteres, e o sufixo usa `23456789ABCDEFGHJKMNPQRSTUVWXYZ`.
- Pesquisa de código remove espaços externos e ignora maiúsculas/minúsculas.
- Código global único por documento de lookup normalizado.
- Um vínculo e um código por par afiliado–negócio por IDs determinísticos.
- Atribuição ativa única por negócio/cliente por documento determinístico e transação.
- Recompensa única por atribuição/tipo por documento determinístico.
- Eventos nunca são atualizados ou apagados.
- `usageCount` não diminui e só incrementa na primeira aquisição confirmada.
- Cancelamento/reversão altera atribuição e recompensas elegíveis na mesma operação idempotente; `PAID` gera revisão manual.

### 4.3 Ordem de validação

O preview e o commit usam a mesma função e devolvem o primeiro erro:

1. existência e pertença ao negócio: `CODE_NOT_FOUND`;
2. código ativo: `CODE_DISABLED`;
3. início da validade: `CODE_NOT_STARTED`;
4. fim da validade: `CODE_EXPIRED`;
5. limite: `CODE_USAGE_LIMIT_REACHED`;
6. afiliado e vínculo ativos: `AFFILIATE_INACTIVE`;
7. telefone diferente do afiliado: `SELF_REFERRAL_NOT_ALLOWED`;
8. cliente novo quando exigido: `CUSTOMER_NOT_ELIGIBLE`;
9. ausência de atribuição ativa: `CUSTOMER_ALREADY_REFERRED`;
10. benefício válido para a venda: `BENEFIT_INVALID`.

Mensagens HTTP/UI serão estáveis, curtas e em português de Moçambique; nenhum erro revelará dados de outro negócio.

## 5. Ficheiros e módulos previstos

Os caminhos podem ser ajustados apenas se a implementação encontrar uma convenção mais específica, mantendo estas responsabilidades.

### 5.1 Flutter — modificar

- `lib/core/database/app_migrations.dart`
- `lib/app/providers.dart`
- `lib/app/router.dart`
- `lib/features/business_profile/domain/business_profile.dart`
- `lib/features/customers/data/customer_dao.dart`
- `lib/features/customers/data/customer_repository.dart`
- `lib/features/sales/domain/sale.dart`
- `lib/features/sales/data/sale_dao.dart`
- `lib/features/sales/data/sale_repository.dart`
- `lib/features/sales/presentation/sale_controller.dart`
- `lib/features/sales/presentation/new_sale_screen.dart`
- `lib/features/sales/presentation/sale_success_screen.dart`
- `lib/features/sync/domain/sync_item.dart`
- `lib/features/sync/data/sync_dao.dart`
- `lib/features/sync/sync_service.dart`
- `lib/core/services/firestore_sync_service.dart`
- `lib/core/sync/background_sync.dart`
- `lib/core/notifications/notification_queue_service.dart`

Os ficheiros Freezed/JSON gerados serão atualizados pelo `build_runner`, nunca manualmente.

### 5.2 Flutter — criar

```text
lib/features/affiliates/
  domain/
    affiliate.dart
    affiliate_code.dart
    affiliate_attribution.dart
    affiliate_reward.dart
    affiliate_metrics.dart
    referral_validation.dart
  data/
    affiliate_api.dart
    affiliate_dao.dart
    affiliate_repository.dart
  services/
    referral_benefit_calculator.dart
    affiliate_share_message.dart
  providers/
    affiliate_providers.dart
  presentation/
    affiliate_list_screen.dart
    affiliate_create_screen.dart
    affiliate_detail_screen.dart
    affiliate_code_screen.dart
    affiliate_rewards_screen.dart
    affiliate_metrics_screen.dart
    widgets/
```

### 5.3 Cloud Functions — modificar

- `functions/src/index.ts`
- `functions/src/sync_backend.ts`
- `functions/src/retention_engine.ts`
- `functions/src/merchant_records.ts`
- `functions/src/merchant_collections.ts`
- `functions/src/admin_api_contracts.ts`
- `functions/src/customer_api_contracts.ts`
- `functions/src/admin_audit.ts`
- `functions/src/merchant_bootstrap.ts`
- `functions/sql/schema.sql`
- `functions/sql/seed_plan_features.sql`, apenas para declarar a flag se o catálogo exigir
- `firestore.rules`
- `firestore.indexes.json`

### 5.4 Cloud Functions — criar

```text
functions/src/affiliate_contracts.ts
functions/src/affiliate_engine.ts
functions/src/affiliate_firestore.ts
functions/src/affiliate_routes.ts
functions/src/affiliate_notifications.ts
functions/src/affiliate_engine.test.ts
functions/src/affiliate_routes.test.ts
functions/src/affiliate_notifications.test.ts
functions/sql/migrations/20260915_affiliates.up.sql
functions/sql/migrations/20260915_affiliates.down.sql
functions/sql/seed_affiliates.sql
```

### 5.5 Portal Next.js — modificar

- `admin/src/app/admin/AdminNav.tsx`
- `admin/src/app/negocio/MerchantNav.tsx`
- `admin/src/app/admin/merchants/[merchantId]/MerchantTabs.tsx`
- `admin/src/lib/admin-api.ts`
- `admin/src/lib/merchant-api.ts`
- `admin/src/lib/actions.ts`
- `admin/src/lib/merchant-actions.ts`
- `admin/src/lib/merchant-labels.ts`
- `admin/src/lib/merchant-labels.test.ts`
- `admin/src/app/globals.css` somente se faltar um estado visual reutilizável

### 5.6 Portal Next.js — criar

```text
admin/src/app/admin/afiliados/page.tsx
admin/src/app/admin/afiliados/[affiliateId]/page.tsx
admin/src/app/admin/afiliados/[affiliateId]/loading.tsx
admin/src/app/admin/merchants/[merchantId]/afiliados/page.tsx
admin/src/app/negocio/afiliados/page.tsx
admin/src/app/negocio/afiliados/[affiliateId]/page.tsx
admin/src/app/negocio/afiliados/[affiliateId]/loading.tsx
admin/src/lib/affiliate-form.ts
admin/src/lib/affiliate-form.test.ts
```

### 5.7 Testes e documentação — criar/atualizar

- Testes Flutter em `test/unit/affiliates/`, `test/integration/affiliates/` e `test/widget/affiliates/`.
- Regressões em `test/integration/repository/sale_repository_test.dart`, `test/widget/new_sale_screen_test.dart`, `test/integration/sync/firestore_sync_test.dart` e `test/integration/sync/sync_service_offline_conflict_test.dart`.
- Cenários reais em `integration_test/affiliate_referral_lifecycle_test.dart`.
- Atualizar `README.md`, `admin/README.md`, `docs/backend_bootstrap_contract.md`, `docs/engage_openapi.yaml`, `docs/app_feature_decision_register.md` e notas de migração.

## 6. Reutilização obrigatória

### Flutter

- Design: exports de `lib/design_system/design_system.dart`; tokens de `app_theme.dart`, `customer_experience_theme.dart` e `app_layout.dart`.
- Feedback/estados: `MaisumToast`, `LoadingButton`, `EmptyState`, `ErrorState`, `ContextualErrorState`, `OfflineBanner`, `SyncStatusBar`.
- Dados: padrão DAO/repository de sales, customers e return bonuses.
- Identidade: normalização de `moz_phone_utils.dart` e matching existente.
- Navegação/estado: GoRouter e providers Riverpod centralizados.
- Partilha: padrão de WhatsApp existente com `url_launcher`.

### Backend

- `requireBusiness` e os predicados de admin/owner.
- `recordAuditEvent`.
- transações Firestore e padrões de idempotência de redemption/notifications.
- `triggerSaleCompletedRetentionRules` e execução idempotente de regras.
- helpers de compatibilidade/replay de `sync_backend.ts`.
- contratos tipados partilhados com o portal.

### Portal

- `PageHeader`, `Panel`, `Card`, `DefinitionList`, `Badge`, `EmptyState`, `ErrorState`, `Pagination`, `TableSkeleton`, `MetricsSkeleton`, `Tabs` e `ChipFilter`.
- `ActionForm`, `Field`, `Select`, `Check`, `TextArea` e `Notice`.
- `SearchForm`, `TruncationNotice` e `ResultCount`.
- filtros em query string, server components, `Suspense` por painel e server actions.
- tokens existentes em `admin/src/app/globals.css`.

## 7. Plano por fases

### Fase 1 — Dados

1. Criar os modelos e índices Firestore.
2. Adicionar migration SQLite v30 com tabelas de afiliados, cache de códigos, campos opcionais na venda e metadados da fila.
3. Acrescentar SQL PostgreSQL `up`/`down`, schema bootstrap e seed dev/test.
4. Adicionar regras Firestore deny-by-default para entidades server-owned.
5. Adicionar testes de migração desde base vazia e desde v29, unicidade e rollback SQL.

**Commit:** `feat(affiliates): add data foundation`

### Fase 2 — Domínio

1. Implementar normalização e geração de código com collision retry.
2. Implementar cada validação na ordem definida no prompt.
3. Implementar elegibilidade de novo cliente, cálculo dos três benefícios, venda qualificável e retorno.
4. Implementar atribuição/recompensa idempotentes e reversão.
5. Implementar métricas e sinais de fraude sem PII.
6. Cobrir todos os casos unitários da secção 12 do prompt.

**Commit:** `feat(affiliates): implement referral domain`

### Fase 3 — API

1. Criar contratos tipados, mensagens portuguesas e erros estáveis.
2. Montar rotas merchant/admin sob os middlewares atuais.
3. Implementar isolamento por negócio, RBAC owner/admin, validação manual estrita e rate limiting.
4. Implementar CRUD, vínculo, códigos, preview, consultas, recompensas e métricas.
5. Adicionar testes de contrato, autorização, não enumeração entre negócios e rate limit.

**Commit:** `feat(affiliates): expose secured referral api`

### Fase 4 — Integração da venda

1. Estender o modelo de venda sem alterar a representação legada.
2. Implementar commit online atómico com chave `sale:{deviceId}:{localSaleId}`.
3. Aplicar desconto ou pontos do cliente e pontos normais exatamente uma vez.
4. Tratar rejeição pré-commit permitindo confirmar sem código.
5. Integrar retorno e cancelamento/reversão.
6. Garantir por regressão que venda sem código não usa o novo caminho.

**Commit:** `feat(affiliates): integrate referrals with sales`

### Fase 5 — Retention Engine e WhatsApp

1. Acrescentar os eventos e ações ao motor existente.
2. Gravar eventos no commit e publicar apenas depois.
3. Adicionar os três templates e `statusText` correto.
4. Implementar outbox/worker, retries, idempotência e logs.
5. Confirmar em teste que falha de notificação não afeta a venda.

**Commit:** `feat(affiliates): add retention notifications`

### Fase 6 — Frontend

1. Integrar o convite de código recolhido por defeito no fluxo Flutter.
2. Criar lista, criação, detalhe, edição do código, recompensas e métricas no Flutter.
3. Criar gestão merchant e governança admin no portal.
4. Implementar partilha WhatsApp/native apenas para códigos confirmados.
5. Cobrir loading, empty, error, partial/stale, success e offline.
6. Validar semântica, foco, teclado, contraste, alvos de 48 px e texto a 200%.

**Commit:** `feat(affiliates): add management experiences`

### Fase 7 — Offline

1. Adicionar cache de códigos e operações à fila.
2. Implementar criação offline e reconciliação de ID/código provisório.
3. Implementar venda offline conhecida/desconhecida e estados pendentes.
4. Resolver conflitos e rejeições de forma determinística.
5. Garantir restart, lotes, falha parcial e retry storms.

**Commit:** `feat(affiliates): complete offline sync`

### Fase 8 — Hardening

1. Executar E2E dos sete cenários do prompt.
2. Adicionar testes de transação/rollback, double submit, cross-merchant e autorização.
3. Validar regras/índices em emuladores.
4. Rever logs, mascaramento, auditoria, fraude e métricas.
5. Executar todas as suites e builds.

**Commit:** `test(affiliates): harden referral lifecycle`

### Fase 9 — Documentação

1. Atualizar README, contratos API/OpenAPI e documentação de sync.
2. Documentar `up`, `down`, seed, rollout e recuperação.
3. Registar a decisão no feature register.
4. Documentar limitações conhecidas e dependências operacionais.

**Commit:** `docs(affiliates): document referral engine`

## 8. UX e estados

### Flutter

- O campo “Tem código de indicação?” fica recolhido e não acrescenta toque à venda normal.
- Cliente claramente recorrente não vê o campo.
- O painel válido mostra benefício e primeiro nome do afiliado, sem IDs.
- A rejeição usa uma linha curta e mantém a venda preenchida.
- Em modo offline, mostrar “Pendente de confirmação” junto ao benefício.
- Código provisório apresenta estado e motivo para “Partilhar código” estar desativado.
- Recompensa sem rede mantém o botão visível, desativado com explicação.
- Todos os controlos usam alvos mínimos de 48 × 48 e `Semantics`.

### Portal

- Listas densas podem usar tabela em desktop; cartões/resumo continuam responsivos.
- Filtros permanecem na URL.
- Falhas assíncronas usam `role="alert"`/`aria-live`; foco é enviado ao resultado do formulário.
- Não criar cores, raios ou tipografia fora dos tokens existentes.

### Estados obrigatórios

| Estado | Comportamento |
| --- | --- |
| Loading | Skeleton/indicador dentro do espaço final; botão permanece visível e desativado |
| Empty | Explicação e ação “Adicionar afiliado” |
| Error | Mensagem em linguagem de negócio e ação “Tentar novamente” |
| Partial/stale | Mostrar dados disponíveis e sinalizar data/parte em falta |
| Success | Toast/notice e destino útil |
| Offline | Explicar o que fica pendente e o que não pode ser feito |

## 9. Estratégia de testes

### Unitários

- geração, alfabeto, ASCII-fold, normalização e colisões;
- todos os reason codes na ordem prevista;
- novo cliente e identidade duplicada por telefone;
- benefícios fixo, percentual e pontos, incluindo limites;
- venda qualificável e regras mínimas;
- idempotência de atribuição/recompensa;
- janela de retorno e evento único;
- cancelamento/reversão e recompensa `PAID`;
- métricas e deduplicação de validações;
- templates e `statusText`.

### Integração

- transação completa e rollback injetado;
- isolamento entre negócios;
- replay gera uma venda, atribuição, recompensa e ledger entry;
- cancelamento sincronizado;
- eventos Retention após commit;
- falha WhatsApp não afeta venda;
- aprovação por papel e estado;
- migração SQLite v29 → v30;
- Firestore sync, cache e conflitos.

### Widget/E2E

- fluxo sem código inalterado;
- fluxo válido/rejeitado;
- criação, partilha, desativação e aprovação;
- offline conhecido/desconhecido;
- reconnect e expiração antes do sync;
- retorno dentro/fora da janela;
- estados e acessibilidade com texto a 200%.

## 10. Comandos de implementação e verificação

Executar o menor conjunto relevante em cada fase e a suite completa na Fase 8.

### Flutter

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-fatal-infos
flutter test test/unit/affiliates test/integration/affiliates test/widget/affiliates
flutter test
flutter test integration_test/affiliate_referral_lifecycle_test.dart
```

### Cloud Functions

```powershell
Set-Location functions
npm run build
npm test
```

Quando catálogo/feature keys mudarem:

```powershell
Set-Location functions
npm run codegen
npm test
```

### Portal

```powershell
Set-Location admin
npm run typecheck
npm test
npm run build
```

### Migrações e emuladores

O repositório não tem comando de migração PostgreSQL. A Fase 1 adicionará scripts `up`/`down`, aplicáveis sem dependência nova:

```powershell
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f functions\sql\migrations\20260915_affiliates.up.sql
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f functions\sql\seed_affiliates.sql
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f functions\sql\migrations\20260915_affiliates.down.sql
```

Validação integrada:

```powershell
firebase emulators:exec --only auth,functions,firestore "npm --prefix functions test"
```

O rollback será testado numa base temporária; nunca contra dados partilhados.

## 11. Critérios de aceite por arquitetura

- Operações remotas com código passam por transação server-owned.
- Nenhuma query aceita `merchantId` do corpo sem confirmar o contexto autenticado.
- Código de outro negócio responde `CODE_NOT_FOUND`.
- Códigos e telefones são normalizados uma vez na fronteira.
- Venda sem código mantém contrato e caminho existentes.
- Venda offline nunca desaparece por rejeição de indicação.
- Eventos são append-only e notificações pós-commit.
- Aprovação nunca ocorre offline.
- Não existe escrita de recompensa de afiliado no ledger do cliente.
- Todos os sete cenários E2E e regressões existentes passam.

## 12. Perguntas em aberto e dependências

1. **Provedor automático de WhatsApp:** o repositório possui fila e partilha assistida, mas não um adaptador de entrega. Antes da Fase 5 é necessário confirmar provedor, credenciais, webhook de estado e política de opt-in. Até lá, o domínio e a outbox podem ser implementados e testados com um adaptador falso; produção fica desativada por configuração, sem fingir sucesso.
2. **Aplicação de SQL em ambientes:** não existe runner de migrations. A proposta é versionar scripts `up`/`down` e documentar execução com `psql`; a equipa de operação deve confirmar como produção aplica esses scripts.
3. **Semântica monetária:** a decisão D4 foi tomada pragmaticamente porque não houve resposta ao pedido de esclarecimento. A aprovação deste documento confirma `amount = líquido` e pontos normais sobre o líquido.
4. **Entrega de desconto para código desconhecido offline:** a decisão D12 não tenta cobrar/devolver dinheiro retroativamente; somente benefício em pontos pode ser creditado depois. A aprovação deste documento confirma esse comportamento.

## 13. Riscos e mitigação

| Risco | Mitigação |
| --- | --- |
| Dupla atribuição em dispositivos diferentes | IDs determinísticos + transação Firestore |
| Código global colidir | Documento lookup + retry com alfabeto restrito |
| Benefício duplicado por replay | Chave de idempotência por venda e ledger |
| Quebra de vendas comuns | Caminho sem código inalterado + regressão dedicada |
| Divergência offline | Estado explícito, servidor autoritativo e histórico de rejeição |
| Exposição entre negócios | APIs merchant-scoped, testes negativos e regras deny-by-default |
| PII em logs | HMAC/máscara e allowlist de campos estruturados |
| WhatsApp bloquear venda | Outbox após commit e worker independente |
| Portal e app divergirem | Contratos TypeScript partilhados e reason codes únicos |
| Migration sem runner | SQL versionado, `ON_ERROR_STOP`, teste up/down e runbook |
| Navegação excessiva | Uma entrada “Afiliados”; detalhe agrega código, métricas e histórico |

## 14. Condição para iniciar a Fase 1

A Fase 1 só começa após aprovação explícita deste documento, incluindo as decisões D4 e D12 e as dependências de WhatsApp/migração acima.

## 15. Registo pós-implementação (2026-09-15)

### 15.1 Fases concluídas e commits reais

| Fase | Estado | Commit(s) real(is) / nota |
| --- | --- | --- |
| 0 — Avaliação | Concluída | `c7053b0` — `docs(affiliates): assess referral implementation` |
| 1 — Dados | Concluída | `d7c61b8` — `feat(affiliates): add data foundation` |
| 2 — Domínio | Concluída | `00d1e5d` — `feat(affiliates): implement the referral domain and lock down its data`; `a6809bd` — `feat(affiliates): add rate limiting, code claiming and the message outbox`; `0d603cc` — `refactor(affiliates): match the stored code shape, and name the id separator` |
| 3 — API | Concluída | `ae0ae6d` — `feat(affiliates): expose secured referral api` |
| 4 — Integração da venda | Concluída | `b1ce0a6` — `feat(affiliates): integrate referrals with sales` |
| 5 — Retention Engine e WhatsApp | Concluída | `82da991` — `feat(affiliates): add retention notifications` |
| 6 — Frontend | Concluída | `f43d236` — `feat(affiliates): add management experiences` |
| 7 — Offline | Concluída | `1403c59` — `feat(affiliates): complete offline sync` |
| 8 — Hardening | Concluída | `229b462` — `test(affiliates): harden referral lifecycle` |
| 9 — Documentação | Concluída | `docs(affiliates): document referral engine` — commit documental desta fase |

### 15.2 Desvios e decisões reais

1. **Fase 2 saiu em mais de um commit.** Rate limiting, code claiming e outbox
   ficaram materializados entre `00d1e5d` e `a6809bd`, com cleanup em
   `0d603cc`, em vez de um único commit com a mensagem planeada.
2. **O gate de rollout não ficou como feature flag paga separada.** A
   ativação real do programa é merchant-scoped, em
   `businesses/{merchantId}.affiliate_config.enabled`, com
   `first_sale_reward_points > 0` para o programa fazer sentido operacional.
3. **Firestore manteve-se como autoridade operacional.** SQLite é projeção
   local/offline; PostgreSQL permanece compatibilidade/analytics e não entra na
   transação crítica da venda.
4. **A lacuna do provedor WhatsApp continua intencionalmente aberta.** A
   outbox existe e reprocessa, mas sem adapter configurado as mensagens ficam
   em `NOT_CONFIGURED`/queued; a partilha manual da app continua funcional.
### 15.3 Limitações conhecidas confirmadas na implementação

- não há pagamentos automáticos, login de afiliado nem marketplace;
- aprovação de recompensa é online-only;
- a consola admin global lista `merchant_ids` ligados, mas não mostra ali o
  estado por ligação (ativo/desligado) na própria tabela;
- código offline não cacheado não recebe desconto monetário retroativo depois;
- se uma venda offline já concedeu benefício local e o servidor rejeitar o
  código, a venda mantém esse benefício registado e o afiliado não recebe
  atribuição/recompensa;
- os pontos do afiliado continuam separados do ledger de fidelização do
  cliente.

### 15.4 Resultados reais de validação acumulados pelas fases 1-8

- Functions: **571** testes.
- Flutter full suite: **779** testes.
- Affiliate referral lifecycle: **14** testes/cenários.
- AVD/device validation: **7** cenários.
- Portal/admin: **120** testes.
- Firestore emulator: **sucesso**.
- Full repo format check: **falhou em 48 ficheiros pré-existentes** fora do
  escopo desta fase.
- Governance checker antes desta entrada ainda reportava módulos em falta,
  incluindo `affiliates`.
- `psql` permaneceu indisponível neste ambiente; o SQL não foi aplicado aqui.

### 15.5 Validação rerun da Fase 9 (documentação)

Ficheiros tocados nesta fase documental:

- `README.md`
- `admin/README.md`
- `docs/backend_bootstrap_contract.md`
- `docs/engage_openapi.yaml`
- `docs/afiliados/OPERATIONS.md`
- `docs/app_feature_decision_register.md`
- `docs/afiliados/PLAN.md`

Resultados observados nesta execução:

1. **YAML parse (`docs/engage_openapi.yaml`)**
   Não foi possível correr parser Ruby/Python porque o ambiente não tinha Ruby,
   nem Python configurado, nem dependência Node de YAML instalada. Como
   verificação disponível, os diagnósticos do editor para
   `docs/engage_openapi.yaml` não reportaram erros.
2. **Governance checker** — `dart run tool/check_feature_decision_register.dart`
   Continua a falhar por módulos pré-existentes fora desta tarefa:
   `admin_portal`, `business_profile`, `catalog`, `customer_app`,
   `merchant_onboarding`. `affiliates` deixou de aparecer após esta entrada.
3. **Plan catalog checker** — `dart run tool/check_plan_catalog.dart`
   Passou. Mantiveram-se apenas os avisos informativos/documentados já
   conhecidos em `docs/landing_page_recommendations.md`.
4. **`git diff --check`**
   Passou.
