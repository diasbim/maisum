# Landing page — recomendações de seguimento

Versão: 1.1
Data: 1 de setembro de 2026
Estado: **Parcialmente implementado** — ver §0.2
Alvo: `docs/index.html`
Relacionado: `docs/WEBSITE_AUDIT.md`, `docs/WEBSITE_INFORMATION_ARCHITECTURE.md`,
`docs/seo_maputo_tracking.md`, `docs/web_admin_portal_code_plan.md`,
`docs/plans.json`, `tool/check_plan_catalog.dart`

---

## 0.1 Ponto de partida: a auditoria de agosto já foi executada

O `WEBSITE_AUDIT.md` é de 25 de agosto. A landing page foi reescrita a 31 de
agosto (`b07a7e0 feat(web): improve local landing page conversion`). Verifiquei
item a item, e **a maior parte das correções pedidas já estava feita**:

| Item da auditoria | Estado |
|---|---|
| Claims M-Pesa ("M-Pesa pronto", confirmação de pagamento) | **Removidos** — 0 ocorrências |
| Claims de WhatsApp automático / "sem tocar em nada" | **Removidos**; a FAQ passou à formulação correta: *"A automação completa de lembretes ainda está em desenvolvimento"* |
| Resultados quantitativos não verificados ("centenas de vendas", "no-show") | **Removidos** — 0 ocorrências |
| Narrativa centrada em barbearia e corte grátis | **Removida**; barbearia é agora um exemplo entre quatro |
| `featureList` no JSON-LD com claims incorretos | **Corrigido** — as 7 entradas atuais mapeiam todas para capacidades "Disponível" da matriz da auditoria |
| Variantes aleatórias de CTA sem persistência | **Removidas** — 0 ocorrências de `Math.random()` |
| `overflow-wrap:anywhere` a partir palavras | **Removido** |
| Falta de tracking de profundidade de scroll | **Adicionado** |
| Eventos de visualização em poucas secções | **Corrigido** — 7 secções com `data-section-view` |

Este documento cobre apenas o que ficou por fazer, mais o que surgiu ao cruzar a
página com a base de dados de planos.

## 0.2 Estado de implementação

| Item | Estado |
|---|---|
| §2 — Fonte única dos planos (`docs/plans.json`) | **Implementado** |
| §2 — Verificador (`tool/check_plan_catalog.dart`) | **Implementado** |
| §3.1 — Mensagem no CTA do rodapé | **Implementado** |
| §3.2 — Distinguir as duas mensagens quase iguais | **Implementado** |
| §3.3 — Mapeamento mensagem → origem | **Implementado** (§3.4) |
| §4.2 — "Para negócios" na navegação | **Implementado** |
| §1.5 — "Base do Pro" no cartão Business | **Implementado** |
| §1.1–§1.4 — As quatro divergências de plano | **Pendente de decisão** (L1–L4) |
| §4.1 — Título liderar com "fidelização" | **Sem alteração**, por recomendação |

---

## 1. Prioridade 1 — A tabela de planos promete o que o sistema não entrega

