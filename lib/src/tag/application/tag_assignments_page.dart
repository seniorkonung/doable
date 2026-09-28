import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_target.dart';
import 'tag_catalog.dart';

enum TagAssignmentsQueryValidationFailure { pageSizeOutOfRange }

final class TagAssignmentsQueryValidationException implements Exception {
  const TagAssignmentsQueryValidationException(this.failure);

  final TagAssignmentsQueryValidationFailure failure;
}

/// Продолжение принадлежит виду запроса, получателю, размеру порции,
/// экземпляру репозитория, эпохе, ревизии и последнему ключу порядка.
/// Оно не сериализуется и не раскрывает внутренний порядок хранения.
abstract interface class TagAssignmentsCursor {}

final class TagAssignmentsQuery {
  factory TagAssignmentsQuery({
    required TagTarget target,
    int pageSize = TagCatalogQuery.defaultPageSize,
    TagAssignmentsCursor? cursor,
  }) {
    if (pageSize < TagCatalogQuery.minPageSize ||
        pageSize > TagCatalogQuery.maxPageSize) {
      throw const TagAssignmentsQueryValidationException(
        TagAssignmentsQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return TagAssignmentsQuery._(target, pageSize, cursor);
  }

  const TagAssignmentsQuery._(this.target, this.pageSize, this.cursor);

  final TagTarget target;
  final int pageSize;
  final TagAssignmentsCursor? cursor;
}

final class TagAssignmentsPageValidationException implements Exception {
  const TagAssignmentsPageValidationException();
}

/// Назначенные получателю теги идут в порядке создания тегов.
/// Пустой успех означает существующего получателя без назначений.
final class TagAssignmentsPage {
  factory TagAssignmentsPage({
    required TagTarget target,
    required List<Tag> items,
    required int pageSize,
    required TagAssignmentsCursor? nextCursor,
    required GraphRevision revision,
  }) {
    if (pageSize < TagCatalogQuery.minPageSize ||
        pageSize > TagCatalogQuery.maxPageSize ||
        items.length > pageSize ||
        (items.isEmpty && nextCursor != null)) {
      throw const TagAssignmentsPageValidationException();
    }
    return TagAssignmentsPage._(
      target,
      List<Tag>.unmodifiable(items),
      pageSize,
      nextCursor,
      revision,
    );
  }

  const TagAssignmentsPage._(
    this.target,
    this.items,
    this.pageSize,
    this.nextCursor,
    this.revision,
  );

  final TagTarget target;
  final List<Tag> items;
  final int pageSize;
  final TagAssignmentsCursor? nextCursor;
  final GraphRevision revision;
}

sealed class TagAssignmentsReadFailure implements GraphCommandFailure {
  const TagAssignmentsReadFailure();
}

final class TagAssignmentsInvalidCursor extends TagAssignmentsReadFailure {
  const TagAssignmentsInvalidCursor();

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

final class TagAssignmentsSnapshotExpired extends TagAssignmentsReadFailure {
  const TagAssignmentsSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class TagAssignmentsTargetNotFound extends TagAssignmentsReadFailure {
  const TagAssignmentsTargetNotFound();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class TagAssignmentsUnavailableFailure extends TagAssignmentsReadFailure {
  const TagAssignmentsUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TagAssignmentsCorruptionFailure extends TagAssignmentsReadFailure {
  const TagAssignmentsCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TagAssignmentsUnexpectedFailure extends TagAssignmentsReadFailure {
  const TagAssignmentsUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef TagAssignmentsPageResult =
    GraphResult<TagAssignmentsPage, TagAssignmentsReadFailure>;
typedef TagAssignmentsPageSuccess =
    GraphResultSuccess<TagAssignmentsPage, TagAssignmentsReadFailure>;
typedef TagAssignmentsPageError =
    GraphResultFailure<TagAssignmentsPage, TagAssignmentsReadFailure>;
