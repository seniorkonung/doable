import '../../application/long_term_relation_projection.dart';

/// Состояние подробного просмотра одной долговременной связи.
///
/// Чтение, подтверждённое отсутствие и каждая безопасная категория отказа
/// остаются отдельными вариантами, поэтому ошибка не изображается пустым
/// результатом, а отсутствие — временным сбоем.
sealed class RelationDetailsState {
  const RelationDetailsState();

  /// Доступен ли пользователю обычный повтор чтения.
  bool get canRetry => false;
}

/// Первое чтение подробных данных ещё не завершилось.
final class RelationDetailsLoading extends RelationDetailsState {
  const RelationDetailsLoading();
}

/// Подтверждённые подробные данные связи на одной ревизии графа.
final class RelationDetailsLoaded extends RelationDetailsState {
  const RelationDetailsLoaded(this.details);

  final LongTermRelationDetails details;
}

/// Чтение подтвердило, что связи больше нет.
final class RelationDetailsNotFound extends RelationDetailsState {
  const RelationDetailsNotFound();
}

/// Временная недоступность хранилища: повтор уместен.
final class RelationDetailsUnavailable extends RelationDetailsState {
  const RelationDetailsUnavailable();

  @override
  bool get canRetry => true;
}

/// Сохранённые данные связи повреждены; повтор не восстановит их.
final class RelationDetailsCorruption extends RelationDetailsState {
  const RelationDetailsCorruption();
}

/// Безопасный исход неизвестного отказа чтения.
final class RelationDetailsUnexpected extends RelationDetailsState {
  const RelationDetailsUnexpected();
}
