import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';

class SurveyBuilderScreen extends ConsumerStatefulWidget {
  const SurveyBuilderScreen({super.key});

  @override
  ConsumerState<SurveyBuilderScreen> createState() =>
      _SurveyBuilderScreenState();
}

class _SurveyBuilderScreenState extends ConsumerState<SurveyBuilderScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<_DraftQuestion> _questions = [];
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(engageAccessProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Survey Builder'),
        backgroundColor: AppColors.offWhite,
        elevation: 0,
      ),
      body: accessAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (_, __) => const EmptyState(
          title: 'Nao foi possivel validar acesso',
          subtitle: 'Tente novamente em alguns segundos.',
        ),
        data: (access) {
          if (!access.canManageSurveys) {
            return const EmptyState(
              title: 'Surveys indisponiveis no seu plano',
              subtitle: 'Criacao de surveys e exclusiva do plano Business.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              const Text(
                'Template rapido',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _templates
                    .map(
                      (template) => ActionChip(
                        label: Text(template.title),
                        onPressed: () => _applyTemplate(template),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Titulo',
                  hintText: 'Ex.: Porque voce nao voltou?',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descricao (opcional)',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Perguntas (max 5)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  TextButton.icon(
                    onPressed: _questions.length >= 5 ? null : _addQuestion,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_questions.isEmpty)
                const Text('Adicione pelo menos uma pergunta.')
              else
                ..._questions.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _QuestionCard(
                      index: entry.key,
                      value: entry.value,
                      onChanged: (value) =>
                          setState(() => _questions[entry.key] = value),
                      onRemove: () =>
                          setState(() => _questions.removeAt(entry.key)),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _submitting ? null : _publish,
                icon: _submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_outlined),
                label: Text(_submitting ? 'Publicando...' : 'Publicar Survey'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _applyTemplate(_SurveyTemplate template) {
    setState(() {
      _titleController.text = template.title;
      _descriptionController.text = template.description;
      _questions
        ..clear()
        ..addAll(template.questions);
    });
  }

  void _addQuestion() {
    setState(() {
      _questions.add(
        const _DraftQuestion(
          questionText: '',
          questionType: SurveyQuestionType.shortText,
          isRequired: true,
          options: <String>[],
        ),
      );
    });
  }

  Future<void> _publish() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppFeedback.showMessage(context, message: 'Informe o titulo do survey.');
      return;
    }
    if (_questions.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: 'Adicione ao menos uma pergunta.',
      );
      return;
    }
    if (_questions.length > 5) {
      AppFeedback.showMessage(
        context,
        message: 'Cada survey suporta no maximo 5 perguntas.',
      );
      return;
    }

    final invalidIndex = _questions.indexWhere(
      (question) => question.questionText.trim().isEmpty,
    );
    if (invalidIndex >= 0) {
      AppFeedback.showMessage(
        context,
        message: 'Pergunta ${invalidIndex + 1} sem texto.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final questions = _questions
          .asMap()
          .entries
          .map(
            (entry) => EngageSurveyQuestion(
              id: '',
              surveyId: '',
              questionText: entry.value.questionText.trim(),
              questionType: entry.value.questionType,
              sortOrder: entry.key,
              isRequired: entry.value.isRequired,
              options: entry.value.options,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          )
          .toList();

      await ref
          .read(engageRepositoryProvider)
          .createSurvey(
            title: title,
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            questions: questions,
          );

      await ref.read(engageSurveysProvider.notifier).refresh();
      await ref.read(engageSurveyAnalyticsProvider.notifier).refresh();
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: 'Survey publicado com sucesso',
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showMessage(context, message: error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.value,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _DraftQuestion value;
  final ValueChanged<_DraftQuestion> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pergunta ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextFormField(
              initialValue: value.questionText,
              decoration: const InputDecoration(labelText: 'Texto da pergunta'),
              onChanged: (text) =>
                  onChanged(value.copyWith(questionText: text)),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              value: value.questionType,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: SurveyQuestionType.values
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (selected) {
                if (selected == null) return;
                onChanged(value.copyWith(questionType: selected));
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile.adaptive(
              value: value.isRequired,
              title: const Text('Obrigatoria'),
              contentPadding: EdgeInsets.zero,
              onChanged: (selected) =>
                  onChanged(value.copyWith(isRequired: selected)),
            ),
            if (value.questionType == SurveyQuestionType.multipleChoice) ...[
              TextFormField(
                initialValue: value.options.join(', '),
                decoration: const InputDecoration(
                  labelText: 'Opcoes (separadas por virgula)',
                ),
                onChanged: (text) {
                  final options = text
                      .split(',')
                      .map((item) => item.trim())
                      .where((item) => item.isNotEmpty)
                      .toList();
                  onChanged(value.copyWith(options: options));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DraftQuestion {
  const _DraftQuestion({
    required this.questionText,
    required this.questionType,
    required this.isRequired,
    required this.options,
  });

  final String questionText;
  final String questionType;
  final bool isRequired;
  final List<String> options;

  _DraftQuestion copyWith({
    String? questionText,
    String? questionType,
    bool? isRequired,
    List<String>? options,
  }) {
    return _DraftQuestion(
      questionText: questionText ?? this.questionText,
      questionType: questionType ?? this.questionType,
      isRequired: isRequired ?? this.isRequired,
      options: options ?? this.options,
    );
  }
}

class _SurveyTemplate {
  const _SurveyTemplate({
    required this.title,
    required this.description,
    required this.questions,
  });

  final String title;
  final String description;
  final List<_DraftQuestion> questions;
}

const List<_SurveyTemplate> _templates = [
  _SurveyTemplate(
    title: 'Why Didn\'t You Return?',
    description: 'Entender principais razoes de inatividade.',
    questions: [
      _DraftQuestion(
        questionText: 'Qual foi o principal motivo para nao voltar?',
        questionType: SurveyQuestionType.multipleChoice,
        isRequired: true,
        options: ['Preco', 'Atendimento', 'Localizacao', 'Horario', 'Outro'],
      ),
      _DraftQuestion(
        questionText: 'O que faria voce voltar?',
        questionType: SurveyQuestionType.shortText,
        isRequired: false,
        options: [],
      ),
    ],
  ),
  _SurveyTemplate(
    title: 'Customer Satisfaction',
    description: 'Medir satisfacao geral com a experiencia.',
    questions: [
      _DraftQuestion(
        questionText: 'Como voce avalia sua experiencia?',
        questionType: SurveyQuestionType.rating,
        isRequired: true,
        options: [],
      ),
      _DraftQuestion(
        questionText: 'Recomendaria nosso servico?',
        questionType: SurveyQuestionType.yesNo,
        isRequired: true,
        options: [],
      ),
    ],
  ),
  _SurveyTemplate(
    title: 'Staff Evaluation',
    description: 'Avaliar atendimento da equipa.',
    questions: [
      _DraftQuestion(
        questionText: 'Como avalia o atendimento da equipa?',
        questionType: SurveyQuestionType.rating,
        isRequired: true,
        options: [],
      ),
      _DraftQuestion(
        questionText: 'Quer destacar algum colaborador?',
        questionType: SurveyQuestionType.shortText,
        isRequired: false,
        options: [],
      ),
    ],
  ),
  _SurveyTemplate(
    title: 'Promotion Interest',
    description: 'Identificar interesse em promocoes.',
    questions: [
      _DraftQuestion(
        questionText: 'Que tipo de promocao prefere?',
        questionType: SurveyQuestionType.multipleChoice,
        isRequired: true,
        options: ['Desconto', 'Pontos extras', 'Brinde', 'Pacote especial'],
      ),
      _DraftQuestion(
        questionText: 'Aceita receber promocoes no WhatsApp?',
        questionType: SurveyQuestionType.yesNo,
        isRequired: true,
        options: [],
      ),
    ],
  ),
  _SurveyTemplate(
    title: 'General Feedback',
    description: 'Coletar feedback aberto do cliente.',
    questions: [
      _DraftQuestion(
        questionText: 'Como podemos melhorar sua experiencia?',
        questionType: SurveyQuestionType.shortText,
        isRequired: true,
        options: [],
      ),
    ],
  ),
];
