import '../../domain/calendar_date.dart';

/// Страница создаёт и удерживает ключ до закрытия. Равенство по идентичности
/// разделяет состояния двух каталогов даже с одинаковой начальной датой.
final class DailyChoiceCatalogInstance {
  DailyChoiceCatalogInstance({required this.initialDate});

  final CalendarDate initialDate;
}
