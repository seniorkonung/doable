import '../../../tag/domain/tag.dart';
import '../../../tag/domain/tag_id.dart';

/// Принимает ли сессия создания изменения своего черновика.
enum IntentionDraftAvailability {
  editable,

  /// Принятая отправка выполняется: черновик зафиксирован до её результата.
  submitting,

  /// Сессия завершена успешным созданием, закрытием по запросу или
  /// освобождена.
  closed,
}

/// Опубликованное состояние набора тегов черновика для общего выбора тегов.
final class IntentionDraftTagSetSnapshot {
  const IntentionDraftTagSetSnapshot({
    required this.tagIds,
    required this.availability,
  });

  /// Неизменяемый набор идентификаторов в порядке добавления.
  final Set<TagId> tagIds;
  final IntentionDraftAvailability availability;
}

enum IntentionDraftTagAddition {
  added,

  /// Тег уже входит в набор; черновик не изменился.
  alreadyIncluded,

  /// Выполняется принятая отправка; черновик не изменился.
  submitting,

  /// Сессия закрыта; черновик не изменился.
  sessionClosed,
}

/// Узкий контракт набора тегов черновика для общего выбора тегов.
///
/// Связан с одной сессией создания: предоставляет только наблюдаемый набор
/// идентификаторов и явное локальное добавление. Добавление меняет только
/// черновик и не записывает назначений; команды графа, ревизии и детали
/// хранилища в контракт не входят. Во время отправки и после закрытия сессии
/// контракт отвергает изменения.
abstract interface class IntentionDraftTagSet {
  IntentionDraftTagSetSnapshot get current;

  /// Изменения набора или его доступности. Поток завершается после
  /// публикации закрытого состояния сессии.
  Stream<IntentionDraftTagSetSnapshot> get changes;

  /// Явно добавляет подтверждённый [tag]; его название сохраняется как
  /// последнее известное для показа. Повторное добавление ничего не меняет.
  IntentionDraftTagAddition add(Tag tag);
}
