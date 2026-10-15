import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/calendar_date.dart';

enum DailyChoiceDayStatusQueryValidationFailure { reversedRange, rangeTooLong }

final class DailyChoiceDayStatusQueryValidationException implements Exception {
  const DailyChoiceDayStatusQueryValidationException(this.failure);

  final DailyChoiceDayStatusQueryValidationFailure failure;
}

/// Включительный диапазон чтения не длиннее 15 недель.
final class DailyChoiceDayStatusQuery {
  factory DailyChoiceDayStatusQuery({
    required CalendarDate firstDate,
    required CalendarDate lastDate,
  }) {
    final first = DateTime.utc(firstDate.year, firstDate.month, firstDate.day);
    final last = DateTime.utc(lastDate.year, lastDate.month, lastDate.day);
    final dayCount = last.difference(first).inDays + 1;
    if (dayCount < 1) {
      throw const DailyChoiceDayStatusQueryValidationException(
        DailyChoiceDayStatusQueryValidationFailure.reversedRange,
      );
    }
    if (dayCount > maxDays) {
      throw const DailyChoiceDayStatusQueryValidationException(
        DailyChoiceDayStatusQueryValidationFailure.rangeTooLong,
      );
    }
    return DailyChoiceDayStatusQuery._(firstDate, lastDate);
  }

  const DailyChoiceDayStatusQuery._(this.firstDate, this.lastDate);

  static const maxDays = 15 * 7;

  final CalendarDate firstDate;
  final CalendarDate lastDate;
}

enum DailyChoiceDayStatus { allCompleted, hasIncomplete }

/// Состояния только дней с выборами в диапазоне [query]. Отсутствие даты в
/// [statuses] означает отсутствие выборов, а не отказ чтения.
/// Адаптер передаёт проверенные даты и состояния и не включает даты вне
/// диапазона. Карта копируется и не допускает изменений после создания.
final class DailyChoiceDayStatuses {
  DailyChoiceDayStatuses({
    required this.query,
    required Map<CalendarDate, DailyChoiceDayStatus> statuses,
  }) : statuses = Map.unmodifiable(statuses);

  final DailyChoiceDayStatusQuery query;
  final Map<CalendarDate, DailyChoiceDayStatus> statuses;
}

/// Единый отказ целого чтения без частичных состояний.
final class DailyChoiceDayStatusesReadFailure implements GraphCommandFailure {
  const DailyChoiceDayStatusesReadFailure();

  /// Общая категория нужна для совместимости с [GraphResult]. Причину отказа
  /// хранилища адаптер классифицирует только для диагностики.
  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

/// Все сохранённые выборы каждой даты учитываются независимо от фильтра
/// выполнения и архивного состояния участников и связей пути.
/// Состояния и ревизия относятся к одному подтверждённому снимку графа.
/// Недопустимая сохранённая дата или значение выполнения дают отказ всего
/// чтения вместо частичного результата или ложного отсутствия выборов.
/// Агрегирование и SQL остаются внутри адаптера; пути выборов не читаются
/// и не проверяются этим чтением.
typedef DailyChoiceDayStatusesReadResult =
    GraphResult<
      GraphSnapshot<DailyChoiceDayStatuses>,
      DailyChoiceDayStatusesReadFailure
    >;
typedef DailyChoiceDayStatusesReadSuccess =
    GraphResultSuccess<
      GraphSnapshot<DailyChoiceDayStatuses>,
      DailyChoiceDayStatusesReadFailure
    >;
typedef DailyChoiceDayStatusesReadError =
    GraphResultFailure<
      GraphSnapshot<DailyChoiceDayStatuses>,
      DailyChoiceDayStatusesReadFailure
    >;
