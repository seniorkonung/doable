import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../shared/domain/calendar_date.dart';
import 'action_list_item.dart';

/// Секция выдачи дня по выполнению действий.
enum ActionDaySection { incomplete, completed }

/// Продолжение несёт ревизию и последний ключ порядка. Содержимое скрыто от
/// клиента.
abstract interface class ActionDayCursor {}

/// Одна порция секции выбранного дня. Размер порции ограничен
/// [minPageSize]–[maxPageSize]; иначе выбрасывается [RangeError].
final class ActionDayQuery {
  factory ActionDayQuery({
    required CalendarDate date,
    required ActionDaySection section,
    int pageSize = defaultPageSize,
    ActionDayCursor? cursor,
  }) {
    RangeError.checkValueInInterval(pageSize, minPageSize, maxPageSize);
    return ActionDayQuery._(date, section, pageSize, cursor);
  }

  const ActionDayQuery._(this.date, this.section, this.pageSize, this.cursor);

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  final CalendarDate date;
  final ActionDaySection section;
  final int pageSize;
  final ActionDayCursor? cursor;
}

/// Секция одной даты упорядочена по времени («Весь день» первым), приоритету
/// и порядку создания, по возрастанию. Строки и ревизия относятся к одному
/// подтверждённому снимку.
sealed class ActionDayPage {
  ActionDayPage({
    required List<ActionListItem> items,
    required this.nextCursor,
    required this.revision,
  }) : items = List.unmodifiable(items);

  final List<ActionListItem> items;
  final ActionDayCursor? nextCursor;
  final GraphRevision revision;
}

/// Числа обеих секций дня, признак времени во всём дне и строки первой
/// порции получены на одном снимке.
final class ActionDayFirstPage extends ActionDayPage {
  ActionDayFirstPage({
    required super.items,
    required this.incompleteCount,
    required this.completedCount,
    required this.hasTimedActions,
    required super.nextCursor,
    required super.revision,
  });

  final int incompleteCount;
  final int completedCount;

  /// Учитывает действия обеих секций, включая ещё не полученные порции.
  final bool hasTimedActions;
}

final class ActionDayContinuationPage extends ActionDayPage {
  ActionDayContinuationPage({
    required super.items,
    required super.nextCursor,
    required super.revision,
  });
}

sealed class ActionDayReadFailure implements GraphCommandFailure {
  const ActionDayReadFailure();
}

/// Ревизия продолжения больше не совпадает с текущим снимком.
final class ActionDaySnapshotExpired extends ActionDayReadFailure {
  const ActionDaySnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class ActionDayUnavailableFailure extends ActionDayReadFailure {
  const ActionDayUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class ActionDayCorruptionFailure extends ActionDayReadFailure {
  const ActionDayCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class ActionDayUnexpectedFailure extends ActionDayReadFailure {
  const ActionDayUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef ActionDayPageResult = GraphResult<ActionDayPage, ActionDayReadFailure>;
typedef ActionDayPageSuccess =
    GraphResultSuccess<ActionDayPage, ActionDayReadFailure>;
typedef ActionDayPageError =
    GraphResultFailure<ActionDayPage, ActionDayReadFailure>;
