import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_target.dart';

sealed class TagCatalogMode {
  const TagCatalogMode();
}

final class TagCatalogBrowseMode extends TagCatalogMode {
  const TagCatalogBrowseMode();

  @override
  bool operator ==(Object other) => other is TagCatalogBrowseMode;

  @override
  int get hashCode => 0;
}

final class TagCatalogSelectionMode extends TagCatalogMode {
  const TagCatalogSelectionMode(this.target);

  final TagTarget target;

  @override
  bool operator ==(Object other) =>
      other is TagCatalogSelectionMode && other.target == target;

  @override
  int get hashCode => Object.hash(TagCatalogSelectionMode, target);
}

enum TagCatalogQueryValidationFailure { pageSizeOutOfRange }

final class TagCatalogQueryValidationException implements Exception {
  const TagCatalogQueryValidationException(this.failure);

  final TagCatalogQueryValidationFailure failure;
}

/// Непрозрачное продолжение относится к виду запроса, режиму и получателю,
/// размеру порции, экземпляру репозитория, эпохе, ревизии и последнему
/// внутреннему ключу порядка.
/// Оно не сериализуется и не служит идентификатором тега.
abstract interface class TagCatalogCursor {}

final class TagCatalogQuery {
  factory TagCatalogQuery({
    int pageSize = defaultPageSize,
    TagCatalogCursor? cursor,
    TagCatalogMode mode = const TagCatalogBrowseMode(),
  }) {
    if (pageSize < minPageSize || pageSize > maxPageSize) {
      throw const TagCatalogQueryValidationException(
        TagCatalogQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return TagCatalogQuery._(pageSize, cursor, mode);
  }

  const TagCatalogQuery._(this.pageSize, this.cursor, this.mode);

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  final int pageSize;
  final TagCatalogCursor? cursor;
  final TagCatalogMode mode;
}

final class TagCatalogPageValidationException implements Exception {
  const TagCatalogPageValidationException();
}

/// Теги идут в устойчивом порядке создания. Список и ревизия принадлежат
/// одному подтверждённому снимку; точное общее количество не вычисляется.
sealed class TagCatalogPage {
  factory TagCatalogPage({
    required List<Tag> items,
    required int pageSize,
    required TagCatalogCursor? nextCursor,
    required GraphRevision revision,
  }) {
    _validateTagCatalogPage(items.length, pageSize, nextCursor);
    return TagBrowsePage._(
      List.unmodifiable(items),
      pageSize,
      nextCursor,
      revision,
    );
  }

  factory TagCatalogPage.selection({
    required TagTarget target,
    required List<TagSelectionRow> rows,
    required int pageSize,
    required TagCatalogCursor? nextCursor,
    required GraphRevision revision,
  }) {
    _validateTagCatalogPage(rows.length, pageSize, nextCursor);
    final immutableRows = List<TagSelectionRow>.unmodifiable(rows);
    return TagSelectionPage._(
      target,
      immutableRows,
      List<Tag>.unmodifiable(immutableRows.map((row) => row.tag)),
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

final class TagBrowsePage extends TagCatalogPage {
  const TagBrowsePage._(
    super.items,
    super.pageSize,
    super.nextCursor,
    super.revision,
  ) : super._();
}

final class TagSelectionRow {
  const TagSelectionRow({required this.tag, required this.isAssigned});

  final Tag tag;
  final bool isAssigned;
}

final class TagSelectionPage extends TagCatalogPage {
  const TagSelectionPage._(
    this.target,
    this.rows,
    super.items,
    super.pageSize,
    super.nextCursor,
    super.revision,
  ) : super._();

  final TagTarget target;
  final List<TagSelectionRow> rows;
}

void _validateTagCatalogPage(
  int itemCount,
  int pageSize,
  TagCatalogCursor? nextCursor,
) {
  if (pageSize < TagCatalogQuery.minPageSize ||
      pageSize > TagCatalogQuery.maxPageSize ||
      itemCount > pageSize ||
      (itemCount == 0 && nextCursor != null)) {
    throw const TagCatalogPageValidationException();
  }
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

final class TagCatalogTargetNotFound extends TagCatalogReadFailure {
  const TagCatalogTargetNotFound();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
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
