import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../shared/domain/calendar_date.dart';

enum ActionDayStatusQueryValidationFailure { reversedRange, rangeTooLong }

final class ActionDayStatusQueryValidationException implements Exception {
  const ActionDayStatusQueryValidationException(this.failure);

  final ActionDayStatusQueryValidationFailure failure;
}

/// Включительное окно календаря не длиннее 15 недель.
final class ActionDayStatusQuery {
  factory ActionDayStatusQuery({
    required CalendarDate firstDate,
    required CalendarDate lastDate,
  }) {
    final first = DateTime.utc(firstDate.year, firstDate.month, firstDate.day);
    final last = DateTime.utc(lastDate.year, lastDate.month, lastDate.day);
    final dayCount = last.difference(first).inDays + 1;
    if (dayCount < 1) {
      throw const ActionDayStatusQueryValidationException(
        ActionDayStatusQueryValidationFailure.reversedRange,
      );
    }
    if (dayCount > maxDays) {
      throw const ActionDayStatusQueryValidationException(
        ActionDayStatusQueryValidationFailure.rangeTooLong,
      );
    }
    return ActionDayStatusQuery._(firstDate, lastDate);
  }

  const ActionDayStatusQuery._(this.firstDate, this.lastDate);

  static const maxDays = 15 * 7;

  final CalendarDate firstDate;
  final CalendarDate lastDate;
}

enum ActionDayStatus { allCompleted, hasIncomplete }

/// Состояния только дней с действиями в окне [query]. Отсутствие даты в
/// [statuses] означает отсутствие действий, а не отказ чтения. Адаптер
/// передаёт проверенные даты и состояния и не включает даты вне окна. Карта
/// копируется и не допускает изменений после создания.
final class ActionDayStatuses {
  ActionDayStatuses({
    required this.query,
    required Map<CalendarDate, ActionDayStatus> statuses,
  }) : statuses = Map.unmodifiable(statuses);

  final ActionDayStatusQuery query;
  final Map<CalendarDate, ActionDayStatus> statuses;
}

/// Отказ целого чтения без частичных состояний.
sealed class ActionDayStatusesReadFailure implements GraphCommandFailure {
  const ActionDayStatusesReadFailure();
}

final class ActionDayStatusesUnavailableFailure
    extends ActionDayStatusesReadFailure {
  const ActionDayStatusesUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class ActionDayStatusesCorruptionFailure
    extends ActionDayStatusesReadFailure {
  const ActionDayStatusesCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class ActionDayStatusesUnexpectedFailure
    extends ActionDayStatusesReadFailure {
  const ActionDayStatusesUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

/// Состояние каждой даты определяют все сохранённые действия этой даты
/// независимо от секций выдачи дня и от архивного или удалённого состояния
/// звеньев их путей. Состояния и ревизия относятся к одному подтверждённому
/// снимку графа. Недопустимая сохранённая дата или значение выполнения дают
/// отказ всего чтения вместо частичного результата или ложного отсутствия
/// действий. Агрегирование и SQL остаются внутри адаптера; пути действий этим
/// чтением не читаются.
typedef ActionDayStatusesReadResult =
    GraphResult<GraphSnapshot<ActionDayStatuses>, ActionDayStatusesReadFailure>;
typedef ActionDayStatusesReadSuccess =
    GraphResultSuccess<
      GraphSnapshot<ActionDayStatuses>,
      ActionDayStatusesReadFailure
    >;
typedef ActionDayStatusesReadError =
    GraphResultFailure<
      GraphSnapshot<ActionDayStatuses>,
      ActionDayStatusesReadFailure
    >;
