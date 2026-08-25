# Arquitetura de Informacao do Website MaisUm

## 1. Escopo

Primeira versao do reposicionamento:

- Uma unica homepage.
- Conteudo principal em portugues para Mocambique.
- Sem paginas verticais adicionais.
- Sem formulario novo.
- Conversao principal pelo WhatsApp.
- Google Play como acao secundaria para o proprietario do negocio.

## 2. Navegacao principal

### Desktop

1. Produto.
2. Como funciona.
3. Retencao.
4. Para negocios.
5. Planos.
6. FAQ.
7. CTA: Comecar agora.

### Mobile

- Logo.
- CTA curto e visivel.
- Menu compacto com os mesmos destinos.
- CTA fixo para WhatsApp depois de o hero sair do ecrã.

## 3. Estrutura da homepage

### 01 — Hero

**Objetivo:** responder em menos de cinco segundos o que e, para quem e e qual problema resolve.

**Conteudo:**

- Categoria.
- Tagline.
- Explicacao do mecanismo.
- CTA principal para WhatsApp.
- CTA secundario para a demo.
- Microcopy sobre app do cliente nao obrigatoria e contexto local.

**Prova visual:**

- Dashboard ilustrativo de retencao.
- Cartoes de clientes regulares e em risco.
- Atividade de recompensa.
- Sinais de diferentes tipos de negocio.

**Evento:** `section_view_hero`.

### 02 — Mais do que fidelizacao

**Objetivo:** elevar a proposta acima de pontos e cartoes.

**Conteudo:**

- Reter.
- Reativar.
- Recompensar.
- Compreender.
- Agir.

**Mensagem:** cada capacidade serve um resultado de negocio.

**Evento:** `section_view_value`.

### 03 — Ciclo de retencao e demo

**Objetivo:** tornar o produto compreensivel sem uma demonstracao externa.

**Fluxo:**

1. Cliente visita.
2. Negocio identifica pelo telefone.
3. Regista a venda ou visita.
4. Cliente recebe pontos/recompensa.
5. MaisUm acompanha o comportamento.
6. Negocio executa a proxima acao.
7. Cliente volta e torna-se regular.

**CTA:** falar no WhatsApp para ver o fluxo aplicado ao negocio.

**Evento:** `section_view_how_it_works`.

### 04 — Sem app para o cliente

**Objetivo:** remover a principal friccao de adocao.

**Mensagem:** a equipa usa a app MaisUm; o cliente participa com o numero de telefone e pode ser contactado pelo WhatsApp.

**Limite de claim:** nao mostrar QR, portal web ou app do cliente como disponiveis.

**Evento:** `section_view_no_customer_app`.

### 05 — Motor de retencao

**Objetivo:** provar que MaisUm e uma plataforma de retencao, nao apenas fidelizacao.

**Conteudo:**

- Clientes totais.
- Taxa de retorno.
- Recorrentes.
- Regulares.
- Em risco.
- Inativos.
- Lista de estados suportados.

**Nota visual:** valores do mockup devem estar marcados como dados ilustrativos.

**Evento:** `section_view_retention`.

### 06 — Da informacao a acao

**Objetivo:** mostrar que o produto ajuda o proprietario a decidir o que fazer.

**Exemplo:**

- Cliente em risco.
- Ultima visita.
- Ritmo habitual.
- Acao recomendada: iniciar recuperacao ou criar oferta.

**Limite de claim:** pode mostrar a fila e a acao recomendada; lembrete automatico deve ser marcado como "Em desenvolvimento".

### 07 — Tipos de negocio

**Objetivo:** comunicar horizontalidade sem apagar a origem do produto.

**Categorias:**

- Barbearias.
- Beleza e saloes.
- Cafes.
- Restaurantes.
- Ginasios.
- Lavagens de carros.
- Estudios de unhas.
- Bem-estar e spas.
- Comercio local.
- Servicos para animais.

**Mensagem:** se o cliente pode voltar, o MaisUm pode ajudar o negocio a trazê-lo de volta.

**Evento:** `section_view_businesses`.

### 08 — Um produto, varios exemplos

**Objetivo:** tornar o uso concreto em varios setores.

**Exemplos:**

- Barbearia: recompensar visitas e recuperar clientes que deixaram de vir.
- Cafe: transformar compras ocasionais em habitos.
- Restaurante: incentivar frequencia em dias mais calmos.
- Salao: apoiar repeticao de marcacoes.
- Ginasio: identificar membros que estao a perder consistencia.

**Regra:** barbearia e apenas um exemplo.

### 09 — Pilares do produto

**Objetivo:** sustentar a credibilidade da categoria "plataforma".

**Pilares:**

1. Clientes.
2. Fidelizacao.
3. Engagement.
4. Retencao.

**Limite de claim:** nao listar selos, tiers, missoes, email, push ou campanhas completas.

**Evento:** `section_view_product`.

### 10 — Experiencia do proprietario

