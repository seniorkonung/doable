import '../../intention/domain/intention_id.dart';
import 'confirmed_choice_path.dart';

enum ChoicePathDraftDirection { topDown, bottomUp }

/// Черновик хранит шаги в порядке обхода. Начало обхода является основанием
/// только для верхнего направления; снизу это фиксированное действие.
sealed class ChoicePathDraft {
  const ChoicePathDraft(this.startingIntentionId);

  final IntentionId startingIntentionId;

  ChoicePathDraftDirection get direction => switch (this) {
    ChoicePathDraftStart() ||
    ChoicePathDraftProgress() => ChoicePathDraftDirection.topDown,
    ChoicePathDraftBottomStart() ||
    ChoicePathDraftBottomProgress() => ChoicePathDraftDirection.bottomUp,
  };

  List<ConfirmedChoicePathStep> get steps;

  IntentionId get currentIntentionId;

  /// Приводит показанные переходы к направлению от основания к действию.
  List<T> pathOrder<T>(Iterable<T> traversalSteps) {
    final ordered = List<T>.of(traversalSteps);
    if (ordered.length != steps.length) {
      throw ArgumentError.value(traversalSteps, 'traversalSteps');
    }
    return List<T>.unmodifiable(
      direction == ChoicePathDraftDirection.bottomUp
          ? ordered.reversed
          : ordered,
    );
  }
}

/// Верхний обход начинается с исходного намерения дневного выбора.
final class ChoicePathDraftStart extends ChoicePathDraft {
  const ChoicePathDraftStart(this.sourceIntentionId) : super(sourceIntentionId);

  final IntentionId sourceIntentionId;

  @override
  List<ConfirmedChoicePathStep> get steps => const [];

  @override
  IntentionId get currentIntentionId => sourceIntentionId;
}

/// Пройденный верхний префикс имеет хотя бы один переход.
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
    this.sourceIntentionId,
    this.steps,
    this.currentIntentionId,
  ) : super(sourceIntentionId);

  final IntentionId sourceIntentionId;

  @override
  final List<ConfirmedChoicePathStep> steps;

  @override
  final IntentionId currentIntentionId;

  /// Подтверждение создаётся только из непустого черновика; сохранение заново
  /// проверяет готовность конца и смысл каждой связи на актуальном графе.
  ConfirmedChoicePath get confirmedPath => ConfirmedChoicePath(steps);
}

/// Нижний обход начинается с фиксированного выбранного действия.
final class ChoicePathDraftBottomStart extends ChoicePathDraft {
  const ChoicePathDraftBottomStart(this.selectedActionId)
    : super(selectedActionId);

  final IntentionId selectedActionId;

  @override
  List<ConfirmedChoicePathStep> get steps => const [];

  @override
  IntentionId get currentIntentionId => selectedActionId;
}

/// Нижний черновик хранит входящие связи в порядке их выбора.
final class ChoicePathDraftBottomProgress extends ChoicePathDraft {
  factory ChoicePathDraftBottomProgress(
    IntentionId selectedActionId,
    Iterable<ConfirmedChoicePathStep> steps,
  ) {
    final ordered = List<ConfirmedChoicePathStep>.unmodifiable(steps);
    if (ordered.isEmpty) {
      throw ArgumentError.value(steps, 'steps');
    }
    final visited = <IntentionId>{selectedActionId};
    var current = selectedActionId;
    for (final step in ordered) {
      if (step.relatedIntentionId != current ||
          !visited.add(step.sourceIntentionId)) {
        throw ArgumentError.value(steps, 'steps');
      }
      current = step.sourceIntentionId;
    }
    return ChoicePathDraftBottomProgress._(selectedActionId, ordered, current);
  }

  const ChoicePathDraftBottomProgress._(
    this.selectedActionId,
    this.steps,
    this.currentIntentionId,
  ) : super(selectedActionId);

  final IntentionId selectedActionId;

  @override
  final List<ConfirmedChoicePathStep> steps;

  @override
  final IntentionId currentIntentionId;

  /// Непустой путь направлен от достигнутого основания к действию.
  ConfirmedChoicePath get confirmedPath =>
      ConfirmedChoicePath(pathOrder(steps));
}
