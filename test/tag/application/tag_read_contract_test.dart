import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('режим выбора хранит тип получателя и не меняет обычный каталог', () {
    final intention = IntentionTagTarget(_intentionId(1));
    final relation = LongTermRelationTagTarget(_relationId(2));
    expect(TagCatalogQuery().mode, isA<TagCatalogBrowseMode>());
    expect(
      TagCatalogQuery(mode: TagCatalogSelectionMode(intention)).mode,
      TagCatalogSelectionMode(intention),
    );
    expect(
      TagCatalogQuery(mode: TagCatalogSelectionMode(relation)).mode,
      TagCatalogSelectionMode(relation),
    );
    expect(
      TagCatalogSelectionMode(intention),
      isNot(TagCatalogSelectionMode(relation)),
    );
  });

  test('страница выбора хранит подтверждённый признак для каждой строки', () {
    final target = IntentionTagTarget(_intentionId(1));
    final rows = [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
      TagSelectionRow(tag: _tag(2, 'Работа'), isAssigned: false),
    ];
    final page = TagCatalogPage.selection(
      target: target,
      rows: rows,
      pageSize: 2,
      nextCursor: null,
      revision: const _Revision(),
    );
    rows.clear();
    expect(page, isA<TagSelectionPage>());
    expect(page.items.map((tag) => tag.name.value), ['Дом', 'Работа']);
    final selection = page as TagSelectionPage;
    expect(selection.target, target);
    expect(selection.rows.map((row) => row.isAssigned), [true, false]);
    expect(() => selection.rows.clear(), throwsUnsupportedError);
  });

  test(
    'контракт возвращает отдельные порции выбора для обоих получателей',
    () async {
      final source = _TagReadSource(const []);
      for (final target in <TagTarget>[
        IntentionTagTarget(_intentionId(1)),
        LongTermRelationTagTarget(_relationId(2)),
      ]) {
        final result = await source.getTagCatalogPage(
          TagCatalogQuery(mode: TagCatalogSelectionMode(target)),
        );
        final page =
            (result as TagCatalogPageSuccess).value as TagSelectionPage;
        expect(page.target, target);
        expect(page.rows.single.isAssigned, isFalse);
        expect(page.revision, isA<GraphRevision>());
      }
    },
  );

  test('запрос и страница назначений ограничены и неизменяемы', () {
    final target = LongTermRelationTagTarget(_relationId(1));
    expect(TagAssignmentsQuery(target: target).pageSize, 50);
    const cursor = _AssignmentsCursor();
    for (final size in [1, 100]) {
      final query = TagAssignmentsQuery(
        target: target,
        pageSize: size,
        cursor: cursor,
      );
      expect(query.target, target);
      expect(query.cursor, same(cursor));
    }
    for (final size in [0, 101]) {
      expect(
        () => TagAssignmentsQuery(target: target, pageSize: size),
        throwsA(isA<TagAssignmentsQueryValidationException>()),
      );
    }
    final tags = [_tag(1, 'Дом')];
    final page = TagAssignmentsPage(
      target: target,
      items: tags,
      pageSize: 1,
      nextCursor: cursor,
      revision: const _Revision(),
    );
    tags.clear();
    expect(page.items.single.name.value, 'Дом');
    expect(page.nextCursor, same(cursor));
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
      () => TagAssignmentsPage(
        target: target,
        items: const [],
        pageSize: 1,
        nextCursor: cursor,
        revision: const _Revision(),
      ),
      throwsA(isA<TagAssignmentsPageValidationException>()),
    );
  });

  test('запрос помеченных сущностей проверяет размер и сохраняет выбор', () {
    final tagId = _tag(1, 'Дом').id;
    const cursor = _TaggedEntitiesCursor();
    final defaultQuery = TaggedEntitiesQuery(
      tagId: tagId,
      scope: TaggedEntitiesScope.active,
    );
    expect(defaultQuery.pageSize, 50);
    expect(defaultQuery.cursor, isNull);

    for (final size in [1, 100]) {
      final query = TaggedEntitiesQuery(
        tagId: tagId,
        scope: TaggedEntitiesScope.archived,
        pageSize: size,
        cursor: cursor,
      );
      expect(query.tagId, tagId);
      expect(query.scope, TaggedEntitiesScope.archived);
      expect(query.pageSize, size);
      expect(query.cursor, same(cursor));
    }
    for (final size in [0, 101]) {
      expect(
        () => TaggedEntitiesQuery(
          tagId: tagId,
          scope: TaggedEntitiesScope.active,
          pageSize: size,
        ),
        throwsA(isA<TaggedEntitiesQueryValidationException>()),
      );
    }
  });

  test('смешанная страница хранит типы сущностей и защищает снимок', () {
    final tag = _tag(1, 'Дом');
    final intention = TaggedIntention(
      id: _intentionId(2),
      title: ' Намерение ',
      archiveState: IntentionArchiveState.active,
    );
    final relation = TaggedLongTermRelation(
      id: _relationId(3),
      type: LongTermRelationType.need,
      sourceTitle: ' Источник ',
      relatedTitle: ' Результат ',
      scope: RelationScope.active,
    );
    final rows = <TaggedEntity>[intention, relation];
    const cursor = _TaggedEntitiesCursor();
    const revision = _Revision();
    final page = TaggedEntitiesPage(
      tag: tag,
      scope: TaggedEntitiesScope.active,
      items: rows,
      pageSize: 2,
      nextCursor: cursor,
      revision: revision,
    );
    rows.clear();

    expect(page.tag, same(tag));
    expect(page.scope, TaggedEntitiesScope.active);
    expect(page.revision, same(revision));
    expect(page.nextCursor, same(cursor));
    expect(page.items, hasLength(2));
    expect(intention.target, IntentionTagTarget(_intentionId(2)));
    expect(intention.title, 'Намерение');
    expect(relation.target, LongTermRelationTagTarget(_relationId(3)));
    expect(relation.type, LongTermRelationType.need);
    expect(relation.sourceTitle, 'Источник');
    expect(relation.relatedTitle, 'Результат');
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
      () => TaggedEntitiesPage(
        tag: tag,
        scope: TaggedEntitiesScope.active,
        items: [intention, relation],
        pageSize: 1,
        nextCursor: null,
        revision: revision,
      ),
      throwsA(isA<TaggedEntitiesPageValidationException>()),
    );
  });

  test('пустой охват и ошибочная страница различаются', () {
    final tag = _tag(1, 'Дом');
    const revision = _Revision();
    final empty = TaggedEntitiesPage(
      tag: tag,
      scope: TaggedEntitiesScope.archived,
      items: const [],
      pageSize: 50,
      nextCursor: null,
      revision: revision,
    );
    expect(empty.items, isEmpty);
    expect(empty.tag.id, tag.id);
    final archivedRelation = TaggedLongTermRelation(
      id: _relationId(3),
      type: LongTermRelationType.can,
      sourceTitle: 'Источник',
      relatedTitle: 'Результат',
      scope: RelationScope.archived,
    );
    expect(
      TaggedEntitiesPage(
        tag: tag,
        scope: TaggedEntitiesScope.archived,
        items: [archivedRelation],
        pageSize: 1,
        nextCursor: null,
        revision: revision,
      ).items.single,
      same(archivedRelation),
    );
    expect(
      () => TaggedEntitiesPage(
        tag: tag,
        scope: TaggedEntitiesScope.active,
        items: const [],
        pageSize: 50,
        nextCursor: const _TaggedEntitiesCursor(),
        revision: revision,
      ),
      throwsA(isA<TaggedEntitiesPageValidationException>()),
    );
    expect(
      () => TaggedEntitiesPage(
        tag: tag,
        scope: TaggedEntitiesScope.active,
        items: [
          TaggedIntention(
            id: _intentionId(2),
            title: 'Намерение',
            archiveState: IntentionArchiveState.archived,
          ),
        ],
        pageSize: 1,
        nextCursor: null,
        revision: revision,
      ),
      throwsA(isA<TaggedEntitiesPageValidationException>()),
    );
  });

  test('исходы чтения различают отсутствие тега и категории отказов', () async {
    final TagReadContract source = _TagReadSource(const []);
    final result = await source.getTaggedEntitiesPage(
      TaggedEntitiesQuery(
        tagId: _tag(1, 'Дом').id,
        scope: TaggedEntitiesScope.active,
      ),
    );
    expect((result as TaggedEntitiesPageSuccess).value.items, isEmpty);

    const failures = <TaggedEntitiesReadFailure>[
      TaggedEntitiesInvalidCursor(),
      TaggedEntitiesSnapshotExpired(),
      TaggedEntitiesTagNotFound(),
      TaggedEntitiesUnavailableFailure(),
      TaggedEntitiesCorruptionFailure(),
      TaggedEntitiesUnexpectedFailure(),
    ];
    expect(failures.map((failure) => failure.category), [
      GraphFailureCategory.validation,
      GraphFailureCategory.conflict,
      GraphFailureCategory.notFound,
      GraphFailureCategory.unavailable,
      GraphFailureCategory.corruption,
      GraphFailureCategory.unexpected,
    ]);
    for (final failure in failures) {
      final TaggedEntitiesPageResult outcome = TaggedEntitiesPageError(failure);
      expect(outcome, isA<TaggedEntitiesPageError>());
    }
  });

  test(
    'контракт различает отсутствие получателя и категории отказов',
    () async {
      final target = IntentionTagTarget(_intentionId(1));
      final TagReadContract source = _TagReadSource(const []);
      final result = await source.getTagAssignmentsPage(
        TagAssignmentsQuery(target: target),
      );
      expect((result as TagAssignmentsPageSuccess).value.target, target);
      expect(result.value.items, isEmpty);

      const failures = <TagAssignmentsReadFailure>[
        TagAssignmentsInvalidCursor(),
        TagAssignmentsSnapshotExpired(),
        TagAssignmentsTargetNotFound(),
        TagAssignmentsUnavailableFailure(),
        TagAssignmentsCorruptionFailure(),
        TagAssignmentsUnexpectedFailure(),
      ];
      expect(failures.map((failure) => failure.category), [
        GraphFailureCategory.validation,
        GraphFailureCategory.conflict,
        GraphFailureCategory.notFound,
        GraphFailureCategory.unavailable,
        GraphFailureCategory.corruption,
        GraphFailureCategory.unexpected,
      ]);
      expect(
        const TagCatalogTargetNotFound().category,
        GraphFailureCategory.notFound,
      );
    },
  );
  test('запрос каталога ограничивает размер порции и сохраняет курсор', () {
    expect(TagCatalogQuery().pageSize, 50);
    expect(TagCatalogQuery().cursor, isNull);

    const cursor = _Cursor();
    for (final size in [1, 100]) {
      final query = TagCatalogQuery(pageSize: size, cursor: cursor);
      expect(query.pageSize, size);
      expect(query.cursor, same(cursor));
    }
    for (final size in [-1, 0, 101]) {
      expect(
        () => TagCatalogQuery(pageSize: size),
        throwsA(
          isA<TagCatalogQueryValidationException>().having(
            (error) => error.failure,
            'причина',
            TagCatalogQueryValidationFailure.pageSizeOutOfRange,
          ),
        ),
      );
    }
  });

  test('страница сохраняет снимок и защищает строки от изменения', () {
    final items = [_tag(1, 'Дом'), _tag(2, 'Работа')];
    const revision = _Revision();
    const cursor = _Cursor();
    final page = TagCatalogPage(
      items: items,
      pageSize: 2,
      nextCursor: cursor,
      revision: revision,
    );

    items.clear();
    expect(page.items.map((tag) => tag.name.value), ['Дом', 'Работа']);
    expect(page.revision, same(revision));
    expect(page.nextCursor, same(cursor));
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
      () => TagCatalogPage(
        items: [_tag(1, 'Дом'), _tag(2, 'Работа')],
        pageSize: 1,
        nextCursor: null,
        revision: revision,
      ),
      throwsA(isA<TagCatalogPageValidationException>()),
    );
    expect(
      () => TagCatalogPage(
        items: const [],
        pageSize: 50,
        nextCursor: cursor,
        revision: revision,
      ),
      throwsA(isA<TagCatalogPageValidationException>()),
    );
  });

  test(
    'пустой каталог является успехом, а чужой и устаревший курсоры различны',
    () async {
      final TagReadContract source = _TagReadSource(const []);
      final empty = await source.getTagCatalogPage(TagCatalogQuery());
      expect((empty as TagCatalogPageSuccess).value.items, isEmpty);

      const failures = <TagCatalogReadFailure>[
        TagCatalogInvalidCursor(),
        TagCatalogSnapshotExpired(),
        TagCatalogUnavailableFailure(),
        TagCatalogCorruptionFailure(),
        TagCatalogUnexpectedFailure(),
      ];
      expect(failures.map((failure) => failure.category), [
        GraphFailureCategory.validation,
        GraphFailureCategory.conflict,
        GraphFailureCategory.unavailable,
        GraphFailureCategory.corruption,
        GraphFailureCategory.unexpected,
      ]);
      for (final failure in failures) {
        final TagCatalogPageResult result = TagCatalogPageError(failure);
        expect(result, isA<TagCatalogPageError>());
      }
    },
  );

  test('наблюдение различает найденный тег, его отсутствие и отказ', () async {
    final tag = _tag(1, 'Дом');
    const revision = _Revision();
    final source = _TagReadSource([
      TagReadSuccess(GraphSnapshot(value: tag, revision: revision)),
      const TagReadSuccess(GraphSnapshot(value: null, revision: revision)),
      const TagReadError(TagReadUnavailableFailure()),
    ]);

    final results = await source.watchTag(tag.id).toList();
    expect((results[0] as TagReadSuccess).value.value, same(tag));
    expect((results[1] as TagReadSuccess).value.value, isNull);
    expect(
      (results[2] as TagReadError).failure.category,
      GraphFailureCategory.unavailable,
    );
    expect(source.requestedId, tag.id);
  });

  test('отказы наблюдения отличают повреждение от неожиданной причины', () {
    const failures = <TagReadFailure>[
      TagReadUnavailableFailure(),
      TagReadCorruptionFailure(),
      TagReadUnexpectedFailure(),
    ];
    expect(failures.map((failure) => failure.category), [
      GraphFailureCategory.unavailable,
      GraphFailureCategory.corruption,
      GraphFailureCategory.unexpected,
    ]);
  });
}