**Objetivo:** ligar a promessa ao produto ja implementado.

**Conteudo:**

- Clientes.
- Vendas.
- Recompensas.
- Retencao.
- Agendamentos.
- Analytics.
- Equipa.

**Prova visual:** captura real do ecrã de registo de venda.

**CTA de suporte:** abrir Google Play.

### 11 — Criado para a realidade local

**Objetivo:** preservar a vantagem local sem a tornar a proposta principal.

**Conteudo:**

- Mocambique.
- +258.
- MT/MZN.
- Android-first.
- WhatsApp como acao suportada.

**Limite de claim:** nao mencionar M-Pesa como integracao.

### 12 — Offline

**Objetivo:** sustentar a historia de confiabilidade.

**Fluxo:**

1. Ligacao enfraquece.
2. Venda fica guardada localmente.
3. Negocio continua.
4. Ligacao regressa.
5. Sincronizacao ocorre.

**Mensagem:** a comunicacao que depende de rede aguarda a ligacao.

**Evento:** `section_view_local`.

### 13 — Planos

**Objetivo:** mostrar um caminho de crescimento sem publicar precos nao validados.

**Planos:**

- Free — comecar a registar e recompensar.
- Starter — compreender resultados e organizar crescimento.
- Pro — aprofundar visao de risco e retencao.
- Business — equipa, varios dispositivos e recuperacao avancada.

**CTA:** encontrar o plano adequado pelo WhatsApp.

**Evento:** `section_view_pricing`.

### 14 — FAQ

**Perguntas:**

1. O que e o MaisUm?
2. Que tipos de negocio podem usar?
3. O cliente precisa de instalar uma app?
4. Como participa sem app?
5. E apenas um programa de fidelizacao?
6. Consigo ver clientes em risco?
7. Como funciona o WhatsApp?
8. Funciona em Mocambique?
9. Funciona offline?
10. Como funcionam os planos?

O JSON-LD deve repetir exatamente estas respostas.

### 15 — CTA final

**Titulo:** Os seus clientes ja conhecem o seu negocio. Agora dê-lhes um motivo para voltar.

**CTA principal:** Transformar clientes em regulares.

**CTA secundario:** Falar com o MaisUm.

**Evento:** `section_view_final_cta`.

### 16 — Footer

**Posicionamento:**

MaisUm — Plataforma de retencao de clientes para pequenos negocios. Transforme clientes ocasionais em clientes regulares.

**Links:**

- Produto.
- Como funciona.
- Para negocios.
- Retencao.
- Fidelizacao.
- Planos.
- FAQ.
- Privacidade.
- Contacto.
- Google Play.

## 4. Caminhos de conversao

### Caminho principal

Hero → proposta de retencao → prova de produto → CTA WhatsApp.

### Caminho de educacao

Hero → como funciona → motor de retencao → pilares → CTA final.

### Caminho por afinidade

Hero → tipos de negocio → exemplo vertical → WhatsApp.

### Caminho de validacao

Hero → experiencia do proprietario → local/offline → planos → WhatsApp.

## 5. Eventos Plausible

### Cliques

- `cta_whatsapp_header`
- `cta_whatsapp_hero`
- `cta_demo_hero`
- `cta_whatsapp_demo`
- `cta_whatsapp_retention`
- `cta_play_store_product`
- `cta_whatsapp_pricing`
- `cta_whatsapp_final`
- `cta_whatsapp_mobile`
- `cta_play_store_footer`
- `cta_whatsapp_footer`
- `nav_product`
- `nav_how_it_works`
- `nav_retention`
- `nav_businesses`
- `nav_pricing`
- `nav_faq`

### Visualizacao

- `section_view_hero`
- `section_view_value`
- `section_view_how_it_works`
- `section_view_no_customer_app`
- `section_view_retention`
- `section_view_businesses`
- `section_view_product`
- `section_view_local`
- `section_view_pricing`
- `section_view_final_cta`

### Profundidade

- `scroll_depth_25`
- `scroll_depth_50`
- `scroll_depth_75`
- `scroll_depth_100`

## 6. SEO

### Tema principal

- Plataforma de retencao de clientes.
- Software de fidelizacao para pequenos negocios.
- Retencao de clientes para pequenos negocios.

### Contexto local

- Software de fidelizacao em Mocambique.
- Gestao de clientes em Mocambique.
- Retencao de clientes em Maputo.

### Tema vertical de suporte

Barbearias, saloes, cafes e restaurantes podem aparecer no corpo, mas nao dominam o titulo, H1 ou descricao.

## 7. Limites desta entrega

- Nao criar `/barbershops`, `/restaurants`, `/cafes`, `/salons`, `/gyms` ou outras paginas.
- Nao criar um novo funil de signup.
- Nao alterar o produto Flutter, backend ou planos remotos.
- Nao publicar valores.
- Nao inventar testemunhos, logos, metricas ou resultados.
- Nao apresentar funcionalidades sem implementacao como roadmap confirmado.
