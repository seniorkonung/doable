import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import '../domain/tag.dart';
import '../domain/tag_id.dart';

enum TaggedIntentionsScope { active, archived }

enum TaggedIntentionsQueryValidationFailure { pageSizeOutOfRange }

final class TaggedIntentionsQueryValidationException implements Exception {
  const TaggedIntentionsQueryValidationException(this.failure);

  final TaggedIntentionsQueryValidationFailure failure;
}

/// Продолжение относится к виду чтения, тегу, охвату, размеру порции,
/// экземпляру репозитория, эпохе и ревизии снимка.
/// Внутреннее состояние не раскрывается и курсор не сериализуется.
abstract interface class TaggedIntentionsCursor {}

final class TaggedIntentionsQuery {
  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  factory TaggedIntentionsQuery({
    required TagId tagId,
    required TaggedIntentionsScope scope,
    int pageSize = TaggedIntentionsQuery.defaultPageSize,
    TaggedIntentionsCursor? cursor,
  }) {
    if (pageSize < TaggedIntentionsQuery.minPageSize ||
        pageSize > TaggedIntentionsQuery.maxPageSize) {
      throw const TaggedIntentionsQueryValidationException(
        TaggedIntentionsQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return TaggedIntentionsQuery._(tagId, scope, pageSize, cursor);
  }

  const TaggedIntentionsQuery._(
    this.tagId,
    this.scope,
    this.pageSize,
    this.cursor,
  );

  final TagId tagId;
  final TaggedIntentionsScope scope;
  final int pageSize;
  final TaggedIntentionsCursor? cursor;
}

/// Краткие данные непосредственно помеченного намерения, включая действие.
/// Архивное состояние относится к самому намерению.
final class TaggedIntention {
  factory TaggedIntention({
    required IntentionId id,
    required String title,
    required IntentionArchiveState archiveState,
  }) =>
      TaggedIntention._(id, IntentionText.normalizeTitle(title), archiveState);

  const TaggedIntention._(this.id, this.title, this.archiveState);

  final IntentionId id;
  final String title;
  final IntentionArchiveState archiveState;
}

final class TaggedIntentionsPageValidationException implements Exception {
  const TaggedIntentionsPageValidationException();
}

/// Строки идут в устойчивом порядке создания назначений намерениям.
/// Каждая идентичность встречается один раз в собственном архивном охвате.
/// Пустой успех означает существующий тег без совпадений в выбранном охвате.
/// Точный общий счётчик, подробности намерений и дневные пути не загружаются.
final class TaggedIntentionsPage {
  factory TaggedIntentionsPage({
    required Tag tag,
    required TaggedIntentionsScope scope,
    required List<TaggedIntention> items,
    required int pageSize,
    required TaggedIntentionsCursor? nextCursor,
    required GraphRevision revision,
  }) {
    final archiveState = switch (scope) {
      TaggedIntentionsScope.active => IntentionArchiveState.active,
      TaggedIntentionsScope.archived => IntentionArchiveState.archived,
    };
    if (pageSize < TaggedIntentionsQuery.minPageSize ||
        pageSize > TaggedIntentionsQuery.maxPageSize ||
        items.length > pageSize ||
        (items.isEmpty && nextCursor != null) ||
        items.map((item) => item.id).toSet().length != items.length ||
        items.any((item) => item.archiveState != archiveState)) {
      throw const TaggedIntentionsPageValidationException();
    }
    return TaggedIntentionsPage._(
      tag,
      scope,
      List<TaggedIntention>.unmodifiable(items),
      pageSize,
      nextCursor,
      revision,
    );
  }

  const TaggedIntentionsPage._(
    this.tag,
    this.scope,
    this.items,
    this.pageSize,
    this.nextCursor,
    this.revision,
  );

  final Tag tag;
  final TaggedIntentionsScope scope;
  final List<TaggedIntention> items;
  final int pageSize;
  final TaggedIntentionsCursor? nextCursor;
  final GraphRevision revision;
}

sealed class TaggedIntentionsReadFailure implements GraphCommandFailure {
  const TaggedIntentionsReadFailure();
}

/// Продолжение другого запроса, тега, охвата, размера или экземпляра.
final class TaggedIntentionsInvalidCursor extends TaggedIntentionsReadFailure {
  const TaggedIntentionsInvalidCursor();

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

/// Эпоха или ревизия изменились: чтение нужно начать с первой порции.
final class TaggedIntentionsSnapshotExpired
    extends TaggedIntentionsReadFailure {
  const TaggedIntentionsSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class TaggedIntentionsTagNotFound extends TaggedIntentionsReadFailure {
  const TaggedIntentionsTagNotFound();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class TaggedIntentionsUnavailableFailure
    extends TaggedIntentionsReadFailure {
  const TaggedIntentionsUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TaggedIntentionsCorruptionFailure
    extends TaggedIntentionsReadFailure {
  const TaggedIntentionsCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TaggedIntentionsUnexpectedFailure
    extends TaggedIntentionsReadFailure {
  const TaggedIntentionsUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef TaggedIntentionsPageResult =
    GraphResult<TaggedIntentionsPage, TaggedIntentionsReadFailure>;
typedef TaggedIntentionsPageSuccess =
    GraphResultSuccess<TaggedIntentionsPage, TaggedIntentionsReadFailure>;
typedef TaggedIntentionsPageError =
    GraphResultFailure<TaggedIntentionsPage, TaggedIntentionsReadFailure>;
