# MaisUm Afiliados — Operações e migrações

Este runbook cobre as migrações locais/remotas e o rollout operacional do
módulo de afiliados.

> **Honestidade de execução**
>
> - Nesta sessão, `psql` **não estava disponível**.
> - Os ficheiros SQL foram revistos estruturalmente e referenciados pela árvore
>   de testes/documentação do repositório, mas **não foram aplicados** a uma
>   base PostgreSQL real a partir deste ambiente.
> - Não declarar sucesso de deploy/migration sem execução observada.

## 1. Autoridade dos dados

- **Firestore é a autoridade operacional** para afiliados, códigos,
  atribuições, recompensas, eventos, sinais de fraude, outbox e decisões de
  reconciliação.
- **SQLite** é apenas projeção local/offline da app Flutter.
- **PostgreSQL** recebe schema compatível/projeções e continua útil para
  bootstrap, compatibilidade e análise, mas não entra na transação crítica da
  venda.

## 2. SQLite: migrações automáticas v30/v31

As migrações da app correm automaticamente ao abrir a base através de
`AppDatabase` / `AppMigrations.latestVersion`.

### v30 — `affiliates foundation`

Criada por `lib/core/database/app_migrations.dart`:

- tabelas `affiliates`, `affiliate_merchants`, `affiliate_codes`,
  `affiliate_code_lookup_cache`, `affiliate_attributions`,
  `affiliate_rewards`, `affiliate_events`, `affiliate_fraud_signals`;
- índices de unicidade/consulta para telefone, código, vínculo e métricas;
- colunas novas em `sales` para `gross_amount`, `affiliate_code_id`,
  `referral_*`;
- metadados de fila/sync necessários ao fluxo de afiliados.

### v31 — `affiliates offline queue projection`

Também automática na abertura:

- adiciona `local_id`, `provisional`, `sync_status`, `last_sync_error` e
  colunas associadas às entidades offline de afiliados;
- enriquece `affiliate_code_lookup_cache` com `affiliate_display_name`,
  `affiliate_first_name`, `affiliate_status`, `link_status`, `refreshed_at`;
- acrescenta `referral_code_input`, `affiliate_id`,
  `referral_rejection_code`, `referral_status_message`,
  `referral_local_benefit_applied`, `referral_idempotency_key` em `sales`;
- acrescenta `idempotency_key` e `sync_status` onde a reconciliação precisa de
  convergir por replay em vez de duplicar linhas.

### Como verificar no dispositivo/emulador

1. Abrir a app numa base nova e confirmar criação da `migration_log`.
2. Abrir uma base antiga (≤ v29) e confirmar aplicação sequencial até v31.
3. Verificar localmente:
   - `migration_log` contém `30` e `31`;
   - as colunas `referral_*`, `local_id`, `idempotency_key` e `sync_status`
     existem;
   - a app arranca sem repair loop.

## 3. PostgreSQL: scripts versionados

Ficheiros relevantes:

- `functions\sql\migrations\20260915_affiliates.up.sql`
- `functions\sql\migrations\20260915_affiliates.down.sql`
- `functions\sql\seed_affiliates.sql`
- `functions\sql\schema.sql` (bootstrap cumulativo)

### O que o `up` faz

- cria tabelas `affiliates`, `affiliate_merchants`, `affiliate_codes`,
  `affiliate_code_lookup`, `affiliate_attributions`, `affiliate_rewards`,
  `affiliate_events`, `affiliate_fraud_signals`, `affiliate_rate_limits`;
- acrescenta colunas de referrals em `sales`;
- acrescenta `local_id`, `idempotency_key`, `last_sync_error` em `sync_queue`;
- cria índices idempotentes e constraints condicionais para `customers`/`sales`
  quando essas tabelas já existem.

### O que o `down` faz

- remove índices novos de `sales` e `sync_queue`;
- remove as colunas adicionadas em `sales`/`sync_queue`;
- elimina as tabelas afiliadas.

> **Precaução de rollback:** `down` só deve ser usado em bases de teste,
> ambientes recém-semeados ou após restauro de backup. Nunca executar `down`
> em produção “para experimentar” depois de tráfego real.

## 4. Backups antes de alterar PostgreSQL

Recomendado antes de `up`, `down` ou seed:

```powershell
pg_dump $env:DATABASE_URL --format=custom --file .\backups\pre_affiliates.backup
```

Se o ambiente usar ficheiros `.sql` em vez de custom dump:

```powershell
pg_dump $env:DATABASE_URL --file .\backups\pre_affiliates.sql
```

Guardar também o commit/hash dos scripts aplicados.

## 5. Aplicação manual com `psql`

Criar a pasta de backup se necessário e falhar logo ao primeiro erro:

```powershell
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f functions\sql\migrations\20260915_affiliates.up.sql
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f functions\sql\seed_affiliates.sql
```

Rollback explícito:

```powershell
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f functions\sql\migrations\20260915_affiliates.down.sql
```

### Ordem recomendada

1. backup;
2. aplicar `up`;
3. validar schema/tabelas/índices;
4. aplicar `seed_affiliates.sql` **apenas** em dev/test;
5. só considerar `down` se houver plano de restauro claro.

## 6. Firestore rules, indexes e deploy

Os artefactos operacionais do módulo vivem em:

- `firestore.rules`
- `firestore.indexes.json`

Deploy recomendado:

```powershell
firebase deploy --only firestore:rules,firestore:indexes
```

