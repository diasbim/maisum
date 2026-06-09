import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';

class OnboardingEntryScreen extends StatefulWidget {
  const OnboardingEntryScreen({super.key});

  @override
  State<OnboardingEntryScreen> createState() => _OnboardingEntryScreenState();
}

class _OnboardingEntryScreenState extends State<OnboardingEntryScreen> {
  _OnboardingIntent? _selectedIntent;
  String? _errorMessage;

  void _selectIntent(_OnboardingIntent intent) {
    setState(() {
      _selectedIntent = intent;
      _errorMessage = null;
    });
  }

  void _continue() {
    if (_selectedIntent == null) {
      const message = 'Selecione uma opcao para continuar.';
      setState(() => _errorMessage = message);
      SemanticsService.announce(message, Directionality.of(context));
      return;
    }

    final route = _selectedIntent == _OnboardingIntent.joinExisting
        ? '/link-device'
        : '/merchant-config';
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Como comecar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Passo 1 de 2',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Progresso do onboarding',
            value: '50 por cento, passo 1 de 2',
            readOnly: true,
            child: LinearProgressIndicator(
              value: 0.5,
              borderRadius: BorderRadius.circular(999),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Escolha uma opcao para continuar.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          _IntentCard(
            icon: Icons.link_rounded,
            intent: _OnboardingIntent.joinExisting,
            isSelected: _selectedIntent == _OnboardingIntent.joinExisting,
            onSelected: _selectIntent,
            title: 'Entrar em barbearia existente',
            subtitle: 'Usar codigo da barbearia.',
            semanticsLabel: 'Entrar em barbearia existente',
            semanticsHint:
                'Abre o fluxo para vincular este dispositivo com codigo.',
          ),
          const SizedBox(height: 12),
          _IntentCard(
            icon: Icons.storefront_rounded,
            intent: _OnboardingIntent.createNew,
            isSelected: _selectedIntent == _OnboardingIntent.createNew,
            onSelected: _selectIntent,
            title: 'Criar nova barbearia',
            subtitle: 'Iniciar uma nova configuracao de negocio.',
            semanticsLabel: 'Criar nova barbearia',
            semanticsHint: 'Abre o fluxo de criacao da barbearia.',
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              container: true,
              label: 'Erro: $_errorMessage',
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: theme.colorScheme.errorContainer,
                  border: Border.all(color: theme.colorScheme.error),
                ),
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              button: true,
              label: 'Continuar para o proximo passo',
              hint: 'Abre o fluxo escolhido.',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _continue,
                child: const Text('Continuar'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              'Pode concluir em etapas. O app retoma de onde parou.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

enum _OnboardingIntent { joinExisting, createNew }

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.icon,
    required this.intent,
    required this.isSelected,
    required this.onSelected,
    required this.title,
    required this.subtitle,
    required this.semanticsLabel,
    required this.semanticsHint,
  });

  final IconData icon;
  final _OnboardingIntent intent;
  final bool isSelected;
  final ValueChanged<_OnboardingIntent> onSelected;
  final String title;
  final String subtitle;
  final String semanticsLabel;
  final String semanticsHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: semanticsLabel,
        hint: semanticsHint,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color:
                  isSelected ? colorScheme.primary : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelected(intent),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(subtitle, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IgnorePointer(
                    child: Radio<bool>(
                      value: true,
                      groupValue: isSelected,
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