Estes achados são novos. A matriz de capacidades da auditoria é ao nível do
produto ("o MaisUm faz X?"); estes são ao nível do **plano** ("o plano Y inclui
X?"), que ninguém tinha cruzado. Fonte: `functions/sql/seed_plans.sql`,
`functions/sql/seed_plan_features.sql`,
`lib/features/subscription/domain/feature_keys.dart`.

**Não implementei §1.1 a §1.4** — cada uma altera a oferta comercial, e essa
decisão é sua. Estão registadas em `docs/plans.json` no bloco `openDecisions`,
e o verificador reporta-as como divergências reconhecidas em cada execução.

### 1.1 "Gestão de equipa" está anunciada como diferenciador do Business — L1

Não existe nenhuma feature key para gestão de equipa.
`lib/features/settings/presentation/staff_management_screen.dart` não
referencia `FeatureKeys`, e `lib/app/router.dart` protege `/staff-management`
apenas por `_ownerOnlyRoutes` — papel de responsável, não plano.

**Todos os planos, incluindo o Free, têm gestão de equipa.**

Opções: (a) remover a linha do cartão Business, (b) criar uma feature key
`staff_management` e passar a aplicá-la, ou (c) mover a linha para uma secção de
capacidades comuns a todos os planos. A opção (b) é a única que preserva a
promessa comercial, mas retira uma funcionalidade a quem já a usa — verificar
antes se algum negócio em plano inferior depende dela.

### 1.2 "Mais capacidade para crescer" (Starter) não tem contrapartida — L2

`limit_value` é `NULL` em **todas** as linhas de `seed_plan_features.sql`.
Nenhuma quota está configurada, embora `usage_balances.limit_value` exista no
schema e `upsertPlanFeature` já aceite `limitValue` e `unit`.

A frase é suficientemente vaga para não ser falsa, mas não corresponde a nada.
Opções: configurar quotas reais por plano, ou substituir por uma capacidade
concreta que o Starter de facto ganha — `campaigns` passa a `true` no Starter e
não é anunciada em lado nenhum.

### 1.3 O plano `growth` existe na base e não é anunciado — L3

`seed_plans.sql:22` define `('growth', 1, 'Growth')` e `seed_plans.sql:50`
o preço a 5000 MZN — o mesmo que o Business. Tem entitlements próprios.

Está declarado em `docs/plans.json` com `"advertised": false`, portanto o
verificador já não o assinala como erro. A decisão de fundo continua aberta:
anunciar, desativar, ou manter como plano interno ou legado.

### 1.4 O Free tem `whatsapp_automation` sem que isso seja anunciado — L4

`('free', 1, 'whatsapp_automation', true)`. Não é promessa excessiva — é o
inverso: capacidade concedida sem intenção declarada. Confirmar se é deliberado.

### 1.5 O cartão Business quebrava o padrão de herança — **corrigido**

O Starter dizia "Base do plano Free" e o Pro "Base do Starter", mas o Business
não declarava nada — saltava direto para os diferenciadores. Confirmei em
`seed_plan_features.sql` que o Business inclui estritamente tudo o que o Pro tem,
e acrescentei a linha **"Base do Pro"** ao cartão.

Alteração aditiva e factualmente verificada: não remove nenhuma promessa e torna
a oferta mais clara. Reverter é trivial se preferir outra formulação.

Fica registado, como oportunidade e não defeito, que o Business ainda inclui
`campaigns`, `cloud_backup`, `engage_manage_visits` e `engage_manage_surveys`
sem que a página os mencione. O verificador lista-os na secção informativa.

---

## 2. Prioridade 2 — Fonte única dos planos — **implementado**

A causa raiz da §1 era estrutural: a tabela de planos vivia como HTML dentro de
um ficheiro de 105 KB, e o provisionamento em dois ficheiros SQL. Nada ligava os
dois, e a divergência só se descobria por leitura manual cruzada.

### 2.1 `docs/plans.json`

Declara, por plano: código, nome público, se é anunciado, tagline, e a lista de
promessas. Cada promessa tem um `backing`:

| `backing` | Significado |
|---|---|
| `core` | Capacidade base, em todos os planos por desenho. Não é gated. |
| `feature_key` | Suportada por uma entitlement, com o `featureKey` indicado. |
| `inherits` | Reafirma o plano inferior, via `inheritsFrom`. |
| `none` | Sem contrapartida técnica. Obriga a constar em `openDecisions`. |

O bloco `openDecisions` regista L1–L4 com um resumo e as opções de cada uma.

### 2.2 `tool/check_plan_catalog.dart`

Segue a convenção de `tool/check_feature_decision_register.dart`. Executar com:

```bash
dart run tool/check_plan_catalog.dart
```

Cruza as três fontes e reporta em três níveis:

- **Erros** (saída 1): plano anunciado sem cartão na página; cartão na página não
  declarado; plano em `seed_plans.sql` não declarado; promessa cuja feature key
  não está provisionada, ou está a `false`; promessa sem contrapartida que não
  esteja reconhecida em `openDecisions`.
- **Divergências reconhecidas** (saída 0): as que têm um `decision` correspondente
  em `openDecisions`. Hoje L1 e L2.
- **Informativo** (saída 0): capacidades provisionadas e ativas que nenhuma
  promessa pública refere. Resolve herança entre planos transitivamente, para
  não sinalizar o que o "Base do X" já cobre.

Estado atual: **passa**, com 2 divergências reconhecidas e 10 entradas
informativas.

Isto fecha a Q8 do `web_admin_portal_code_plan.md` e desbloqueia a Fase 5.1
desse plano, que passa a ter uma fonte declarada com que reconciliar. O mesmo
verificador é o candidato natural ao teste de CI da Fase 7.

**Nota:** os cartões da landing page **não** são gerados a partir do
`plans.json` — continuam escritos à mão no HTML, e o verificador é que garante
que não divergem. Gerar exigiria um passo de compilação ou renderização por
JavaScript; o primeiro contraria a arquitetura estática, o segundo esconderia o
conteúdo dos planos dos motores de busca. A verificação dá a garantia sem
nenhum dos custos.

---

## 3. Prioridade 3 — Atribuição do funil, sem formulário — **implementado**

O `WEBSITE_INFORMATION_ARCHITECTURE.md` decidiu explicitamente *"Sem formulario
novo. Conversao principal pelo WhatsApp."* Estas alterações respeitam essa
decisão — não introduzi formulário.

O problema não era a ausência de formulário; era que a conversa chegava sem
origem recuperável.

### 3.1 CTA do rodapé sem mensagem — **corrigido**

Dos cinco links `wa.me/258823262347`, o do rodapé não tinha texto nenhum: quem
respondia não sabia de onde a pessoa vinha nem o que procurava. Passou a ter
mensagem própria.

### 3.2 Duas mensagens quase iguais — **corrigido**

"Quero ver como o MaisUm funcionaria no meu negócio" (secção de negócios) e
"Quero ver uma demonstração do MaisUm para o meu negócio" (CTA final) eram
indistinguíveis em intenção. A primeira passou a refletir a intenção real da
secção onde vive — qualificação por tipo de negócio.

### 3.3 Sem marcadores técnicos visíveis

Qualquer marcador do tipo `[hero]` ou `?ref=` apareceria ao utilizador dentro do
WhatsApp e degradaria a experiência. As mensagens continuam naturais; a origem é
inferida pelo texto, que é agora único por CTA.

### 3.4 Mapeamento mensagem → origem

Tabela de referência para quem responde no WhatsApp registar a origem no registo
de *prospect* do portal admin (`web_admin_portal_code_plan.md`, Fase 5.4):

| Mensagem recebida | Origem | `data-cta-location` |
|---|---|---|
| "…quero ver como o MaisUm **pode ajudar o meu negócio a reter mais clientes**." | Hero | `hero` |
| "…**tenho um negócio local** e quero saber se o MaisUm se adapta ao meu tipo de negócio." | Secção "Para negócios" | `businesses` |
| "…quero **perceber qual plano** MaisUm é adequado para o meu negócio." | Secção de planos | `plans` |
| "…**li a página** do MaisUm e quero agendar uma demonstração." | CTA final | `final` |
| "…**vim do site** MaisUm e quero falar sobre o meu negócio." | Rodapé | `footer` |

Manter esta tabela sincronizada se as mensagens mudarem — é o único elo entre os
22 eventos Plausible e os negócios que efetivamente se registam.

---

## 4. Prioridade 4 — Decisões

### 4.1 O título lidera com "fidelização", não com "retenção" — **sem alteração**

A auditoria pedia que título e descrição liderassem com retenção. O título atual
é *"Fidelização de clientes em Maputo | MaisUm Moçambique"*.

Isto é **escolha deliberada, não esquecimento**: o `seo_maputo_tracking.md` visa
precisamente queries como `fidelizacao clientes maputo` e
`fidelizacao whatsapp mocambique`. "Retenção" não é termo de pesquisa comum
entre pequenos negócios; "fidelização" é.

**Recomendação, e o que fiz: manter.** O `<title>` usa o vocabulário de
pesquisa; o H1 e o `og:description` já lideram com a narrativa de retenção, que
é o enquadramento correto depois de a pessoa chegar. Fica aqui registado para a
tensão entre os dois documentos não voltar. Se discordar, é uma linha a mudar.

### 4.2 "Para negócios" na navegação — **implementado**

A página tem oito secções mas a navegação tinha quatro destinos. Ficavam de fora
`sem-app` e `negocios` — sendo que `negocios` é a secção de segmentação vertical
(barbearia, café, restaurante, beleza), conteúdo de qualificação que só era
alcançável por scroll. O `WEBSITE_INFORMATION_ARCHITECTURE.md` já previa "Para
negócios" na navegação.

Adicionado nas duas navegações, entre "Produto" e "Planos", respeitando a ordem
das secções no documento. Eventos novos: `nav_businesses` e
`nav_businesses_mobile`. O `syncActiveNav` é genérico e apanha o novo destino
sem alteração de JavaScript.

A secção `sem-app` continua fora da navegação — é conteúdo de apoio, não destino.

---

## 5. O que não recomendo mexer

- **A arquitetura estática.** HTML/CSS/JS sem build, publicado de `docs/`.
  Adequado ao propósito e sem custo de manutenção.
- **A ausência de formulário.** Decisão documentada e coerente com o mercado.
- **O peso do Google Play.** Já foi reequilibrado na reescrita de 31 de agosto.
- **O JSON-LD.** Está correto e completo: `FAQPage` com 10 pares,
  `Organization`, `WebSite`, `WebPage`, `Offer` do plano Free a 0 MZN — que é
  verdadeiro e não contradiz a política de não publicar preços dos planos pagos.

---

## 6. Perguntas em aberto

- **L1** — "Gestão de equipa" deve passar a ser exclusiva do Business (§1.1)? Se
  sim, é preciso saber se algum negócio em plano inferior já a usa.
- **L2** — As quotas por plano vão ser configuradas, ou a promessa de
  "capacidade" sai da página (§1.2)?
- **L3** — Qual o destino do plano `growth` (§1.3)?
- **L4** — O `whatsapp_automation` no Free é deliberado (§1.4)?
- **L5** — O Business deve passar a anunciar `campaigns`, `cloud_backup`,
  visitas e inquéritos, que já inclui e não menciona (§1.5)?
- **L6** — Confirma-se manter "fidelização" no título por motivos de SEO (§4.1)?
