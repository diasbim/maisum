import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../design_system/components/maisum_app_bar.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/widgets/customer_picker_field.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/presentation/feature_upsell_screen.dart';
import '../domain/engage_labels.dart';
import '../domain/engage_models.dart';
import '../providers/engage_providers.dart';

class SurveyResponseScreen extends ConsumerStatefulWidget {
  const SurveyResponseScreen({super.key});

  @override
  ConsumerState<SurveyResponseScreen> createState() =>
      _SurveyResponseScreenState();
}

class _SurveyResponseScreenState extends ConsumerState<SurveyResponseScreen> {
  Customer? _customer;
  String _channel = SurveyChannel.manual;
  String? _selectedSurveyId;
  bool _submitting = false;
  final Map<String, dynamic> _answers = <String, dynamic>{};

  /// Bumped after every send. The answer fields keep their text in their own
  /// element state, so clearing [_answers] alone left the previous customer's
  /// words on screen — and sent them again for the next one.
  int _formGeneration = 0;

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(engageAccessProvider);
    final surveysAsync = ref.watch(engageSurveysProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: const MaisUmAppBar(
        title: 'Registar resposta',
        fallbackLocation: '/engage',
      ),
      body: accessAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (_, __) => const EmptyState(
          title: 'Não foi possível validar o acesso',
          subtitle: 'Tente novamente em alguns segundos.',
        ),
        data: (access) {
          if (!access.canManageSurveys) {
            return EmptyState(
              title: 'Envio de questionários indisponível',
              subtitle: 'Funcionalidade exclusiva do plano Business.',
              actionLabel: 'Ver opções',
              onAction: () => context.push(
                featureUpsellLocation(
                  featureKey: FeatureKeys.engageManageSurveys,
                  featureName: 'Registar resposta',
                  reason: 'plan_restricted',
                ),
              ),
            );
          }

          return surveysAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
            error: (_, __) => const EmptyState(
              title: 'Não foi possível carregar os questionários',
              subtitle: 'Atualize e tente novamente.',
            ),
            data: (surveys) {
              if (surveys.isEmpty) {
                return const EmptyState(
                  title: 'Nenhum questionário ativo',
                  subtitle: 'Crie um questionário antes de enviar respostas.',
                );
              }

              final selected = surveys.firstWhere(
                (survey) =>
                    survey.id == (_selectedSurveyId ?? surveys.first.id),
                orElse: () => surveys.first,
              );

              _selectedSurveyId ??= selected.id;

              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSurveyId,
                    decoration:
                        const InputDecoration(labelText: 'Questionário'),
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
                  CustomerPickerField(
                    label: 'Cliente (opcional)',
                    selected: _customer,
                    optional: true,
                    hintText: 'Resposta anónima',
                    helperText: 'Ligar a resposta a um cliente permite '
                        'recuperá-lo depois. Sem cliente, a resposta conta '
                        'apenas para as médias.',
                    onChanged: (customer) =>
                        setState(() => _customer = customer),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _channel,
                    decoration: const InputDecoration(
                      labelText: 'Como recebeu a resposta?',
                    ),
                    items: SurveyChannel.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(EngageLabels.surveyChannel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _channel = value);
                    },
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
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: const [
            DropdownMenuItem(value: true, child: Text('Sim')),
            DropdownMenuItem(value: false, child: Text('Não')),
          ],
          onChanged: (selected) =>
              setState(() => _answers[question.id] = selected),
        );
      case SurveyQuestionType.rating:
        // A slider showed "3" before anyone touched it, so a required rating
        // looked answered and then refused to submit. Five buttons have an
        // honest empty state and are far easier to hit on a phone.
        final value = (_answers[question.id] as num?)?.toInt();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var score = 1; score <= 5; score++)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _RatingOption(
                      score: score,
                      selected: value == score,
                      onTap: () => setState(
                        () => _answers[question.id] = score.toDouble(),
                      ),
                    ),
                  ),
              ],
            ),
            if (value == null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '1 é muito mau, 5 é muito bom.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        );
      case SurveyQuestionType.multipleChoice:
        final value = _answers[question.id] as String?;
        return DropdownButtonFormField<String>(
          initialValue: value,
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
          // Keyed on the send generation so a new response starts empty.
          key: ValueKey('${question.id}-$_formGeneration'),
          initialValue: (_answers[question.id] as String?) ?? '',
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(labelText: label),
          onChanged: (value) => _answers[question.id] = value,
        );
    }
  }

  Future<void> _submit(EngageSurvey survey) async {
    if (_submitting) return;

    for (var i = 0; i < survey.questions.length; i++) {
      final question = survey.questions[i];
      if (!question.isRequired) continue;
      final value = _answers[question.id];
      final emptyString = value is String && value.trim().isEmpty;
      if (value == null || emptyString) {
        // Name the question: "preencha as obrigatórias" leaves the merchant
        // hunting through a five-question form for the one they missed.
        AppFeedback.showMessage(
          context,
          message: 'Falta responder à pergunta ${i + 1}, que é obrigatória.',
          isError: true,
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
    }).toList();

    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(engageRepositoryProvider)
          .submitSurveyResponseWithResult(
            SurveySubmissionInput(
              surveyId: survey.id,
              customerId: _customer?.id,
              channel: _channel,
              answers: answers,
            ),
          );

      try {
        await ref.read(engageSurveyAnalyticsProvider.notifier).refresh();
      } catch (_) {
        // The submission result is still valid if the summary cannot refresh.
      }
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: result.isQueued
            ? 'Resposta guardada para sincronizar'
            : 'Resposta registada',
        subtitle: 'O formulário está pronto para o próximo cliente.',
      );
      setState(() {
        _answers.clear();
        _customer = null;
        _formGeneration++;
      });
    } catch (_) {
      if (!mounted) return;
      AppFeedback.showRetryableError(
        context,
        message:
            'Não foi possível guardar a resposta. Os dados continuam preenchidos.',
        onRetry: () => _submit(survey),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

/// One point on the 1–5 scale. A real 48pt target, and selection is carried by
/// the fill, the border and the check — never by colour alone.
class _RatingOption extends StatelessWidget {
  const _RatingOption({
    required this.score,
    required this.selected,
    required this.onTap,
  });

  final int score;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Nota $score de 5',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: AppControlSize.iconButton,
          height: AppControlSize.iconButton,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.secondaryLight : AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.secondaryDark : AppColors.g300,
              width: selected ? 2 : 1.2,
            ),
          ),
          child: Text(
            '$score',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: selected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}
