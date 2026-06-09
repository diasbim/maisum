class AppStrings {
  static String clientesCount(int total) =>
      '$total ${total == 1 ? 'cliente' : 'clientes'}';

  static String clientesVisibleCount(int visible, int total) {
    final visibleLabel = visible == 1 ? 'cliente' : 'clientes';
    final totalLabel = total == 1 ? 'cliente' : 'clientes';
    return '$visible $visibleLabel de $total $totalLabel';
  }

  // App
  static const String appName = 'MaisUm';

  // Auth
  static const String phoneNumber = 'Número de telemóvel';
  static const String phoneHint = '+258 84 000 0000';
  static const String continuar = 'Continuar';
  static const String otpTitle = 'Código de verificação';
  static const String otpSubtitle = 'Enviámos um código para ';
  static const String verificar = 'Verificar';
  static const String otpResend = 'Reenviar código';
  static const String logout = 'Sair';

  // Dashboard
  static const String dashboard = 'Dashboard';
  static const String totalClientes = 'Total clientes';
  static const String novaVenda = 'Nova Venda';
  static const String clientes = 'Clientes';
  static const String recompensas = 'Recompensas';
  static const String vendasHoje = 'Vendas Hoje';
  static const String pontosHoje = 'Pontos Hoje';
  static const String pendentes = 'Pendentes';
  static const String dashboardGreetingPrefix = 'Olá,';
  static const String dashboardGreetingFallback = 'Vendedor';
  static const String dashboardGreetingSubtitle =
      'Vamos vender mais hoje com menos toques.';
  static const String dashboardEmptyTitle =
      'Tudo pronto para a primeira venda.';
  static const String dashboardEmptySubtitle =
      'Adicione o primeiro cliente e registe uma venda em menos de 3 toques.';
  static const String dashboardLoadErrorTitle =
      'Não foi possível abrir o painel.';
  static const String dashboardLoadErrorSubtitle =
      'Puxe para atualizar ou tente novamente em alguns segundos.';
  static const String dashboardSectionToday = 'Hoje';
  static const String dashboardSectionQuick = 'Rápido';
  static const String dashboardQuickClientsSubtitle = 'Abrir lista';
  static const String dashboardQuickSalesSubtitle = 'Últimas vendas';
  static const String dashboardQuickRewardsSubtitle = 'Criar ou resgatar';
  static const String dashboardQuickSyncOk = 'Tudo sincronizado';
  static const String dashboardRegistered = 'Registados';
  static const String dashboardReturningCustomers = 'Clientes recorrentes';
  static const String dashboardStreakTitle = 'Sequência de vendas';
  static const String dashboardStreakDaySingular = 'dia seguido';
  static const String dashboardStreakDayPlural = 'dias seguidos';
  static const String dashboardStreakStatusRisk = 'Em risco';
  static const String dashboardStreakStatusStable = 'Estável';
  static const String dashboardSaleCardSubtitle =
      'Registrar venda em menos de 5 segundos';
  static const String dashboardSaleCta = 'Registrar Venda';
  static const String subscriptionNoStatus = 'Sem estado';
  static const String syncRetrying = 'A tentar novamente';

  // Sales
  static const String novaVendaTitle = 'Nova Venda';
  static const String cliente = 'Cliente';
  static const String confirmar = 'Confirmar';
  static const String resumo = 'Resumo';
  static const String valorStep = 'Valor';
  static const String nomeOuTelefoneCliente = 'Nome ou telefone do cliente';
  static const String outroValor = 'Outro valor';
  static const String ultimo = 'Último';
  static const String clienteGanhara = 'O cliente ganhará';
  static const String pontosAposConfirmacao =
      'Os pontos serão adicionados após confirmação da venda.';
  static const String por = 'por';
  static const String selecionarCliente = 'Selecionar cliente';
  static const String buscarTelefone = 'Buscar por telefone';
  static const String novoCliente = 'Novo cliente';
  static const String valor = 'Valor (MZN)';
  static const String valorHint = 'Ex: 350';
  static const String pontosPreview = 'pontos';
  static const String confirmarVenda = 'Confirmar Venda';
  static const String vendaRegistada = 'Venda registada!';
  static const String mensagemProntaEnvio = 'Mensagem pronta para enviar';
  static const String enviarSms = 'Enviar SMS';
  static const String voltarAoInicio = 'Voltar ao início';
  static const String pontosAtribuidos = 'pontos atribuídos';
  static const String continuar2 = 'Continuar';
  static const String nome = 'Nome';
  static const String nomeHint = 'Nome do cliente';
  static const String criarCliente = 'Criar cliente';

  // Customers
  static const String resgatarRecompensa = 'Resgatar recompensa';
  static const String resgateRegistado = 'Resgate registado com sucesso!';
  static const String clientesTitle = 'Clientes';
  static const String buscarCliente = 'Buscar cliente...';
  static const String semClientes = 'Nenhum cliente ainda';
  static const String adicionarCliente = 'Adicionar cliente';
  static const String totalPontos = 'Total de pontos';
  static const String historicoVendas = 'Histórico de vendas';
  static const String enviarWhatsApp = 'Enviar WhatsApp';
  static const String semVendas = 'Nenhuma venda ainda';
  static const String adicionarPontos = 'Adicionar pontos';
  static const String ultimaVisita = 'Última visita';
  static const String pontos = 'pontos';
  static const String pontosAbrev = 'pts';
  static const String clienteNaoEncontrado = 'Cliente não encontrado';
  static const String clienteAtivo = 'Cliente activo';
  static const String clienteInativo = 'Cliente inativo';
  static const String saldoPontos = 'Saldo de pontos';
  static const String aproxPrefix = '~';
  static const String moedaMzn = 'MZN';
  static const String comprasSuffix = 'em compras';
  static const String verHistorico = 'Ver histórico';
  static const String historicoCompras = 'Histórico de compras';
  static const String verTudo = 'Ver tudo';
  static const String progressoProximaRecompensa =
      'Progresso para próxima recompensa';
  static const String semRecompensasAtivas = 'Sem recompensas activas';
  static const String recompensaPronta = 'Recompensa pronta';
  static const String faltam = 'Faltam';
  static const String para = 'para';

  // Rewards / Redemption
  static const String resgatar = 'Resgatar Recompensa';
  static const String confirmarResgate = 'Confirmar Resgate';
  static const String recompensasDisponiveis = 'Disponíveis para resgate';
  static const String recompensasInsuficientes = 'Pontos insuficientes';
  static const String notificarWhatsApp = 'Notificar via WhatsApp';
  static const String recompensasTitle = 'Recompensas';
  static const String novaRecompensa = 'Nova Recompensa';
  static const String semRecompensas = 'Nenhuma recompensa ainda';
  static const String criarRecompensa = 'Criar recompensa';
  static const String nomeRecompensa = 'Nome da recompensa';
  static const String pontosNecessarios = 'Pontos necessários';
  static const String descricao = 'Descrição (opcional)';
  static const String guardar = 'Guardar';
  static const String pontosRequeridos = 'pontos requeridos';
  static const String recompensasSection = 'As tuas recompensas';
  static const String recompensasOrdenar = 'Ordenar';
  static const String recompensasHeroTitle =
      'Motiva os teus clientes a voltarem';
  static const String recompensasHeroBody =
      'Cria recompensas atrativas e aumenta as visitas.';
  static const String recompensaAtiva = 'Ativa';
  static const String recompensasInsightTitle =
      'Recompensas simples motivam mais.';
  static const String recompensasInsightBody =
      'Mantém poucos prémios e fáceis de entender.';

  // Sync
  static const String sincronizado = 'Sincronizado';
  static const String sincronizando = 'Sincronizando...';
  static const String pendentesSync = 'pendentes';
  static const String syncInterrompida = 'Sincronização interrompida';
  static const String syncFalhaPendentes =
      'Alguns itens não foram sincronizados.';
  static const String syncIndiceFaltando = 'Índice do Firestore em falta.';
  static const String syncPermissaoNegada = 'Sem permissão para sincronizar.';
  static const String syncPendingToSend = 'por enviar';
  static const String offline = 'Sem ligação à internet';
  static const String semLigacao = 'A trabalhar offline';
  static const String syncRetryNow = 'Tentar agora';
  static const String syncFailedActionable =
      'Não foi possível sincronizar alguns registos. Verifique a internet e tente novamente.';
  static const String syncOfflineSavedSubtitle =
      'As vendas continuam guardadas no telemóvel.';
  static const String syncRunningSubtitle =
      'A atualizar clientes, vendas e recompensas.';
  static const String syncPendingSubtitle =
      'Toque para ver o que falta enviar.';
  static const String syncReadySubtitle =
      'Tudo pronto para continuar a trabalhar.';

  // Settings
  static const String definicoes = 'Definições';
  static const String nomeNegocio = 'Nome do negócio';
  static const String editarNomeNegocio = 'Editar nome do negócio';
  static const String nomeNegocioHint = 'Introduza o nome do negócio';
  static const String nomeNegocioAtualizado = 'Nome do negócio atualizado';
  static const String subscricao = 'Subscrição';
  static const String subscricaoAdmin = 'Admin da subscrição';
  static const String subscricaoAdminDesc = 'Ver plano e limites locais';
  static const String planoAtual = 'Plano atual';
  static const String estadoSubscricao = 'Estado';
  static const String limites = 'Limites';
  static const String quotaWhatsApp = 'Mensagens WhatsApp';
  static const String quotaUsadas = 'Usadas';
  static const String quotaRestante = 'Restante';
  static const String quotaRenova = 'Renova em';
  static const String funcionalidades = 'Funcionalidades';
  static const String flagsRemotas = 'Flags remotas';
  static const String periodo = 'Período';
  static const String testeAte = 'Teste até';
  static const String graciaAte = 'Graça até';
  static const String identificadores = 'Identificadores';
  static const String merchantId = 'Merchant ID';
  static const String appUserId = 'App User ID';
  static const String deviceId = 'Device ID';
  static const String sessaoValidaAte = 'Sessão válida até';
  static const String taxaPontos = 'Taxa de pontos';
  static const String taxaDesc = '1 ponto por cada 100 MZN';
  static const String versao = 'Versão';
  static const String confirmarLogout = 'Confirmar saída';
  static const String confirmarLogoutMsg = 'Tem a certeza que quer sair?';
  static const String cancelar = 'Cancelar';

  // PIN Setup
  static const String pinSetupTitle = 'Criar PIN de acesso';
  static const String pinSetupSubtitle =
      'Escolha um PIN de 4 dígitos para aceder rapidamente';
  static const String pinConfirmTitle = 'Confirmar PIN';
  static const String pinConfirmSubtitle = 'Introduza o mesmo PIN novamente';
  static const String pinCreatedSuccess = 'PIN criado com sucesso!';
  static const String pinMismatch = 'Os PINs não coincidem. Tente novamente.';

  // PIN Entry
  static const String pinEntryTitle = 'Bem-vindo de volta!';
  static const String pinEntrySubtitle = 'Introduza o seu PIN para continuar';
  static const String pinIncorrect = 'PIN incorreto';
  static const String pinForgot = 'Esqueci o PIN';
  static const String pinBlocked =
      'Demasiadas tentativas. Faça login novamente.';

  static const String resgatarBtn = 'Resgatar';

  // SMS permission
  static const String smsPermissionTitle = 'Permitir SMS de pagamentos';
  static const String smsPermissionBody =
      'MaisUm usa SMS apenas para detectar pagamentos M-Pesa/eMola '
      'e sugerir vendas rapidamente. Nenhuma mensagem pessoal é lida.';
  static const String smsPermissionAllow = 'Permitir SMS';
  static const String smsPermissionSkip = 'Continuar sem SMS';
  static const String smsPermissionDone = 'Permissão registada.';

  // Customer edit
  static const String editarCliente = 'Editar cliente';

  // Redemption confirmation
  static const String resgateConfirmado = 'Resgate confirmado!';
  static const String codigoResgate = 'Código de resgate';
  static const String concluir = 'Concluir';

  // Errors
  static const String erroGenerico = 'Algo correu mal. Tente novamente.';
  static const String erroGenericoAcao =
      'Não foi possível concluir esta ação. Tente novamente.';
  static const String erroRede = 'Sem ligação à internet.';
  static const String erroAuth = 'Sessão expirada. Faça login novamente.';
  static const String erroServidor = 'Erro no servidor. Tente mais tarde.';
  static const String tentar = 'Tentar novamente';
  static const String funcaoIndisponivel =
      'Funcionalidade indisponível no seu plano.';
  static const String limiteSoftAviso =
      'Limite mensal atingido. Vamos sincronizar depois.';
  static const String whatsappQueued = 'Será enviado quando online ⏳';
  static const String whatsappSent = 'WhatsApp enviado ✅';
  static const String phoneRequired = 'Introduza o número de telemóvel';
  static const String otpRequired = 'Introduza o código de 6 dígitos';
  static const String amountRequired = 'Introduza o valor da venda';
  static const String amountInvalid = 'Valor inválido';
  static const String nameRequired = 'Introduza o nome do cliente';
  static const String customerPhoneDuplicate =
      'Este número já está associado a outro cliente nesta conta.';
  static const String customerCreatedSuccess = 'Cliente criado com sucesso.';
  static const String saleRegisteredSuccess = 'Venda registada com sucesso.';
  static const String dateSavedSuccess = 'Data guardada com sucesso.';
  static const String rewardNameRequired = 'Introduza o nome da recompensa';
  static const String pointsRequired = 'Introduza os pontos necessários';
  static const String merchantNameRequired = 'Introduza o nome do negócio';
}
