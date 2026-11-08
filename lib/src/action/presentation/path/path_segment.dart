import '../../../intention/domain/intention.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../application/action_details.dart';
import '../../domain/action_path.dart';

/// Первый целый участок сохранённого пути: от первого актуального намерения до
/// первого разрыва. Актуальное намерение существует и активно, а соседние
/// намерения участка соединены активной связью. Без актуальных намерений —
/// `null`.
ActionPath? firstWholeSegment(ActionSavedPath path) {
  final intentions = [path.root, for (final step in path.steps) step.intention];
  final start = intentions.indexWhere(_isActual);
  if (start < 0) return null;
  final segment = [intentions[start].id];
  for (var index = start + 1; index < intentions.length; index++) {
    if (!_isActive(path.steps[index - 1].link) ||
        !_isActual(intentions[index])) {
      break;
    }
    segment.add(intentions[index].id);
  }
  return ActionPath(segment);
}

bool _isActual(ActionPathIntention intention) => switch (intention) {
  ExistingActionPathIntention(:final intention) =>
    intention.archiveState == IntentionArchiveState.active,
  DeletedActionPathIntention() => false,
};

bool _isActive(ActionPathLink link) => switch (link) {
  ExistingActionPathLink(:final relation) =>
    relation.scope == RelationScope.active,
  DeletedActionPathLink() => false,
};
