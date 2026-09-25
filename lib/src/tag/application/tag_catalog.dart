import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';

enum TagCatalogQueryValidationFailure { pageSizeOutOfRange }

final class TagCatalogQueryValidationException implements Exception {
  const TagCatalogQueryValidationException(this.failure);

  final TagCatalogQueryValidationFailure failure;
}

/// Непрозрачное продолжение относится к каталогу, размеру порции, экземпляру
/// репозитория, эпохе, ревизии и последнему внутреннему ключу порядка.
/// Оно не сериализуется и не служит идентификатором тега.
abstract interface class TagCatalogCursor {}

final class TagCatalogQuery {
  factory TagCatalogQuery({
    int pageSize = defaultPageSize,
    TagCatalogCursor? cursor,
  }) {
    if (pageSize < minPageSize || pageSize > maxPageSize) {
      throw const TagCatalogQueryValidationException(
        TagCatalogQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return TagCatalogQuery._(pageSize, cursor);
  }

  const TagCatalogQuery._(this.pageSize, this.cursor);

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  final int pageSize;
  final TagCatalogCursor? cursor;
}

final class TagCatalogPageValidationException implements Exception {
  const TagCatalogPageValidationException();
}

/// Теги идут в устойчивом порядке создания. Список и ревизия принадлежат
/// одному подтверждённому снимку; точное общее количество не вычисляется.
final class TagCatalogPage {
  factory TagCatalogPage({
    required List<Tag> items,
    required int pageSize,
    required TagCatalogCursor? nextCursor,
    required GraphRevision revision,
  }) {
    if (pageSize < TagCatalogQuery.minPageSize ||
        pageSize > TagCatalogQuery.maxPageSize ||
        items.length > pageSize ||
        (items.isEmpty && nextCursor != null)) {
      throw const TagCatalogPageValidationException();
    }
    return TagCatalogPage._(
      List.unmodifiable(items),
      pageSize,
      nextCursor,
      revision,
    );
  }

  const TagCatalogPage._(
    this.items,
    this.pageSize,
    this.nextCursor,
    this.revision,
  );

  final List<Tag> items;
  final int pageSize;
  final TagCatalogCursor? nextCursor;
  final GraphRevision revision;
}

sealed class TagCatalogReadFailure implements GraphCommandFailure {
  const TagCatalogReadFailure();
}

/// Продолжение другого запроса, размера порции или экземпляра репозитория.
final class TagCatalogInvalidCursor extends TagCatalogReadFailure {
  const TagCatalogInvalidCursor();

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

/// Эпоха или ревизия изменилась: чтение нужно начать с первой порции.
final class TagCatalogSnapshotExpired extends TagCatalogReadFailure {
  const TagCatalogSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class TagCatalogUnavailableFailure extends TagCatalogReadFailure {
  const TagCatalogUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TagCatalogCorruptionFailure extends TagCatalogReadFailure {
  const TagCatalogCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TagCatalogUnexpectedFailure extends TagCatalogReadFailure {
  const TagCatalogUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef TagCatalogPageResult =
    GraphResult<TagCatalogPage, TagCatalogReadFailure>;
typedef TagCatalogPageSuccess =
    GraphResultSuccess<TagCatalogPage, TagCatalogReadFailure>;
typedef TagCatalogPageError =
    GraphResultFailure<TagCatalogPage, TagCatalogReadFailure>;
