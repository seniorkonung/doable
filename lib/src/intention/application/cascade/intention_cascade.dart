import '../../../graph/application/graph_revision.dart';
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
    required this.archivedRelationCount,
  }) : departing = List.unmodifiable(departing),
       promoted = List.unmodifiable(promoted);

  /// Вспомогательные намерения, которые уходят в архив вместе с предметом.
  final List<IntentionId> departing;

  /// Вспомогательные намерения непосредственно ниже предмета, которые при
  /// «только это» становятся главными.
  final List<IntentionId> promoted;

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
  const CascadeExecution._({required this.choice, required this.expected});

  factory CascadeExecution.of(CascadePlan<C> plan, CascadeChoice choice) =>
      CascadeExecution._(
        choice: choice,
        expected: switch (choice) {
          CascadeChoice.withSupporting => plan.withSupporting,
          CascadeChoice.onlyThis => plan.onlyThis,
        },
      );

  /// Вариант «со вспомогательными» из составов [plan].
  CascadeExecution.withSupporting(CascadePlan<C> plan)
    : choice = CascadeChoice.withSupporting,
      expected = plan.withSupporting;

  final CascadeChoice choice;
  final C expected;
}

/// Исход подтверждённой каскадной операции: состав выбранного варианта,
/// который команда исполнила. Из него собирается сообщение об исходе
/// (ADR-0057).
final class CascadeOutcome<C extends CascadeComposition>
    implements GraphChange {
  const CascadeOutcome({required this.revision, required this.executed});

  @override
  final GraphRevision revision;
  final C executed;
}

/// Чтение предпросмотра каскада. Подмешивается в `PersonalGraphRepository`:
/// отдельного репозитория нет (ADR-0009).
abstract interface class IntentionCascadePreviewReadContract {
  /// Читает составы обоих вариантов [operation] над [subject], признак
  /// вопроса и названия намерений из списков составов на одной ревизии
  /// графа. Индекс удержания текущей ревизии строится вне очереди записи,
  /// если его нет (ADR-0056). Вид ответа соответствует [operation], а
  /// удаление намерения отличается от удаления связи.
  Future<CascadePreviewResult> previewCascade(
    CascadeSubject subject,
    CascadeOperation operation,
  );
}

sealed class CascadePreviewResult {
  const CascadePreviewResult();
}

/// Составы обоих вариантов операции и названия намерений на [revision].
sealed class CascadePreview<C extends CascadeComposition>
    extends CascadePreviewResult {
  CascadePreview({
    required this.revision,
    required this.plan,
    required Map<IntentionId, String> titles,
  }) : titles = Map.unmodifiable(titles);

  final GraphRevision revision;
  final CascadePlan<C> plan;

  /// Название каждого намерения из списков обоих составов [plan]. Порядок
  /// показа задают сами списки.
  final Map<IntentionId, String> titles;
}

final class ArchiveCascadePreview
    extends CascadePreview<ArchiveCascadeComposition> {
  ArchiveCascadePreview({
    required super.revision,
    required super.plan,
    required super.titles,
  });
}

final class RestoreCascadePreview
    extends CascadePreview<RestoreCascadeComposition> {
  RestoreCascadePreview({
    required super.revision,
    required super.plan,
    required super.titles,
  });
}

final class IntentionDeleteCascadePreview
    extends CascadePreview<DeleteCascadeComposition> {
  IntentionDeleteCascadePreview({
    required super.revision,
    required super.plan,
    required super.titles,
    required this.isInActionPath,
  });

  /// Намерение входит хотя бы в один сохранённый путь действия: по нему
  /// пояснение под «Удалить» без каскада выбирает между пометкой «Удалено»
  /// в путях и сохранением тегов.
  final bool isInActionPath;
}

final class RelationDeleteCascadePreview
    extends CascadePreview<DeleteCascadeComposition> {
  RelationDeleteCascadePreview({
    required super.revision,
    required super.plan,
    required super.titles,
  });
}

/// Предпросмотр не прочитан. Причина записана в диагностику.
sealed class CascadePreviewFailure extends CascadePreviewResult {
  const CascadePreviewFailure();
}

/// Предмета нет в хранилище на ревизии чтения.
final class CascadePreviewSubjectNotFound extends CascadePreviewFailure {
  const CascadePreviewSubjectNotFound();
}

/// Операция неприменима к состоянию предмета: архивирование архивного или
/// восстановление активного.
final class CascadePreviewOperationInapplicable extends CascadePreviewFailure {
  const CascadePreviewOperationInapplicable();
}

/// Подтверждённая команда изменила граф, пока предпросмотр читался:
/// удержание — во время построения индекса, что угодно — между частями
/// чтения названий. Предпросмотр читается заново.
final class CascadePreviewExpired extends CascadePreviewFailure {
  const CascadePreviewExpired();
}

/// Хранилище недоступно.
final class CascadePreviewUnavailable extends CascadePreviewFailure {
  const CascadePreviewUnavailable();
}

/// Сохранённые данные графа повреждены.
final class CascadePreviewCorruption extends CascadePreviewFailure {
  const CascadePreviewCorruption();
}

/// Непредвиденный отказ хранилища или подсчёта удержания.
final class CascadePreviewUnexpected extends CascadePreviewFailure {
  const CascadePreviewUnexpected();
}

/// Чтение предпросмотра при запуске операции.
extension CurrentCascadePreviewRead on IntentionCascadePreviewReadContract {
  /// Читает предпросмотр заново, пока он устаревает из-за подтверждённой
  /// команды: каждое устаревание означает новую ревизию графа, поэтому повтор
  /// конечен.
  Future<CascadePreviewResult> previewCurrentCascade(
    CascadeSubject subject,
    CascadeOperation operation,
  ) async {
    while (true) {
      final preview = await previewCascade(subject, operation);
      if (preview is! CascadePreviewExpired) {
        return preview;
      }
    }
  }
}
