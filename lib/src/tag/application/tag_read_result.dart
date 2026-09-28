import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_id.dart';
import '../domain/tag_target.dart';
import 'tag_assignment_status.dart';
import 'tag_assignments_page.dart';
import 'tag_catalog.dart';
import 'tagged_entities_page.dart';

sealed class TagReadFailure implements GraphCommandFailure {
  const TagReadFailure();
}

final class TagReadUnavailableFailure extends TagReadFailure {
  const TagReadUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TagReadCorruptionFailure extends TagReadFailure {
  const TagReadCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TagReadUnexpectedFailure extends TagReadFailure {
  const TagReadUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

/// null в успешном снимке означает, что тег с этим id отсутствует.
/// Отказ чтения передаётся отдельно и не подменяется отсутствием.
typedef TagReadResult = GraphResult<GraphSnapshot<Tag?>, TagReadFailure>;
typedef TagReadSuccess =
    GraphResultSuccess<GraphSnapshot<Tag?>, TagReadFailure>;
typedef TagReadError = GraphResultFailure<GraphSnapshot<Tag?>, TagReadFailure>;

/// Контракт чтений единого репозитория личного графа для потребителей тегов.
/// Реализация и проверка продолжения принадлежат адаптеру графа.
abstract interface class TagReadContract {
  /// Возвращает обычный каталог либо выбор для типизированного получателя.
  /// Строки выбора несут подтверждённый признак назначения; оба режима идут
  /// в порядке создания тегов, включая теги без назначений. Продолжение
  /// принадлежит режиму и получателю. Отсутствующий получатель — отдельный
  /// отказ даже при пустом каталоге.
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query);

  /// Возвращает порцию тегов одного существующего получателя в порядке
  /// создания тегов. Пустой успех отличается от отсутствия получателя;
  /// продолжение принадлежит получателю и подтверждённому снимку.
  Future<TagAssignmentsPageResult> getTagAssignmentsPage(
    TagAssignmentsQuery query,
  );

  /// Проверяет одну пару на согласованном снимке. Отсутствие каждого участника
  /// и отказ чтения различны; остальные назначения не загружаются.
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    TagTarget target,
  );

  /// Возвращает одну порцию непосредственно помеченных сущностей выбранного
  /// тега в порядке создания назначений. Охват определяется собственным
  /// архивным состоянием получателя до разбиения на порции. Пустой успех
  /// отличается от отсутствия тега; продолжение принадлежит этому тегу,
  /// охвату, размеру порции и подтверждённому снимку.
  Future<TaggedEntitiesPageResult> getTaggedEntitiesPage(
    TaggedEntitiesQuery query,
  );

  /// Наблюдает один тег без загрузки назначений; каждый успех несёт ревизию.
  Stream<TagReadResult> watchTag(TagId id);
}
