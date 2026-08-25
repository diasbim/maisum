# Auditoria do Website MaisUm

Data da auditoria: 25 de agosto de 2026

## 1. Resumo executivo

O website atual e uma landing page estatica, publicada a partir de `docs/` no GitHub Pages. A pagina ja comunica com pequenos negocios em Mocambique, mas a narrativa continua concentrada em pontos, WhatsApp, instalacao da app Android e exemplos de barbearia.

O produto implementado e mais amplo do que essa narrativa: inclui CRM leve, historico de vendas, recompensas, segmentos de retencao, clientes em risco, recomendacoes de recuperacao, agendamentos, equipa, varios dispositivos e funcionamento offline.

Ao mesmo tempo, varias promessas atuais excedem o que o codigo suporta. Automacao completa de WhatsApp, confirmacao M-Pesa, campanhas completas, uma app para clientes e alguns resultados quantitativos nao podem ser apresentados como funcionalidades atuais.

## 2. Superficie atual

### Rotas publicas

- `/` — landing page em `docs/index.html`.
- `/privacy.html` — politica de privacidade.
- Nao existem paginas verticais para barbearias, restaurantes, cafes, saloes ou outros segmentos.

### Implementacao

- HTML, CSS e JavaScript sem framework ou etapa de compilacao.
- CSS e JavaScript incorporados em `docs/index.html`.
- Publicacao de `docs/` por GitHub Pages.
- Configuracao alternativa de Firebase Hosting tambem aponta para `docs/`.
- Google Fonts: Bricolage Grotesque e Outfit.
- Icones em SVG inline.
- Plausible carregado dinamicamente apenas fora de `file:`, `localhost` e `127.0.0.1`.

### Assets existentes

- Logotipo e icones da marca.
- Captura real do fluxo de registo de venda em formato desktop.
- Captura otimizada para telemovel.
- Nao existe uma captura de dashboard de retencao pronta para o website.

## 3. Design system atual

### Elementos a preservar

- Azul-marinho como cor de confianca e tecnologia.
- Amarelo/dourado como cor de acao e reconhecimento.
- Tipografia forte com Bricolage Grotesque nos titulos e Outfit no corpo.
- Cartoes arredondados, sombras suaves e bastante espaco em branco.
- Componentes leves, sem dependencias de JavaScript.
- Skip link, landmarks semanticos e suporte a `prefers-reduced-motion`.

### Problemas encontrados

- A composicao visual do hero e dominada pelo ecrã de venda no telemovel e por pontos.
- WhatsApp verde e usado como parte central da identidade do produto, em vez de canal.
- A regra `overflow-wrap:anywhere` parte palavras no meio no hero, incluindo em larguras comuns de telemovel e desktop.
- O CTA fixo em mobile promove a instalacao da app, apesar de a conversao principal pretendida ser uma conversa com o proprietario do negocio.
- A navegacao tem demasiados itens de funcionalidade e nao reflete a nova hierarquia de retencao.
- O hero associa a proposta a M-Pesa e a um corte gratis, duas mensagens inadequadas para o novo posicionamento.
- Nao existe uma visualizacao clara do ciclo de retencao, dos segmentos de clientes ou da acao recomendada.

## 4. Auditoria da narrativa atual

### Mensagem dominante

O website atual conta esta historia:

1. Registar uma venda.
2. Atribuir pontos.
3. Enviar WhatsApp.
4. Dar um corte gratis.
5. Fazer o cliente voltar.

Esta narrativa faz o MaisUm parecer um programa de pontos orientado a barbearias, apesar de usar expressoes mais amplas como "negocios locais".

### Assuncoes verticais

- Corte de 500 MT como transacao principal.
- Proximo corte como exemplo de agendamento.
- Corte gratis como recompensa principal.
- Tesoura, barbearia e mensagens do cliente sobre voltar na sexta.
- Crescimento descrito como reducao de no-show para cortes.

### Elementos reutilizaveis

- Estrutura de hero com dois CTAs.
- Fluxos visuais com cartoes e setas.
- Captura real do registo de venda.
- Secao offline.
- Gestao de equipa e varios dispositivos.
- FAQ com `details`/`summary`.
- CTA final e contacto WhatsApp.
- Navegacao mobile, observador de secoes e eventos Plausible.

## 5. Matriz de capacidades verificadas

Os estados abaixo refletem codigo executavel, e nao apenas documentos de roadmap, nomes de planos ou stubs.

