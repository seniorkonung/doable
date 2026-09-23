import '../../intention/domain/intention_id.dart';
import 'confirmed_choice_path.dart';

/// Текущий префикс обхода сверху вниз. Проверка его актуальности принадлежит
/// репозиторию; черновик гарантирует только непрерывность и простоту формы.
sealed class ChoicePathDraft {
  const ChoicePathDraft(this.sourceIntentionId);

  final IntentionId sourceIntentionId;

  List<ConfirmedChoicePathStep> get steps;

  IntentionId get currentIntentionId;
}

/// Начало обхода допускает ноль переходов, но не даёт подтверждённого пути.
final class ChoicePathDraftStart extends ChoicePathDraft {
  const ChoicePathDraftStart(super.sourceIntentionId);

  @override
  List<ConfirmedChoicePathStep> get steps => const [];

  @override
  IntentionId get currentIntentionId => sourceIntentionId;
}

/// Пройденный префикс имеет хотя бы один переход.
final class ChoicePathDraftProgress extends ChoicePathDraft {
  factory ChoicePathDraftProgress(
    IntentionId sourceIntentionId,
    Iterable<ConfirmedChoicePathStep> steps,
  ) {
    final ordered = List<ConfirmedChoicePathStep>.unmodifiable(steps);
    if (ordered.isEmpty) {
      throw ArgumentError.value(steps, 'steps');
    }
    final visited = <IntentionId>{sourceIntentionId};
    var current = sourceIntentionId;
    for (final step in ordered) {
      if (step.sourceIntentionId != current ||
          !visited.add(step.relatedIntentionId)) {
        throw ArgumentError.value(steps, 'steps');
      }
      current = step.relatedIntentionId;
    }
    return ChoicePathDraftProgress._(sourceIntentionId, ordered, current);
  }

  const ChoicePathDraftProgress._(
    super.sourceIntentionId,
    this.steps,
    this.currentIntentionId,
  );

  @override
  final List<ConfirmedChoicePathStep> steps;

  @override
  final IntentionId currentIntentionId;

  /// Подтверждение создаётся только из непустого черновика; сохранение заново
  /// проверяет готовность конца и смысл каждой связи на актуальном графе.
  ConfirmedChoicePath get confirmedPath => ConfirmedChoicePath(steps);
}
