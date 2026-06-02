import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';

class SurveyResponseScreen extends ConsumerStatefulWidget {
  const SurveyResponseScreen({super.key});

  @override
  ConsumerState<SurveyResponseScreen> createState() =>
      _SurveyResponseScreenState();
}

class _SurveyResponseScreenState extends ConsumerState<SurveyResponseScreen> {
  final _customerIdController = TextEditingController();
  final _channelController = TextEditingController(text: 'manual');
  String? _selectedSurveyId;
  bool _submitting = false;
  final Map<String, dynamic> _answers = <String, dynamic>{};

  @override
  void dispose() {
    _customerIdController.dispose();
    _channelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(engageAccessProvider);
    final surveysAsync = ref.watch(engageSurveysProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Enviar Survey'),
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
              title: 'Envio de surveys indisponivel',
              subtitle: 'Funcionalidade exclusiva do plano Business.',
            );
          }

          return surveysAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
            error: (_, __) => const EmptyState(
              title: 'Nao foi possivel carregar surveys',
              subtitle: 'Atualize e tente novamente.',
            ),
            data: (surveys) {
              if (surveys.isEmpty) {
                return const EmptyState(
                  title: 'Nenhum survey ativo',
                  subtitle: 'Crie um survey antes de enviar respostas.',
                );
              }

              final selected = surveys.firstWhere(
                (survey) =>
                    survey.id == (_selectedSurveyId ?? surveys.first.id),
                orElse: () => surveys.first,
              );

              if (_selectedSurveyId == null) {
                _selectedSurveyId = selected.id;
              }

              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedSurveyId,
                    decoration: const InputDecoration(labelText: 'Survey'),
                    items: surveys
                        .map(
                          (survey) => DropdownMenuItem(
                            value: survey.id,
                            child: Text(survey.title),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedSurveyId = value;
                        _answers.clear();
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _customerIdController,
                    decoration: const InputDecoration(
                      labelText: 'Customer ID (opcional)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _channelController,
                    decoration: const InputDecoration(
                      labelText: 'Canal',
                      hintText: 'whatsapp, sms, in-app, manual',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    selected.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  if ((selected.description ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(selected.description!),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  ...selected.questions.map(
                    (question) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _buildQuestionField(question),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: _submitting ? null : () => _submit(selected),
                    icon: _submitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _submitting ? 'A enviar...' : 'Enviar resposta',
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildQuestionField(EngageSurveyQuestion question) {
    final label = question.isRequired
        ? '${question.questionText} *'
        : question.questionText;

    switch (question.questionType) {
      case SurveyQuestionType.yesNo:
        final value = _answers[question.id] as bool?;
        return DropdownButtonFormField<bool>(
          value: value,
          decoration: InputDecoration(labelText: label),
          items: const [
            DropdownMenuItem(value: true, child: Text('Sim')),
            DropdownMenuItem(value: false, child: Text('Nao')),
          ],
          onChanged: (selected) =>
              setState(() => _answers[question.id] = selected),
        );
      case SurveyQuestionType.rating:
        final value = _answers[question.id] as double?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Slider(
              value: value ?? 3,
              min: 1,
              max: 5,
              divisions: 4,
              label: '${(value ?? 3).toStringAsFixed(0)}',
              onChanged: (selected) =>
                  setState(() => _answers[question.id] = selected),
            ),
          ],
        );
      case SurveyQuestionType.multipleChoice:
        final value = _answers[question.id] as String?;
        return DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(labelText: label),
          items: question.options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: (selected) =>
              setState(() => _answers[question.id] = selected),
        );
      default:
        return TextFormField(
          initialValue: (_answers[question.id] as String?) ?? '',
          decoration: InputDecoration(labelText: label),
          onChanged: (value) => _answers[question.id] = value,
        );
    }
  }

  Future<void> _submit(EngageSurvey survey) async {
    for (final question in survey.questions) {
      if (!question.isRequired) continue;
      final value = _answers[question.id];
      final emptyString = value is String && value.trim().isEmpty;
      if (value == null || emptyString) {
        AppFeedback.showMessage(
          context,
          message: 'Preencha as perguntas obrigatorias.',
        );
        return;
      }
    }

    final answers = survey.questions
        .where((question) => _answers.containsKey(question.id))
        .map((question) {
          final value = _answers[question.id];
          if (value is bool) {
            return SurveyAnswerInput(
              questionId: question.id,
              answerBool: value,
            );
          }
          if (value is num) {
            return SurveyAnswerInput(
              questionId: question.id,
              answerNumeric: value.toDouble(),
            );
          }
          return SurveyAnswerInput(
            questionId: question.id,
            answerText: value?.toString(),
          );
        })
        .toList();

    setState(() => _submitting = true);
    try {
      await ref
          .read(engageRepositoryProvider)
          .submitSurveyResponse(
            SurveySubmissionInput(
              surveyId: survey.id,
              customerId: _customerIdController.text.trim().isEmpty
                  ? null
                  : _customerIdController.text.trim(),
              channel: _channelController.text.trim().isEmpty
                  ? 'manual'
                  : _channelController.text.trim(),
              answers: answers,
            ),
          );
      await ref.read(engageSurveyAnalyticsProvider.notifier).refresh();
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: 'Resposta enviada com sucesso',
      );
      _answers.clear();
      setState(() {});
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
