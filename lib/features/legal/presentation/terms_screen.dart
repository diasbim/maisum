import 'package:flutter/material.dart';

import 'legal_screen.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: 'Termos e Condições',
      lastUpdated: '1 de Maio de 2025',
      sections: [
        LegalSection(
          number: '1',
          heading: 'Aceitação dos Termos',
          body:
              'Ao utilizar o programa de fidelização MaisUm, declara que leu, '
              'compreendeu e aceita ficar vinculado aos presentes Termos e '
              'Condições, bem como à nossa Política de Privacidade. Se não '
              'concordar com alguma disposição, não deverá utilizar o serviço.\n\n'
              'A utilização continuada do serviço após eventuais alterações aos '
              'presentes Termos constitui aceitação tácita das mesmas.',
        ),
        LegalSection(
          number: '2',
          heading: 'Descrição do Serviço',
          body:
              'O MaisUm é uma plataforma de gestão de fidelização destinada a '
              'estabelecimentos comerciais em Moçambique. O serviço permite:\n\n'
              '• Registo e gestão de clientes;\n'
              '• Atribuição de pontos de fidelização por cada compra;\n'
              '• Resgate de recompensas de acordo com o saldo de pontos;\n'
              '• Histórico de transações e relatórios de atividade.\n\n'
              'O operador do estabelecimento é o responsável pela exatidão dos '
              'dados introduzidos na plataforma.',
        ),
        LegalSection(
          number: '3',
          heading: 'Registo e Conta de Utilizador',
          body:
              'O acesso ao MaisUm requer autenticação por número de telemóvel '
              'moçambicano válido. O utilizador é responsável por:\n\n'
              '• Manter a confidencialidade do seu PIN de acesso;\n'
              '• Todas as ações realizadas com as suas credenciais;\n'
              '• Comunicar imediatamente qualquer acesso não autorizado.\n\n'
              'Reservamo-nos o direito de suspender contas que violem estes '
              'Termos ou que sejam utilizadas de forma fraudulenta.',
        ),
        LegalSection(
          number: '4',
          heading: 'Programa de Pontos e Recompensas',
          body:
              'A taxa de acumulação de pontos é definida pelo operador do '
              'estabelecimento. Os pontos:\n\n'
              '• Não têm valor monetário e não podem ser convertidos em '
              'dinheiro;\n'
              '• Não são transferíveis entre clientes;\n'
              '• Podem ser anulados em caso de devolução ou cancelamento de '
              'venda;\n'
              '• Estão sujeitos a validade definida pelo estabelecimento.\n\n'
              'As recompensas disponíveis e as condições de resgate são '
              'determinadas exclusivamente pelo operador do estabelecimento.',
        ),
        LegalSection(
          number: '5',
          heading: 'Utilização Aceitável',
          body:
              'O utilizador compromete-se a não:\n\n'
              '• Utilizar o serviço para fins ilegais ou fraudulentos;\n'
              '• Introduzir dados de clientes sem o seu consentimento;\n'
              '• Tentar aceder a contas de outros utilizadores;\n'
              '• Interferir no funcionamento normal do serviço;\n'
              '• Revender ou sublicenciar o acesso ao serviço a terceiros.',
        ),
        LegalSection(
          number: '6',
          heading: 'Limitação de Responsabilidade',
          body:
              'Na medida permitida pela legislação moçambicana, o MaisUm não '
              'será responsável por:\n\n'
              '• Perdas de dados resultantes de falha de dispositivo;\n'
              '• Danos indiretos ou lucros cessantes;\n'
              '• Interrupções de serviço devidas a causas de força maior;\n'
              '• Atos praticados por terceiros com acesso indevido ao '
              'dispositivo.\n\n'
              'Os direitos do consumidor previstos na Lei n.º 3/1996, de '
              '2 de Fevereiro (Lei de Defesa do Consumidor), permanecem '
              'plenamente aplicáveis.',
        ),
        LegalSection(
          number: '7',
          heading: 'Alterações ao Serviço',
          body:
              'Reservamo-nos o direito de modificar, suspender ou descontinuar '
              'qualquer funcionalidade do serviço, mediante aviso prévio '
              'razoável. As alterações materiais aos presentes Termos serão '
              'comunicadas através da aplicação com antecedência mínima de '
              '15 dias.',
        ),
        LegalSection(
          number: '8',
          heading: 'Lei Aplicável e Foro',
          body:
              'Os presentes Termos são regidos pela lei moçambicana, '
              'designadamente:\n\n'
              '• Lei n.º 3/1996, de 2 de Fevereiro — Lei de Defesa do '
              'Consumidor;\n'
              '• Lei n.º 31/2009, de 24 de Julho — Lei das Transações '
              'Eletrónicas;\n'
              '• Lei n.º 7/2012, de 8 de Fevereiro — Lei da Informática.\n\n'
              'Para a resolução de litígios decorrentes da utilização do '
              'serviço, as partes elegem o foro da Cidade de Maputo, com '
              'renúncia expressa a qualquer outro.',
        ),
        LegalSection(
          number: '9',
          heading: 'Contacto',
          body:
              'Para questões relacionadas com estes Termos, contacte-nos '
              'através da morada do estabelecimento ou pelo endereço de '
              'suporte disponível na aplicação.',
        ),
      ],
    );
  }
}
