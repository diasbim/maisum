# Prospeção MaisUm — Plano de implementação do MVP sem IA

> **Estado: implementado (2026-09-22).** As seis fases estão em código, com
> 948 testes em `functions/` e 156 em `admin/` a passar, e o portal a construir.
> Os desvios ao plano original estão registados em
> [Desvios](#desvios-ao-plano-original), no fim.

**Objetivo:** validar se a prospeção gera clientes, com custo determinístico e zero
gasto de LLM, reutilizando o módulo de prospeção que já existe.

**Fonte de dados única:** Google Places.
**Custo variável único:** chamadas pagas ao Places, controladas pelo guarda de
orçamento que já está escrito.

---

## Princípio que governa o plano

A pesquisa do Places devolve identificação, tipo, localização e avaliações de
forma barata. Telefone e website exigem um segundo pedido, mais caro, por
negócio. Todo o desenho decorre de uma regra:

> Nunca pedir os campos caros para um negócio que o motor de regras ainda não aprovou.

Numa campanha de 1 000 descobertos com 300 qualificados, paga-se o segundo
estágio 300 vezes, não 1 000. Os restantes 700 custam zero e ficam guardados.

---

## O que já existe e não se reescreve

| Bloco | Ficheiro |
|---|---|
| Motor de regras puro, testado critério a critério | `functions/src/prospecting_scoring.ts` |
| Qualificação e motivos de rejeição | `qualify` / `DISQUALIFY_REASON` |
| Guarda de orçamento (mês, dia, por lead, limiar) | `functions/src/prospecting_budget.ts` |
| Porta de fornecedor + cadeia de fallback | `functions/src/prospecting_providers.ts` |
| Orquestração de descoberta e enriquecimento | `functions/src/prospecting_pipeline.ts` |
| Persistência, subcoleções, transação orçamento+uso | `functions/src/prospecting_store.ts` |
| Funil como estados | `PROSPECT_STATUS` em `prospecting_contracts.ts` |
| Admin Next.js (lista, detalhe, definições) | `admin/src/app/admin/prospecao/` |

---

## Não fazer

Quatro coisas que parecem simplificações e são regressões:

1. **Não migrar para PostgreSQL/Prisma.** O store são 33 KB de Firestore com
   subcoleções e uma transação que consome orçamento e escreve a linha de uso no
   mesmo commit. A migração custa semanas e não produz nenhuma informação sobre
   se a prospeção converte — que é a única pergunta do MVP.
2. **Não renomear `SCORE_BAND`.** `PRIORITY/GOOD/NURTURE/LOW_FIT` são valores
   guardados. Renomear muda o significado de todos os scores já escritos. Uma
   quinta banda, se for precisa, é uma linha no array `bands`.
3. **Não remover membros de `PROVIDER_OPERATION` nem critérios de scoring.**
   São vocabulário guardado: linhas de uso antigas referem `ANALYZE_LEAD`. Deixam
   de ser *emitidos*; não são apagados.
4. **Não apagar o `LlmPort`.** `resolveLlm` já devolve `NotConfiguredLlm` sem
   chave, e as rotas já respondem "nenhum modelo configurado" em vez de 500.
   É a porta para IA futura, e já está fechada por omissão.

---

## Fase 0 — Desligar a IA (sem código)

Remover `ANTHROPIC_API_KEY` do ambiente de funções.

**Feito quando:** a rota de análise responde `NOT_CONFIGURED` e o painel do lead
explica a ausência em vez de falhar; nenhuma linha de uso `ANALYZE_LEAD` nova.

**Verificação:** `admin/scripts/smoke.mjs` contra o emulador.

---

## Fase 1 — Pesos e sinais (caminho crítico)

A decisão de produto. Sem ela não há leads pontuados, e com a tabela atual
**nenhum lead chega a 80** porque seis critérios dependem de fontes que já não
existem (`employeeCountInRange`, `promotions`, `activeSocial`, `strongPresence`,
`decisionMakerIdentified`, `growthSignal`).

Os quatro ids de dimensão mantêm-se — são colunas guardadas
(`business_fit_score`, ...). Mudam os pesos dentro deles, para que os 100 pontos
sejam alcançáveis só com o Places:

```text
BUSINESS_FIT              40   setor ICP 20 · recorrente 10 · geografia 5 · rating >= 4,0  5
RETENTION_POTENTIAL       30   serviço recorrente 10 · múltiplos serviços 5
                               · caso de uso fidelização 5 · volume de avaliações 10
DIGITAL_PRESENCE          20   website 5 · telefone 5 · horário publicado 5 · fotos 5
COMMERCIAL_OPPORTUNITY    10   contacto alcançável 5 · negócio operacional 5
                        -----
                          100
```

### Alterações

**`functions/src/prospecting_config.ts`**
- `ScoringConfig`: novos campos `businessFit.ratingAtLeast` e `businessFit.minRating`,
  `retentionPotential.reviewVolume` e `retentionPotential.reviewThresholds`,
  `digitalPresence.openingHours`, `digitalPresence.photos`,
  `commercialOpportunity.operational`.
- `DEFAULT_SCORING`: pesos e `max` acima.
- Limiares de avaliações a **10 e 30**, não 50/100. Uma barbearia no Alto-Maé
  pode ter 8 avaliações; os limiares de mercados maduros rejeitariam tudo.
  São dados editáveis — a primeira campanha calibra-os.

**`functions/src/prospecting_scoring.ts`**
- `ScoringSignals`: `rating: number | null`, `reviewCount: number | null`,
  `hasOpeningHours: boolean | null`, `hasPhotos: boolean | null`,
  `isOperational: boolean | null`.
- `UNKNOWN_SIGNALS`: os cinco a `null`.
- `scoreProspect`: critérios novos; os seis inalcançáveis saem do cálculo mas os
  seus ids permanecem no módulo para leitura de scores antigos.

**`functions/src/prospecting_providers.ts`**
- `CompanyRecord`: `rating`, `review_count`, `has_opening_hours`, `has_photos`,
  `business_status`.
- `assertCompanySane` valida os intervalos (`rating` em 0–5, `review_count` >= 0).

**`functions/src/prospecting_pipeline.ts`**
- `signalsFromCompany`: mapear os campos novos.

**`functions/src/prospecting_store.ts`**
- `scoring_version` gravado com o score. Um score guardado sem a versão dos pesos
  é um número sem significado assim que o operador pode editar a tabela — não
  distingue "os leads de Agosto eram piores" de "a tabela mudou". As análises já
  resolvem isto com `promptVersion`; é o mesmo padrão.

### Testes
`prospecting_scoring.test.ts` — um caso por critério novo; um caso de tecto que
prova que um negócio com todos os sinais do Places atinge 100; um caso que prova
que `null` (desconhecido) não conta como falso.

**Feito quando:** `npm test --prefix functions` passa e o caso de tecto atinge 100.

---

## Fase 2 — Provider Places, estágio 1

**`functions/src/prospecting_provider_places.ts`** (novo), espelhando
`prospecting_provider_apollo.ts`: `PLACES_KEY`, `PlacesOptions`,
`PlacesProvider implements BusinessDiscoveryProvider`, `statusToCode`.

- `BusinessSearchCriteria` serve como está. `industries` mapeia para os
  `keywords` que já existem em `ICP_INDUSTRIES`; `city` para coordenadas + raio;
  `cursor` para o token de página. **`employeeMin/Max` fica por usar** — o
  adaptador regista-o explicitamente em vez de fingir que filtrou.
- *Field mask* mínimo: id, nome, tipo, localização, `rating`, nº de avaliações,
  estado. Nada de telefone ou website nesta chamada.
- `source_reference` recebe o identificador do local — é a chave de deduplicação
  contra a coleção `companyLookup`.
- Implementa `CostReportingProvider` (`estimatedCostUsd`, `lastCostUsd`).

**`prospecting_config.ts`**: flag `placesEnabled`; `providerPriority` passa a
`['places', 'fixtures']`.
**`functions/.env.example`**: `GOOGLE_PLACES_API_KEY`, `PROSPECTING_PLACES_ENABLED`.

### Testes
`prospecting_provider_places.test.ts` com respostas gravadas: mapeamento de
tipo→ICP, paginação por cursor, negócio sem rating (→ `null`, não zero), erro de
quota → `RATE_LIMIT`, resposta malformada → `INVALID_SCHEMA`.

**Feito quando:** uma campanha no emulador descobre negócios reais, deduplicados,
pontuados apenas com dados do estágio 1.

---

## Fase 3 — Estágio 2 atrás do guarda de orçamento

**`prospecting_contracts.ts`**: `FETCH_PLACE_DETAILS` em `PROVIDER_OPERATION`.
Como `OPERATION_COST_USD` é um `Record` sobre o enum, o compilador exige a
entrada de custo — é a rede de segurança desta fase.

**`prospecting_provider_places.ts`**: método de detalhes com o *field mask* caro
(telefone, website, horário, fotos).

**`prospecting_pipeline.ts`**: `fetchPlaceDetails`, no lugar que
`findDecisionMakers` ocupava — `guardSpend` → chamada → re-score → estado
`READY_TO_CONTACT`. O guarda recusa `BELOW_THRESHOLD` antes de consultar o
orçamento, portanto um lead fraco nunca chega ao pedido pago.

**`prospecting_config.ts`**: `ENRICHMENT_UNIT_COST_USD` passa a ser só
`FETCH_PLACE_DETAILS`. `ESTIMATES_VERIFIED` **fica a `false`** até haver fatura —
o preço por pedido depende do SKU e do *field mask*, e o painel já mostra a
estimativa com a ressalva.

### Testes
`prospecting_pipeline.test.ts`: lead abaixo do limiar não emite pedido;
lead acima emite exatamente um; cap diário atingido recusa com `DAILY_CAP`;
re-score depois dos detalhes sobe o score.

**Feito quando:** um lead a 45 pontos nunca gera um pedido de detalhes.

---

## Fase 4 — Motor de templates

Substitui a chamada de LLM em `OutreachService`
(`functions/src/prospecting_analysis.ts`).

**`functions/src/prospecting_templates.ts`** (novo):
- Templates em Firestore com recurso a um conjunto embutido, como as definições.
- Variáveis numa lista branca derivada de campos guardados.
- **Falha fechada:** variável em falta aborta a renderização. Um template não
  inventa, mas interpola vazio — "Olá 👋, encontrei o vosso espaço" sem o nome é
  pior do que mensagem nenhuma.
- `OUTREACH_MAX_CHARS` passa de corte em runtime a **validação na gravação**: o
  operador vê "excede 600 caracteres para WhatsApp" antes de existir a mensagem,
  em vez de descobrir uma frase truncada depois de enviada.
- `blocksOutreach` (`DO_NOT_CONTACT` / `OPTED_OUT`) intocado, nos dois sítios.

**`prospecting_store.ts`**: `template_version` na atividade `OUTREACH_GENERATED` —
é o que torna o A/B mensurável sem mais infraestrutura.

**Admin**: `OutreachPanel.tsx` escolhe template em vez de gerar; `definicoes/`
ganha edição e validação.

Conjunto inicial: `barbershop-whatsapp-v1`, `salon-whatsapp-v1`,
`generic-whatsapp-v1`, `generic-email-v1`.

**Feito quando:** gerar uma mensagem não faz nenhuma chamada de rede paga.

---

## Fase 5 — Funil

Query sobre `PROSPECT_STATUS`, segmentada por banda e por `template_version`.
Índice novo em `firestore.indexes.json`. Página em `admin/src/app/admin/prospecao/`.

Dois números decidem se a IA alguma vez volta:

- **`QUALIFIED → REPLIED` baixo** → o problema é a mensagem. Três versões de
  template estagnadas é a condição mínima para considerar geração por IA.
- **`PRIORITY → CUSTOMER` ≈ `NURTURE → CUSTOMER`** → o motor não discrimina. É
  aqui, e só aqui, que ranking por IA tem ROI demonstrável — e nessa altura já há
  o conjunto de dados rotulado para o avaliar.

Se ambos forem saudáveis, a IA não volta. É essa a resposta que o MVP deve poder dar.

---

## Ordem e verificação

```text
Fase 0  desligar IA          sem código
Fase 1  pesos e sinais       <- caminho crítico, decisão de produto
Fase 2  Places estágio 1     depende de 1
Fase 3  Places estágio 2     depende de 2
Fase 4  templates            independente de 2–3, pode correr em paralelo
Fase 5  funil                depende de 3 e 4
```

Testes: `npm test --prefix functions` (`tsc` + `node --test lib/*.test.js`).
Admin: `admin/tsconfig.test.json`. Ponta a ponta: `admin/scripts/smoke.mjs`.

---

## Riscos externos

Nenhum dos dois é resolvido por esta arquitetura, e ambos podem invalidar um
canal **depois** de construído. Resolver antes da Fase 2.

1. **Termos do Google Places.** O identificador do local pode ser guardado
   indefinidamente; o restante conteúdo (nome, morada, telefone, avaliações) tem
   restrições de cache e de uso para construir bases de dados paralelas. O
   esquema desta arquitetura guarda tudo em Firestore de forma persistente.
   Confirmar nos termos atuais antes de fixar o esquema.
2. **Política de mensagens da Meta.** Mensagens iniciadas pelo negócio exigem
   templates pré-aprovados, e o contacto não solicitado a números sem opt-in é
   proibido. O WhatsApp é o canal principal do plano e é o mais rápido a fazer
   banir um número.

## Questão em aberto

O preço por pedido do Places por SKU e por *field mask* não está fixado neste
plano porque muda. Entra como estimativa em `OPERATION_COST_USD` com
`ESTIMATES_VERIFIED = false`; o cap configurado é o que limita o gasto até haver
uma fatura real.

---

## Desvios ao plano original

Sete, todos deliberados. Os três primeiros mudaram o desenho; os restantes são
detalhes que só apareceram a escrever o código.

**1. As bandas não foram recalibradas — os pesos foram.**
O plano previa baixar as bandas para o tecto real de 65 pontos. Em vez disso, os
pesos foram redistribuídos para que os 100 pontos sejam alcançáveis só com o
Places, e as bandas ficaram em 80/60/40. É melhor pelo motivo que o próprio
plano dá para não renomear `SCORE_BAND`: as bandas são valores guardados, e
mexer-lhes torna incomparável tudo o que já foi pontuado.

Os seis critérios sem fonte — `employeeCountInRange`, `activeSocial`,
`strongPresence`, `promotions`, `decisionMakerIdentified`, `growthSignal` —
passaram a valer zero, e `scoreProspect` **descarta** um critério de peso zero
em vez de o mostrar a valer nada. Zero passou assim a ser a forma de desligar um
critério a partir das definições, e voltar a ligá-lo é um número no ecrã.

**2. `FETCH_PLACE_DETAILS` → `FETCH_LISTING_DETAILS`.**
A porta ficou genérica (`ListingDetailProvider`), não específica do Google. A
operação seguiu o mesmo nome, para que o vocabulário guardado e a porta
coincidam. Outro directório que cobre por campos entra atrás da mesma interface.

**3. `furthest_stage`: o funil não se conta por estado actual.**
Descoberto na Fase 5, e não estava no plano. `prospects.status` é onde um lead
*está*, não por onde *passou* — cinco leads que converteram todos dariam "zero
contactados" e uma taxa de resposta de nada. `setProspectStatus` passa a manter
uma marca de água máxima, na mesma transação do estado, que nunca desce. Um lead
que chegou a `DEMO` e caiu para `LOST` continua a contar em todas as etapas até
`DEMO`, que é a única forma de "quantos dos contactados responderam?" ter
resposta verdadeira.

**4. `loyaltyUseCase` é inferido do setor.**
Lia só o sinal da pesquisa web, o que o deixava `UNKNOWN` em todos os leads
depois de a pesquisa deixar de correr. Um setor que é recorrente *e* vende mais
do que uma coisa tem caso de uso de fidelização por definição, e a tabela ICP já
afirma as duas metades. Uma observação explícita continua a prevalecer sobre a
tabela.

**5. Os canais oferecidos são intersectados com os que têm template.**
`availableChannels` diz em que canais o lead é *alcançável*. Ser alcançável por
SMS e haver um template de SMS são factos diferentes, e oferecer o canal levaria
o operador a um beco sem saída.

**6. A rota `/enrich` tem um só escritor.**
`fetchListingDetails` escreve os campos, a pontuação, a atividade e o estado; a
rota audita e responde. Dois escritores para uma ação é como um ecrã acaba a
mostrar duas entradas "enriquecido" para um clique.

**7. Corrigido um `x` solto no início de `firestore.indexes.json`.**
Pré-existente e não commitado. Quebrava o JSON e teria quebrado o deploy.

## O que ficou por fazer

- **A atribuição de respostas por template.** `template_id` já é gravado em cada
  atividade `OUTREACH_GENERATED`, portanto o dado existe. Falta a query de
  grupo de coleções que o agrega, e o índice que ela exige. A taxa de resposta
  global — que é o número da regra de decisão — já está no ecrã do funil.
- **A edição de templates na consola.** `validateTemplate` existe e é chamado na
  renderização; falta o ecrã em `Definições → Prospeção` que o chama na gravação.
  Os quatro templates por omissão vivem em código até lá.
- **O preço real do Places.** `ESTIMATES_VERIFIED` continua a `false`, como
  deve, até haver fatura.
