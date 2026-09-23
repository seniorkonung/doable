import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'calendar_date.dart';
import 'choice_path_step_id.dart';
import 'daily_choice_description.dart';
import 'daily_choice_id.dart';

final class DailyChoice {
  factory DailyChoice({
    required DailyChoiceId id,
    required IntentionId sourceIntentionId,
    required IntentionId selectedIntentionId,
    required CalendarDate date,
    required DailyChoiceDescription? description,
    required bool isCompleted,
  }) {
    if (sourceIntentionId == selectedIntentionId) {
      throw ArgumentError.value(selectedIntentionId, 'selectedIntentionId');
    }
    return DailyChoice._(
      id: id,
      sourceIntentionId: sourceIntentionId,
      selectedIntentionId: selectedIntentionId,
      date: date,
      description: description,
      isCompleted: isCompleted,
    );
  }

  const DailyChoice._({
    required this.id,
    required this.sourceIntentionId,
    required this.selectedIntentionId,
    required this.date,
    required this.description,
    required this.isCompleted,
  });

  final DailyChoiceId id;
  final IntentionId sourceIntentionId;
  final IntentionId selectedIntentionId;
  final CalendarDate date;
  final DailyChoiceDescription? description;
  final bool isCompleted;
}

final class ChoicePathStep {
  const ChoicePathStep({
    required this.id,
    required this.dailyChoiceId,
    required this.relationId,
    required this.previousStepId,
  });

  final ChoicePathStepId id;
  final DailyChoiceId dailyChoiceId;
  final LongTermRelationId relationId;
  final ChoicePathStepId? previousStepId;
}

/// Упорядоченные сохранённые ссылки. Проверка их смысла в текущем графе
/// выполняется в транзакции репозитория до создания этого значения.
final class StoredChoicePath {
  factory StoredChoicePath(Iterable<ChoicePathStep> steps) {
    final ordered = List<ChoicePathStep>.unmodifiable(steps);
    if (ordered.isEmpty) {
      throw ArgumentError.value(steps, 'steps');
    }
    final owner = ordered.first.dailyChoiceId;
    final ids = <ChoicePathStepId>{};
    ChoicePathStepId? previous;
    for (final step in ordered) {
      if (step.dailyChoiceId != owner ||
          step.previousStepId != previous ||
          !ids.add(step.id)) {
        throw ArgumentError.value(steps, 'steps');
      }
      previous = step.id;
    }
    return StoredChoicePath._(ordered);
  }

  const StoredChoicePath._(this.steps);

  final List<ChoicePathStep> steps;
}
