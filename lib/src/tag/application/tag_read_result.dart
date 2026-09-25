import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_id.dart';
import 'tag_catalog.dart';

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
  /// Возвращает обычный каталог, включая теги без назначений, в порядке
  /// создания. Пустая первая страница без продолжения — пустой каталог.
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query);

  /// Наблюдает один тег без загрузки назначений; каждый успех несёт ревизию.
  Stream<TagReadResult> watchTag(TagId id);
}
