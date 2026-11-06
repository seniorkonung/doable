import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../domain/action.dart';

/// Намерение сохранённого пути. Пока намерение существует, оно несёт текущие
/// данные; удалённое — название, которое было при удалении (ADR-0055).
sealed class ActionPathIntention {
  const ActionPathIntention();

  IntentionId get id;
  String get title;
}

final class ExistingActionPathIntention extends ActionPathIntention {
  const ExistingActionPathIntention(this.intention);

  /// Текущие данные, включая архивное состояние.
  final Intention intention;

  @override
  IntentionId get id => intention.id;

  @override
  String get title => intention.title;
}

final class DeletedActionPathIntention extends ActionPathIntention {
  const DeletedActionPathIntention({required this.id, required this.title});

  @override
  final IntentionId id;

  @override
  final String title;
}

/// Связь звена пути. Звено определяет пара соседних намерений в направлении
/// пути: если у пары снова есть связь, звено показывает её, а не удалённую.
sealed class ActionPathLink {
  const ActionPathLink();

  LongTermRelationType get type;
}

final class ExistingActionPathLink extends ActionPathLink {
  const ExistingActionPathLink(this.relation);

  /// Текущие данные связи пары, включая приоритет и архивное состояние.
  final LongTermRelation relation;

  @override
  LongTermRelationType get type => relation.type;
}

/// Удалённая связь пары. Приоритет удалённой связи не хранится.
final class DeletedActionPathLink extends ActionPathLink {
  const DeletedActionPathLink(this.type);

  /// Тип, который был у связи при удалении.
  @override
  final LongTermRelationType type;
}

/// Шаг пути после корневого: звено от предыдущего намерения и само намерение.
final class ActionPathStep {
  const ActionPathStep({required this.link, required this.intention});

  final ActionPathLink link;
  final ActionPathIntention intention;
}

/// Сохранённый путь действия от корневого намерения до конечного. Число
/// звеньев на одно меньше числа намерений по построению.
final class ActionSavedPath {
  ActionSavedPath({required this.root, required Iterable<ActionPathStep> steps})
    : steps = List.unmodifiable(steps);

  final ActionPathIntention root;
  final List<ActionPathStep> steps;

  int get intentionCount => steps.length + 1;
}

/// Действие для панели: его поля и сохранённый путь [path] на текущих данных
/// намерений и связей.
final class ActionDetails {
  const ActionDetails({required this.action, required this.path});

  final Action action;
  final ActionSavedPath path;
}

sealed class ActionReadFailure implements GraphCommandFailure {
  const ActionReadFailure();
}

final class ActionReadUnavailableFailure extends ActionReadFailure {
  const ActionReadUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class ActionReadCorruptionFailure extends ActionReadFailure {
  const ActionReadCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class ActionReadUnexpectedFailure extends ActionReadFailure {
  const ActionReadUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

/// Успех со значением `null` — действия нет.
typedef ActionReadResult =
    GraphResult<GraphSnapshot<ActionDetails?>, ActionReadFailure>;
typedef ActionReadSuccess =
    GraphResultSuccess<GraphSnapshot<ActionDetails?>, ActionReadFailure>;
typedef ActionReadError =
    GraphResultFailure<GraphSnapshot<ActionDetails?>, ActionReadFailure>;
