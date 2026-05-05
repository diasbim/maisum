import 'package:flutter/material.dart';

import 'legal_screen.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: 'Política de Privacidade',
      lastUpdated: '1 de Maio de 2025',
      sections: [
        LegalSection(
          number: '1',
          heading: 'Responsável pelo Tratamento',
          body:
              'O responsável pelo tratamento dos dados pessoais recolhidos '
              'através do MaisUm é o operador do estabelecimento comercial '
              'que utiliza esta aplicação.\n\n'
              'A presente Política de Privacidade foi elaborada em '
              'conformidade com a Lei n.º 7/2012, de 8 de Fevereiro '
              '(Lei da Informática) e com o Decreto n.º 42/2017, de '
              '31 de Agosto (Regulamento de Proteção de Dados Pessoais '
              'de Moçambique).',
        ),
        LegalSection(
          number: '2',
          heading: 'Dados Recolhidos',
          body:
              'Para o funcionamento do programa de fidelização, recolhemos '
              'e tratamos os seguintes dados pessoais dos clientes:\n\n'
              '• Nome completo;\n'
              '• Número de telemóvel;\n'
              '• Histórico de compras (valor e data);\n'
              '• Saldo de pontos e histórico de resgates.\n\n'
              'Relativamente ao operador do estabelecimento, recolhemos '
              'o número de telemóvel utilizado para autenticação.',
        ),
        LegalSection(
          number: '3',
          heading: 'Finalidade do Tratamento',
          body:
              'Os dados pessoais são tratados exclusivamente para as '
              'seguintes finalidades:\n\n'
              '• Gestão do programa de pontos e recompensas;\n'
              '• Identificação do cliente no momento da compra;\n'
              '• Comunicação de recompensas via WhatsApp, quando '
              'solicitado pelo operador;\n'
              '• Análise estatística agregada e anónima do desempenho '
              'do estabelecimento.\n\n'
              'Não utilizamos os dados para marketing direto sem '
              'consentimento explícito, nem os partilhamos com '
              'terceiros para fins comerciais.',
        ),
        LegalSection(
          number: '4',
          heading: 'Base Legal do Tratamento',
          body:
              'O tratamento de dados pessoais assenta nas seguintes '
              'bases legais, nos termos do Decreto n.º 42/2017:\n\n'
              '• Execução de contrato: para gerir a relação de '
              'fidelização entre o estabelecimento e o cliente;\n'
              '• Consentimento: para o envio de notificações via '
              'WhatsApp;\n'
              '• Interesse legítimo: para análise de atividade e '
              'melhoria do serviço.',
        ),
        LegalSection(
          number: '5',
          heading: 'Armazenamento e Segurança',
          body:
              'Os dados são armazenados:\n\n'
              '• Localmente no dispositivo do operador, em base de '
              'dados SQLite encriptada;\n'
              '• Na nuvem (Firebase/Firestore), quando a '
              'sincronização está ativa e o dispositivo tem ligação '
              'à internet.\n\n'
              'Adotamos medidas técnicas e organizativas adequadas '
              'para proteger os dados contra acesso não autorizado, '
              'perda acidental ou destruição, em conformidade com '
              'o artigo 19.º do Decreto n.º 42/2017.',
        ),
        LegalSection(
          number: '6',
          heading: 'Conservação dos Dados',
          body:
              'Os dados dos clientes são conservados enquanto o '
              'cliente mantiver uma relação ativa com o '
              'estabelecimento. O operador pode eliminar os dados '
              'de qualquer cliente a qualquer momento através da '
              'aplicação.\n\n'
              'Os dados do operador são conservados durante o '
              'período de vigência da conta, sendo eliminados nos '
              '30 dias seguintes ao encerramento da mesma.',
        ),
        LegalSection(
          number: '7',
          heading: 'Direitos dos Titulares dos Dados',
          body:
              'Nos termos da legislação moçambicana aplicável, '
              'qualquer titular de dados tem o direito de:\n\n'
              '• Aceder aos seus dados pessoais;\n'
              '• Retificar dados incorretos ou incompletos;\n'
              '• Opor-se ao tratamento dos seus dados;\n'
              '• Solicitar a eliminação dos seus dados.\n\n'
              'Para exercer estes direitos, o cliente deve dirigir-se '
              'diretamente ao operador do estabelecimento.',
        ),
        LegalSection(
          number: '8',
          heading: 'Partilha de Dados com Terceiros',
          body:
              'Não vendemos nem partilhamos dados pessoais com '
              'terceiros para fins comerciais.\n\n'
              'Os dados podem ser partilhados apenas com:\n\n'
              '• Prestadores de serviços de infraestrutura '
              '(Google Firebase), vinculados por acordos de '
              'confidencialidade;\n'
              '• Autoridades competentes, quando exigido por lei '
              'moçambicana.\n\n'
              'A transferência internacional de dados para os '
              'servidores do Google segue as garantias previstas '
              'no artigo 21.º do Decreto n.º 42/2017.',
        ),
        LegalSection(
          number: '9',
          heading: 'Cookies e Dados de Utilização',
          body:
              'A aplicação MaisUm não utiliza cookies. Podem ser '
              'recolhidos dados técnicos anónimos para diagnóstico '
              'de erros (ex.: modelo de dispositivo, versão do '
              'sistema operativo), sem que seja possível identificar '
              'o utilizador a partir dos mesmos.',
        ),
        LegalSection(
          number: '10',
          heading: 'Alterações à Política',
          body:
              'A presente Política de Privacidade pode ser '
              'atualizada periodicamente. Quaisquer alterações '
              'materiais serão comunicadas através da aplicação '
              'com antecedência mínima de 15 dias.\n\n'
              'A utilização continuada do serviço após a entrada '
              'em vigor das alterações constitui aceitação das '
              'mesmas.',
        ),
        LegalSection(
          number: '11',
          heading: 'Legislação Aplicável',
          body:
              'Esta Política é regida pela seguinte legislação '
              'moçambicana:\n\n'
              '• Lei n.º 7/2012, de 8 de Fevereiro — Lei da '
              'Informática (Artigos 24.º a 37.º);\n'
              '• Decreto n.º 42/2017, de 31 de Agosto — '
              'Regulamento de Proteção de Dados Pessoais;\n'
              '• Lei n.º 31/2009, de 24 de Julho — Lei das '
              'Transações Eletrónicas;\n'
              '• Lei n.º 3/1996, de 2 de Fevereiro — Lei de '
              'Defesa do Consumidor.',
        ),
        LegalSection(
          number: '12',
          heading: 'Contacto',
          body:
              'Para questões relacionadas com privacidade e '
              'proteção de dados, ou para exercer os seus direitos, '
              'contacte o operador do estabelecimento diretamente '
              'ou através dos canais de suporte disponíveis na '
              'aplicação.',
        ),
      ],
    );
  }
}