Tag _tag(int value, String name) => Tag(
  id: (TagId.decode(
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);

IntentionId _intentionId(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

final class _Cursor implements TagCatalogCursor {
  const _Cursor();
}

final class _AssignmentsCursor implements TagAssignmentsCursor {
  const _AssignmentsCursor();
}

final class _TaggedEntitiesCursor implements TaggedEntitiesCursor {
  const _TaggedEntitiesCursor();
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is _Revision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

final class _TagReadSource implements TagReadContract {
  _TagReadSource(this.results);

  final List<TagReadResult> results;
  TagId? requestedId;

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    TagTarget target,
  ) async => const TagAssignmentStatusError(TagAssignmentStatusUnexpected());

  @override
  Future<TagAssignmentsPageResult> getTagAssignmentsPage(
    TagAssignmentsQuery query,
  ) async => TagAssignmentsPageSuccess(
    TagAssignmentsPage(
      target: query.target,
      items: const [],
      pageSize: query.pageSize,
      nextCursor: null,
      revision: const _Revision(),
    ),
  );

  @override
  Future<TaggedEntitiesPageResult> getTaggedEntitiesPage(
    TaggedEntitiesQuery query,
  ) async => TaggedEntitiesPageSuccess(
    TaggedEntitiesPage(
      tag: _tag(1, 'Дом'),
      scope: query.scope,
      items: const [],
      pageSize: query.pageSize,
      nextCursor: null,
      revision: const _Revision(),
    ),
  );

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) async {
    return TagCatalogPageSuccess(switch (query.mode) {
      TagCatalogBrowseMode() => TagCatalogPage(
        items: const [],
        pageSize: query.pageSize,
        nextCursor: null,
        revision: const _Revision(),
      ),
      TagCatalogSelectionMode(:final target) => TagCatalogPage.selection(
        target: target,
        rows: [TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false)],
        pageSize: query.pageSize,
        nextCursor: null,
        revision: const _Revision(),
      ),
    });
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    requestedId = id;
    return Stream.fromIterable(results);
  }
}
