import '../../../long_term_relation/domain/long_term_relation_id.dart';
import '../../domain/intention_id.dart';

/// Элемент, над которым выполняется каскадная операция (D7, ADR-0057).
sealed class CascadeSubject {
  const CascadeSubject();
}

final class IntentionCascadeSubject extends CascadeSubject {
  const IntentionCascadeSubject(this.intentionId);

  final IntentionId intentionId;
}

final class RelationCascadeSubject extends CascadeSubject {
  const RelationCascadeSubject(this.relationId);

  final LongTermRelationId relationId;
}

enum CascadeOperation { archive, delete, restore }

/// Вариант каскада, который выбирает человек: «со вспомогательными»
/// выполняет каскад, «только это» — операцию над одним элементом.
enum CascadeChoice { withSupporting, onlyThis }

/// Состав одного варианта каскадной операции: всё, что нужно и вопросу с
/// подтверждением, и сообщению об исходе.
///
/// Списки намерений не содержат намерение-предмет и идут в порядке показа:
/// обходом в глубину от предмета по порядку связей. Исполнение сравнивает их
/// как множества: порядок и числа связей производны и в сравнение не входят.
sealed class CascadeComposition {
  const CascadeComposition();
}

final class ArchiveCascadeComposition extends CascadeComposition {
  ArchiveCascadeComposition({
    required List<IntentionId> departing,
    required List<IntentionId> promoted,
    required List<IntentionId> mainsLosingRelation,
    required this.archivedRelationCount,
  }) : departing = List.unmodifiable(departing),
       promoted = List.unmodifiable(promoted),
       mainsLosingRelation = List.unmodifiable(mainsLosingRelation);

  /// Вспомогательные намерения, которые уходят в архив вместе с предметом.
  final List<IntentionId> departing;

  /// Вспомогательные намерения непосредственно ниже предмета, которые при
  /// «только это» становятся главными.
  final List<IntentionId> promoted;

  /// Главные намерения на другом конце архивируемых связей, которые сами
  /// остаются.
  final List<IntentionId> mainsLosingRelation;

  /// Все связи, которые операция архивирует, включая связь-предмет.
  final int archivedRelationCount;
}

final class DeleteCascadeComposition extends CascadeComposition {
  DeleteCascadeComposition({
    required List<IntentionId> departing,
    required List<IntentionId> promoted,
    required List<IntentionId> archivedByInvariant,
    required List<IntentionId> mainsLosingRelation,
    required this.deletedRelationCount,
    required this.archivedRelationCount,
  }) : departing = List.unmodifiable(departing),
       promoted = List.unmodifiable(promoted),
       archivedByInvariant = List.unmodifiable(archivedByInvariant),
       mainsLosingRelation = List.unmodifiable(mainsLosingRelation);

  /// Вспомогательные намерения, которые удаляются вместе с предметом.
  final List<IntentionId> departing;

  /// Вспомогательные намерения непосредственно ниже предмета, которые при
  /// «только это» становятся главными.
  final List<IntentionId> promoted;

  /// Активные вспомогательные намерения, оставшиеся без активной входящей
  /// связи, и всё, что архивируется ниже них.
  final List<IntentionId> archivedByInvariant;

  /// Главные намерения на другом конце удаляемых связей, которые сами не
  /// удаляются.
  final List<IntentionId> mainsLosingRelation;

  /// Все связи, которые операция удаляет, включая связь-предмет.
  final int deletedRelationCount;

  /// Связи, которые архивируются вместе с [archivedByInvariant].
  final int archivedRelationCount;
}

final class RestoreCascadeComposition extends CascadeComposition {
  RestoreCascadeComposition({
    required List<IntentionId> restored,
    required this.returnedAsMain,
    required this.restoredRelationCount,
  }) : restored = List.unmodifiable(restored);

  /// Возвращаемые намерения: архивные участники связи-предмета и
  /// вспомогательные намерения, которые возвращает каскад.
  final List<IntentionId> restored;

  /// Намерение, которое возвращается главным, потому что после
  /// восстановления над ним нет активного намерения: само намерение-предмет
  /// или исходный участник связи-предмета.
  final IntentionId? returnedAsMain;

  /// Все связи, которые операция возвращает, включая связь-предмет.
  final int restoredRelationCount;
}

/// Составы обоих вариантов одной операции на одной ревизии графа.
final class CascadePlan<C extends CascadeComposition> {
  const CascadePlan({
    required this.withSupporting,
    required this.onlyThis,
    required this.asksQuestion,
  });

  final C withSupporting;
  final C onlyThis;

  /// Каскад затронул бы другие намерения, поэтому человек выбирает вариант.
  /// Без вопроса оба варианта совпадают.
  final bool asksQuestion;
}

/// Выбранный вариант и его состав, который команда сверяет с составом,
/// вычисленным заново в своей транзакции. Для операции без вопроса это
/// состав, вычисленный при её запуске.
final class CascadeExecution<C extends CascadeComposition> {
  const CascadeExecution({required this.choice, required this.expected});

  final CascadeChoice choice;
  final C expected;
}
