import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../domain/tag.dart';
import '../domain/tag_id.dart';
import '../domain/tag_target.dart';

enum TaggedEntitiesScope { active, archived }

enum TaggedEntitiesQueryValidationFailure { pageSizeOutOfRange }

final class TaggedEntitiesQueryValidationException implements Exception {
  const TaggedEntitiesQueryValidationException(this.failure);

  final TaggedEntitiesQueryValidationFailure failure;
}

/// Продолжение относится к виду чтения, тегу, охвату, размеру порции,
/// экземпляру репозитория, эпохе, ревизии и последнему порядковому ключу.
/// Внутренний ключ не раскрывается и курсор не сериализуется.
abstract interface class TaggedEntitiesCursor {}

final class TaggedEntitiesQuery {
  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  factory TaggedEntitiesQuery({
    required TagId tagId,
    required TaggedEntitiesScope scope,
    int pageSize = TaggedEntitiesQuery.defaultPageSize,
    TaggedEntitiesCursor? cursor,
  }) {
    if (pageSize < TaggedEntitiesQuery.minPageSize ||
        pageSize > TaggedEntitiesQuery.maxPageSize) {
      throw const TaggedEntitiesQueryValidationException(
        TaggedEntitiesQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return TaggedEntitiesQuery._(tagId, scope, pageSize, cursor);
  }

  const TaggedEntitiesQuery._(
    this.tagId,
    this.scope,
    this.pageSize,
    this.cursor,
  );

  final TagId tagId;
  final TaggedEntitiesScope scope;
  final int pageSize;
  final TaggedEntitiesCursor? cursor;
}

/// Только непосредственно помеченные намерения и долговременные связи.
/// Названия участников связи относятся к тому же снимку, что и сама строка.
sealed class TaggedEntity {
  const TaggedEntity();

  TagTarget get target;
}

final class TaggedIntention extends TaggedEntity {
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

  @override
  TagTarget get target => IntentionTagTarget(id);
}

final class TaggedLongTermRelation extends TaggedEntity {
  factory TaggedLongTermRelation({
    required LongTermRelationId id,
    required LongTermRelationType type,
    required String sourceTitle,
    required String relatedTitle,
    required RelationScope scope,
  }) => TaggedLongTermRelation._(
    id,
    type,
    IntentionText.normalizeTitle(sourceTitle),
    IntentionText.normalizeTitle(relatedTitle),
    scope,
  );

  const TaggedLongTermRelation._(
    this.id,
    this.type,
    this.sourceTitle,
    this.relatedTitle,
    this.scope,
  );

  final LongTermRelationId id;
  final LongTermRelationType type;
  final String sourceTitle;
  final String relatedTitle;
  final RelationScope scope;

  @override
  TagTarget get target => LongTermRelationTagTarget(id);
}

final class TaggedEntitiesPageValidationException implements Exception {
  const TaggedEntitiesPageValidationException();
}

/// Строки идут в устойчивом порядке создания назначений обоих видов.
/// Пустой успех означает существующий тег без совпадений в выбранном охвате.
/// Точный общий счётчик, подробности сущностей и дневные пути не загружаются.
final class TaggedEntitiesPage {
  factory TaggedEntitiesPage({
    required Tag tag,
    required TaggedEntitiesScope scope,
    required List<TaggedEntity> items,
    required int pageSize,
    required TaggedEntitiesCursor? nextCursor,
    required GraphRevision revision,
  }) {
    if (pageSize < TaggedEntitiesQuery.minPageSize ||
        pageSize > TaggedEntitiesQuery.maxPageSize ||
        items.length > pageSize ||
        (items.isEmpty && nextCursor != null) ||
        items.any((item) => !_belongsToScope(item, scope))) {
      throw const TaggedEntitiesPageValidationException();
    }
    return TaggedEntitiesPage._(
      tag,
      scope,
      List<TaggedEntity>.unmodifiable(items),
      pageSize,
      nextCursor,
      revision,
    );
  }

  const TaggedEntitiesPage._(
    this.tag,
    this.scope,
    this.items,
    this.pageSize,
    this.nextCursor,
    this.revision,
  );

  final Tag tag;
  final TaggedEntitiesScope scope;
  final List<TaggedEntity> items;
  final int pageSize;
  final TaggedEntitiesCursor? nextCursor;
  final GraphRevision revision;
}

bool _belongsToScope(TaggedEntity item, TaggedEntitiesScope scope) =>
    switch (item) {
      TaggedIntention(:final archiveState) =>
        (archiveState == IntentionArchiveState.active) ==
            (scope == TaggedEntitiesScope.active),
      TaggedLongTermRelation(scope: final relationScope) =>
        (relationScope == RelationScope.active) ==
            (scope == TaggedEntitiesScope.active),
    };

sealed class TaggedEntitiesReadFailure implements GraphCommandFailure {
  const TaggedEntitiesReadFailure();
}

/// Продолжение другого запроса, тега, охвата, размера или экземпляра.
final class TaggedEntitiesInvalidCursor extends TaggedEntitiesReadFailure {
  const TaggedEntitiesInvalidCursor();

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

/// Эпоха или ревизия изменились: чтение нужно начать с первой порции.
final class TaggedEntitiesSnapshotExpired extends TaggedEntitiesReadFailure {
  const TaggedEntitiesSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class TaggedEntitiesTagNotFound extends TaggedEntitiesReadFailure {
  const TaggedEntitiesTagNotFound();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class TaggedEntitiesUnavailableFailure extends TaggedEntitiesReadFailure {
  const TaggedEntitiesUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TaggedEntitiesCorruptionFailure extends TaggedEntitiesReadFailure {
  const TaggedEntitiesCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TaggedEntitiesUnexpectedFailure extends TaggedEntitiesReadFailure {
  const TaggedEntitiesUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef TaggedEntitiesPageResult =
    GraphResult<TaggedEntitiesPage, TaggedEntitiesReadFailure>;
typedef TaggedEntitiesPageSuccess =
    GraphResultSuccess<TaggedEntitiesPage, TaggedEntitiesReadFailure>;
typedef TaggedEntitiesPageError =
    GraphResultFailure<TaggedEntitiesPage, TaggedEntitiesReadFailure>;
