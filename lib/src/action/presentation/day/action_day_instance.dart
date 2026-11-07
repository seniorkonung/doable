import '../../../shared/domain/calendar_date.dart';

/// Страница создаёт и удерживает ключ до закрытия. Равенство по идентичности
/// разделяет состояния двух экранов дня даже с одинаковой начальной датой.
final class ActionDayInstance {
  ActionDayInstance({required this.initialDate});

  final CalendarDate initialDate;
}