| Capacidade | Estado | Evidencia |
| --- | --- | --- |
| CRM e perfis de clientes | Disponivel | `lib/features/customers/domain/customer.dart`; `lib/features/customers/presentation/customer_list_screen.dart` |
| Historico de visitas/vendas e gasto | Disponivel | `lib/features/sales/data/sale_dao.dart`; `lib/features/customers/presentation/customer_detail_screen.dart` |
| Pontos e recompensas | Disponivel | `lib/features/sales/data/sale_repository.dart`; `lib/features/rewards/data/redemption_repository.dart` |
| Selos, tiers de fidelizacao e missoes | Nao encontrado | Nao existem modelos ou fluxos implementados para estas mecanicas |
| Segmentos new, returning, regular, loyal, VIP, at-risk e inactive | Disponivel | `lib/features/customers/domain/customer.dart`; `functions/src/index.ts` |
| Taxa e resumo de retencao | Disponivel | `lib/features/dashboard/presentation/dashboard_controller.dart`; `lib/features/engage/data/engage_dao.dart` |
| Fila de recuperacao e proxima melhor acao | Disponivel | `lib/features/engage/data/engage_dao.dart`; `functions/src/index.ts` |
| Ofertas individuais de recuperacao | Disponivel | `lib/features/engage/domain/engage_models.dart` |
| Campanhas completas | Parcial | Existe controlo de entitlement, mas nao foi encontrado um motor completo de criacao e disparo |
| Lembretes automaticos | Em desenvolvimento | Existem filas e hooks parciais; a entrega ponta a ponta ainda requer validacao |
| Acao direta por WhatsApp | Disponivel | `lib/features/customers/presentation/customer_detail_screen.dart` |
| Envio automatico por fornecedor WhatsApp | Parcial | O backend aceita e enfileira; nao foi encontrado worker/provedor de entrega |
| SMS para clientes | Planeado | OTP de autenticacao nao equivale a canal de engagement |
| Email e push para clientes | Nao encontrado | Nao existem transporte, templates ou dependencia de push |
| Identificacao do cliente por telefone | Disponivel | Modelos de cliente e normalizacao de numero |
| Participacao por QR ou portal web | Nao encontrado | O QR existente liga dispositivos do negocio |
| App para clientes | Nao disponivel | O escopo atual exclui uma app dedicada ao cliente |
| App Android para o negocio | Disponivel | App Flutter e publicacao Google Play |
| Operacao offline e sincronizacao posterior | Disponivel | `lib/features/sales/data/sale_repository.dart`; `lib/features/sync/sync_service.dart` |
| Numeros +258 | Disponivel | `lib/core/utils/moz_phone_utils.dart` |
| Valores em MT/MZN | Disponivel | `lib/core/constants/app_strings.dart`; ecrãs de vendas e relatorios |
| Confirmacao ou deteccao M-Pesa | Planeado | Nao existem permissoes, parser ou integracao de pagamento implementados |
| Agendamentos | Disponivel | `lib/features/appointments/data/appointment_repository.dart` |
| Gestao de equipa | Disponivel | `lib/features/settings/data/staff_management_repository.dart` |
| Varios dispositivos | Disponivel | Fluxo de vinculacao por codigo |
| Varias localizacoes/filiais | Nao disponivel | Marcado como fora do escopo atual |
| Planos e limites | Parcial | Free, Starter, Pro e Business existem; os precos publicos dependem de configuracao remota |
| Tracking de conversao | Disponivel | Eventos Plausible de CTA e visualizacao de algumas secoes |

## 6. Claims atuais a remover ou corrigir

### Nao suportados

- "M-Pesa pronto" e notificacoes de pagamento M-Pesa confirmado.
- "WhatsApp automatico", "WhatsApp imediato" e envio "sem tocar em nada".
- "Engage completo".
- Starter com "campanhas" como capacidade totalmente funcional.
- Confirmacao de que uma venda offline nunca pode perder dados.

### Nao verificados

- "Centenas de vendas registadas".
- "Dezenas de clientes a voltar".
- Registo garantido em menos de cinco segundos.
- Equipa preparada em tres minutos.
- Maior taxa de resposta.
- Reducao de no-show e regresso mais rapido como resultados comprovados.

### Formulações seguras

- "Registe vendas e visitas em poucos passos."
- "Abra uma conversa de WhatsApp com o contexto do cliente."
- "Veja clientes recorrentes e em risco."
- "Priorize a proxima acao de recuperacao."
- "Continue a registar vendas offline e sincronize quando a ligacao voltar."
- "Identifique clientes por numero de telefone; o cliente nao precisa de instalar uma app."

## 7. SEO atual

### Pontos positivos

- `lang="pt-MZ"`.
- Canonical, Open Graph, Twitter Card e JSON-LD.
- Metadados geograficos para Maputo e Mocambique.
- FAQ estruturado.
- Sitemap e robots.

### Problemas

- O titulo e a descricao lideram com "gestao e fidelizacao", e nao com retencao.
- WhatsApp recebe peso excessivo no Open Graph.
- O `featureList` estruturado inclui claims sobre cortes, WhatsApp automatico e Engage que precisam de correcao.
- FAQ estruturado e visivel reforca WhatsApp como experiencia unica.
- A imagem social mostra o ecrã de venda, nao a proposta de retencao. Pode continuar temporariamente por ser o unico asset real adequado.

## 8. Conversao e analytics

### Atual

- CTAs para WhatsApp e Google Play.
- Eventos Plausible por link.
- Visualizacao de duas secoes.
- Variantes aleatorias do CTA mobile e da secao de crescimento.

### Problemas

- A instalacao Android domina o hero, o CTA final e o CTA fixo mobile.
- Variantes sao escolhidas aleatoriamente a cada carregamento, sem persistencia ou plano de experiencia.
- Nao existe tracking de profundidade de scroll.
- Nem todas as secoes estrategicas tem eventos de visualizacao.

### Direcao

- WhatsApp de vendas como conversao principal.
- Demo/como funciona como conversao secundaria.
- Google Play como prova e acao secundaria para o proprietario.
- Eventos deterministas para CTA, navegacao, planos, demo, secoes e profundidade de scroll.

## 9. Recomendacao final

Manter a arquitetura estatica e reconstruir a pagina como uma plataforma de retencao para pequenos negocios. O hero deve ser liderado por um dashboard de retencao e por um ciclo de cliente, nao por um telemovel ou cartao de pontos.

A nova pagina deve usar apenas capacidades verificadas como claims atuais, marcar automacao de lembretes como "Em desenvolvimento" quando relevante e omitir funcionalidades sem compromisso de roadmap. Barbearias devem aparecer como exemplo, ao lado de outros negocios que dependem de visitas repetidas.
