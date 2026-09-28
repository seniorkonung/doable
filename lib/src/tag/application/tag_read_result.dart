import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_id.dart';
import '../domain/tag_target.dart';
import 'tag_assignment_status.dart';
import 'tag_assignments.dart';
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
/// Согласованное чтение и проверка данных принадлежат адаптеру графа.
abstract interface class TagReadContract {
  /// Полный каталог на одной ревизии, в порядке создания тегов.
  /// Режим выбора содержит подтверждённые признаки назначения получателю.
  /// Отсутствующий получатель — отдельный отказ даже при пустом каталоге.
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode);

  /// Все теги существующего получателя на одной ревизии, в порядке создания.
  /// Пустой успех отличается от отсутствия получателя.
  Future<TagAssignmentsResult> getTagAssignments(TagTarget target);

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