Se a release incluir Functions associadas:

```powershell
firebase deploy --only functions,firestore:rules,firestore:indexes
```

### Verificação em emulador

Executar a suite que valida regras/índices/rotas no emulador:

```powershell
firebase emulators:exec --only auth,functions,firestore "npm --prefix functions test"
```

Nesta execução, o Firestore Emulator arrancou em standard edition, executou o
comando de verificação e terminou limpo com:

```powershell
firebase emulators:exec --only firestore "git --version"
```

O conjunto `auth,functions,firestore` acima não foi executado como uma única
sessão, e este documento não reivindica deploy.

## 7. Seed e dados de demonstração

`functions\sql\seed_affiliates.sql`:

- cria merchants de demonstração;
- cria identidades/vínculos/códigos afiliados de demonstração;
- preenche `affiliate_code_lookup`;
- não inventa vendas operacionais apenas para “mostrar” referrals.

Usar **apenas** em dev/test. Não aplicar em produção.

## 8. Rollout por configuração

O rollout atual não usa um entitlement pago novo. O gate real é a configuração
server-owned do negócio em `businesses/{merchantId}.affiliate_config`:

- `enabled`
- `first_sale_reward_points`
- `return_reward_enabled`
- `return_reward_points`
- `return_window_days`
- `reward_approval_required`
- `notifications_enabled`

### Sequência recomendada

1. publicar rules/indexes/functions;
2. garantir Flutter/portal já com SQLite v31;
3. ativar `affiliate_config.enabled=true` **por merchant piloto**;
4. definir `first_sale_reward_points > 0` antes de expor o programa;
5. manter `return_reward_enabled=false` até confirmar o piloto;
6. só depois ampliar para mais merchants.

## 9. Outbox e provedor WhatsApp

Estado atual do repositório:

- existe outbox Firestore em `businesses/{merchantId}/affiliate_outbox`;
- **não existe provedor WhatsApp configurado** neste repositório;
- `resolveWhatsAppAdapter()` devolve `null`;
- entregas respondem `not_configured`;
- o worker mantém as mensagens em `NOT_CONFIGURED`/reatráveis, sem fingir envio.

### O que fazer quando houver provedor

1. integrar o adapter em `functions/src/affiliate_outbox_firestore.ts` via
   `setWhatsAppAdapter(...)`;
2. confirmar credenciais, webhook de estado e política de opt-in;
3. executar sweep manual/batch para drenar backlog.

### Sweep operacional

Endpoint batch autorizado:

```text
POST /admin/affiliates/outbox/sweep
```

Pode ser chamado por automação autenticada (`x-admin-key` apenas para o path
permitido) ou por operação manual autenticada.

Exemplo de body:

```json
{
  "merchant_id": "merchant-1",
  "limit": 25
}
```

Sem provedor configurado, o sweep apenas reavalia e mantém o backlog em estado
reatrável; com provedor configurado, envia o que estiver devido.

## 10. Monitorização e eventos

Observar:

- respostas 429 em `/merchant/referrals/validate-code`;
- eventos/refusos `REFERRAL_REJECTED`;
- sinais `OFFLINE_CODE_REJECTED`, `VALIDATION_BURST`,
  `SELF_REFERRAL_ATTEMPT`, `DUPLICATE_ATTRIBUTION_ATTEMPT`;
- recompensas presas em `PENDING`;
- backlog de outbox em `NOT_CONFIGURED`, `FAILED` ou `PROCESSING` expirado;
- warnings `affiliate_offline_clock_skew`;
- auditoria administrativa:
  `affiliate.create`, `affiliate.update`, `affiliate.unlink`,
  `affiliate_code.create`, `affiliate_code.update`,
  `affiliate_reward.approve`, `affiliate_reward.cancel`.

## 11. Falhas comuns e recuperação

### `validate-code` devolve 429

- esperar `Retry-After`;
- verificar bursts por device/utilizador;
- não tratar como “código existe/não existe”.

### Venda offline rejeitada no sync

- a venda mantém-se;
- se houve desconto local já concedido, ele permanece registado;
- não criar crédito monetário retroativo;
- o afiliado não recebe atribuição/recompensa;
- rever histórico local, evento `REFERRAL_REJECTED` e sinal de fraude.

### `deferred` em `/merchant/referral-sales/sync`

- o customer ainda não chegou ao servidor;
- deixar a fila reprocessar depois do sync de customer;
- não apagar a venda local.

### Recompensa paga/cancelada em estado inesperado

- `PAID` não é revertida automaticamente;
- abrir revisão manual em vez de tentar “corrigir” com update direto.

### Backlog de mensagens

- `NOT_CONFIGURED`: falta provedor; backlog esperado;
- `FAILED`: rever erro do provider e repetir sweep;
- `PROCESSING` antigo: sweep volta a reclamar após lease expirar.

## 12. Checklist mínimo de release

- [ ] app Flutter em schema SQLite v31
- [ ] Functions/publicação de routes de afiliados
- [ ] Firestore rules + indexes publicados
- [ ] `affiliate_config.enabled` apenas nos merchants piloto
- [ ] `first_sale_reward_points` configurado
- [ ] seed aplicado só em dev/test
- [ ] backup PostgreSQL guardado antes de qualquer `psql`
- [ ] plano para outbox/provedor documentado
- [ ] monitorização de 429/rejeições/backlog preparada
