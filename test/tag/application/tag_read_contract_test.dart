import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_read_contract_test_fallback.dart';

void main() {
  test(
    'режим выбора хранит идентичность намерения и отличается от каталога',
    () {
      final intentionId = _intentionId(1);
      final sameIntentionId = _intentionId(1);
      final anotherIntentionId = _intentionId(2);
      expect(const TagCatalogBrowseMode(), const TagCatalogBrowseMode());
      final mode = TagCatalogSelectionMode(intentionId);
      expect(mode.intentionId, intentionId);
      expect(mode, TagCatalogSelectionMode(sameIntentionId));
      expect(mode.hashCode, TagCatalogSelectionMode(sameIntentionId).hashCode);
      expect(mode, isNot(TagCatalogSelectionMode(anotherIntentionId)));
      expect(mode, isNot(const TagCatalogBrowseMode()));
    },
  );

  test('полный каталог хранит все 137 тегов и защищает снимок', () {
    final tags = [
      for (var number = 1; number <= 137; number++) _tag(number, 'Тег $number'),
    ];
    const revision = _Revision();
    final snapshot = TagCatalogSnapshot(items: tags, revision: revision);
    tags.clear();
    expect(snapshot, isA<TagBrowseSnapshot>());
    expect(snapshot.items.map((tag) => tag.id), [
      for (var number = 1; number <= 137; number++)
        _tag(number, 'Тег $number').id,
    ]);
    expect(snapshot.revision, same(revision));
    expect(() => snapshot.items.clear(), throwsUnsupportedError);
  });

  test('полный выбор хранит подтверждённый признак каждой из 137 строк', () {
    final intentionId = _intentionId(1);
    final rows = [
      for (var number = 1; number <= 137; number++)
        TagSelectionRow(
          tag: _tag(number, 'Тег $number'),
          isAssigned: number.isEven,
        ),
    ];
    const revision = _Revision();
    final snapshot = TagCatalogSnapshot.selection(
      intentionId: intentionId,
      rows: rows,
      revision: revision,
    );
    rows.clear();
    expect(snapshot, isA<TagSelectionSnapshot>());
    final selection = snapshot as TagSelectionSnapshot;
    expect(selection.intentionId, intentionId);
    expect(selection.revision, same(revision));
    expect(selection.items.map((tag) => tag.name.value), [
      for (var number = 1; number <= 137; number++) 'Тег $number',
    ]);
    expect(selection.rows.map((row) => row.isAssigned), [
      for (var number = 1; number <= 137; number++) number.isEven,
    ]);
    expect(() => selection.rows.clear(), throwsUnsupportedError);
    expect(() => selection.items.clear(), throwsUnsupportedError);
  });

  test('полный снимок назначений хранит намерение и все 137 тегов', () {
    final intentionId = _intentionId(1);
    final tags = [
      for (var number = 1; number <= 137; number++) _tag(number, 'Тег $number'),
    ];
    const revision = _Revision();
    final snapshot = TagAssignmentsSnapshot(
      intentionId: intentionId,
      items: tags,
      revision: revision,
    );
    tags.clear();
    expect(snapshot.intentionId, intentionId);
    expect(snapshot.revision, same(revision));
    expect(snapshot.items.map((tag) => tag.name.value), [
      for (var number = 1; number <= 137; number++) 'Тег $number',
    ]);
    expect(() => snapshot.items.clear(), throwsUnsupportedError);
  });

  test('контракт возвращает выбор по идентичности каждого намерения', () async {
    final TagReadContract source = _TagReadSource(
      const [],
      tags: [_tag(1, 'Дом')],
    );
    for (final intentionId in [_intentionId(1), _intentionId(2)]) {
      final result = await source.getTagCatalog(
        TagCatalogSelectionMode(intentionId),
      );
      final snapshot =
          (result as TagCatalogSuccess).value as TagSelectionSnapshot;
      expect(snapshot.intentionId, intentionId);
      expect(snapshot.rows.single.isAssigned, isFalse);
      expect(snapshot.revision, isA<GraphRevision>());
    }
  });

  test(
    'пустой каталог является успехом, а категории отказов различны',
    () async {
      final TagReadContract source = _TagReadSource(const []);
      final result = await source.getTagCatalog(const TagCatalogBrowseMode());
      expect((result as TagCatalogSuccess).value.items, isEmpty);
      const failures = <TagCatalogReadFailure>[
        TagCatalogIntentionNotFound(),
        TagCatalogUnavailableFailure(),
        TagCatalogCorruptionFailure(),
        TagCatalogUnexpectedFailure(),
      ];
      expect(failures.map((failure) => failure.category), [
        GraphFailureCategory.notFound,
        GraphFailureCategory.unavailable,
        GraphFailureCategory.corruption,
        GraphFailureCategory.unexpected,
      ]);
      for (final failure in failures) {
        final TagCatalogResult outcome = TagCatalogError(failure);
        expect(outcome, isA<TagCatalogError>());
      }
    },
  );

  test(
    'контракт различает отсутствие намерения и категории отказов назначений',
    () async {
      final intentionId = _intentionId(1);
      final TagReadContract source = _TagReadSource(const []);
      final result = await source.getTagAssignments(intentionId);
      expect((result as TagAssignmentsSuccess).value.intentionId, intentionId);
      expect(result.value.items, isEmpty);
      const failures = <TagAssignmentsReadFailure>[
        TagAssignmentsIntentionNotFound(),
        TagAssignmentsUnavailableFailure(),
        TagAssignmentsCorruptionFailure(),
        TagAssignmentsUnexpectedFailure(),
      ];
      expect(failures.map((failure) => failure.category), [
        GraphFailureCategory.notFound,
        GraphFailureCategory.unavailable,
        GraphFailureCategory.corruption,
        GraphFailureCategory.unexpected,
      ]);
      for (final failure in failures) {
        final TagAssignmentsResult outcome = TagAssignmentsError(failure);
        expect(outcome, isA<TagAssignmentsError>());
      }
    },
  );

  test(
    'чтения возвращают все 137 тегов в порядке создания на одной ревизии',
    () async {
      final intentionId = _intentionId(1);
      final otherIntentionId = _intentionId(2);
      final tags = [
        for (var number = 1; number <= 137; number++)
          _tag(number, 'Тег ${138 - number}'),
      ];
      final pairs = {
        for (final tag in tags)
          TagAssignment(tagId: tag.id, intentionId: intentionId),
        TagAssignment(tagId: tags.last.id, intentionId: otherIntentionId),
      };
      const revision = _Revision();
      final TagReadContract source = _TagReadSource(
        const [],
        tags: tags,
        assignments: pairs,
        revision: revision,
      );

      final catalog = (await source.getTagCatalog(
        const TagCatalogBrowseMode(),
      ) as TagCatalogSuccess).value;
      final selection =
          (await source.getTagCatalog(
                TagCatalogSelectionMode(intentionId),
              ) as TagCatalogSuccess).value
              as TagSelectionSnapshot;
      final assignments = (await source.getTagAssignments(
        intentionId,
      ) as TagAssignmentsSuccess).value;
      final otherSelection =
          (await source.getTagCatalog(
                TagCatalogSelectionMode(otherIntentionId),
              ) as TagCatalogSuccess).value
              as TagSelectionSnapshot;
      final otherAssignments = (await source.getTagAssignments(
        otherIntentionId,
      ) as TagAssignmentsSuccess).value;
      final expectedIds = tags.map((tag) => tag.id).toList();
      tags.clear();
      pairs.clear();

      expect(catalog.items.map((tag) => tag.id), expectedIds);
      expect(selection.items.map((tag) => tag.id), expectedIds);
      expect(selection.rows.every((row) => row.isAssigned), isTrue);
      expect(selection.intentionId, intentionId);
      expect(assignments.items.map((tag) => tag.id), expectedIds);
      expect(assignments.intentionId, intentionId);
      expect(
        otherSelection.rows.where((row) => row.isAssigned).single.tag.id,
        expectedIds.last,
      );
      expect(otherAssignments.items.single.id, expectedIds.last);
      for (final snapshot in [catalog, selection, otherSelection]) {
        expect(snapshot.revision, same(revision));
        expect(() => snapshot.items.clear(), throwsUnsupportedError);
      }
      for (final snapshot in [assignments, otherAssignments]) {
        expect(snapshot.revision, same(revision));
        expect(() => snapshot.items.clear(), throwsUnsupportedError);
      }
      expect(() => selection.rows.clear(), throwsUnsupportedError);
    },
  );

  test(
    'пустые снимки существующего намерения отличаются от его отсутствия',
    () async {
      final intentionId = _intentionId(1);
      final missingIntentionId = _intentionId(99);
      final TagReadContract source = _TagReadSource(const []);

      final selection =
          (await source.getTagCatalog(
                TagCatalogSelectionMode(intentionId),
              ) as TagCatalogSuccess).value
              as TagSelectionSnapshot;
      final assignments = (await source.getTagAssignments(
        intentionId,
      ) as TagAssignmentsSuccess).value;
      expect(selection.intentionId, intentionId);
      expect(selection.rows, isEmpty);
      expect(assignments.intentionId, intentionId);
      expect(assignments.items, isEmpty);
      expect(
        (await source.getTagCatalog(
          TagCatalogSelectionMode(missingIntentionId),
        ) as TagCatalogError).failure,
        isA<TagCatalogIntentionNotFound>(),
      );
      expect(
        (await source.getTagAssignments(
          missingIntentionId,
        ) as TagAssignmentsError).failure,
        isA<TagAssignmentsIntentionNotFound>(),
      );
    },
  );

  test(
    'точечный статус проверяет обе идентичности без чтения полных списков',
    () async {
      final tag = _tag(1, 'Дом');
      final unassignedTag = _tag(2, 'Работа');
      final intentionId = _intentionId(1);
      final otherIntentionId = _intentionId(2);
      const revision = _Revision();
      final source = _TagReadSource(
        const [],
        tags: [tag, unassignedTag],
        assignments: {TagAssignment(tagId: tag.id, intentionId: intentionId)},
        revision: revision,
      );
      final TagReadContract contract = source;

      for (final (tagId, id, isAssigned) in [
        (tag.id, intentionId, true),
        (tag.id, otherIntentionId, false),
        (unassignedTag.id, intentionId, false),
      ]) {
        final status = (await contract.getTagAssignmentStatus(
          tagId,
          id,
        ) as TagAssignmentStatusSuccess).value;
        expect(status.value, isAssigned);
        expect(status.revision, same(revision));
      }
      expect(
        (await contract.getTagAssignmentStatus(
          _tag(99, 'Дом').id,
          intentionId,
        ) as TagAssignmentStatusError).failure,
        isA<TagAssignmentStatusTagNotFound>(),
      );
      expect(
        (await contract.getTagAssignmentStatus(
          tag.id,
          _intentionId(99),
        ) as TagAssignmentStatusError).failure,
        isA<TagAssignmentStatusIntentionNotFound>(),
      );
      expect(source.catalogReads, 0);
      expect(source.assignmentReads, 0);
    },
  );

  test(
    'отказы статуса различают отсутствующих участников и причины чтения',
    () {
      const failures = <TagAssignmentStatusFailure>[
        TagAssignmentStatusTagNotFound(),
        TagAssignmentStatusIntentionNotFound(),
        TagAssignmentStatusUnavailable(),
        TagAssignmentStatusCorruption(),
        TagAssignmentStatusUnexpected(),
      ];
      expect(failures.map((failure) => failure.category), [
        GraphFailureCategory.notFound,
        GraphFailureCategory.notFound,
        GraphFailureCategory.unavailable,
        GraphFailureCategory.corruption,
        GraphFailureCategory.unexpected,
      ]);
      for (final failure in failures) {
        final TagAssignmentStatusResult result = TagAssignmentStatusError(
          failure,
        );
        expect((result as TagAssignmentStatusError).failure, same(failure));
      }
    },
  );

  test(
    'запасная тестовая реализация возвращает отказы вместо пустого успеха',
    () async {
      final TagReadContract source = _FallbackTagReadSource();
      final intentionId = _intentionId(1);
      expect(
        (await source.getTagCatalog(
          TagCatalogSelectionMode(intentionId),
        ) as TagCatalogError).failure,
        isA<TagCatalogUnexpectedFailure>(),
      );
      expect(
        (await source.getTagAssignments(
          intentionId,
        ) as TagAssignmentsError).failure,
        isA<TagAssignmentsUnexpectedFailure>(),
      );
      expect(
        (await source.getTagAssignmentStatus(
          _tag(1, 'Дом').id,
          intentionId,
        ) as TagAssignmentStatusError).failure,
        isA<TagAssignmentStatusUnexpected>(),
      );
    },
  );

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
  _TagReadSource(
    this.results, {
    this.tags = const [],
    Set<IntentionId>? intentions,
    this.assignments = const {},
    this.revision = const _Revision(),
  }) : intentions = intentions ?? {_intentionId(1), _intentionId(2)};

  final List<TagReadResult> results;
  final List<Tag> tags;
  final Set<IntentionId> intentions;
  final Set<TagAssignment> assignments;
  final GraphRevision revision;
  TagId? requestedId;
  var catalogReads = 0;
  var assignmentReads = 0;

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    IntentionId intentionId,
  ) async {
    if (!tags.any((tag) => tag.id == tagId)) {
      return const TagAssignmentStatusError(TagAssignmentStatusTagNotFound());
    }
    if (!intentions.contains(intentionId)) {
      return const TagAssignmentStatusError(
        TagAssignmentStatusIntentionNotFound(),
      );
    }
    return TagAssignmentStatusSuccess(
      GraphSnapshot(
        value: assignments.contains(
          TagAssignment(tagId: tagId, intentionId: intentionId),
        ),
        revision: revision,
      ),
    );
  }

  @override
  Future<TagAssignmentsResult> getTagAssignments(
    IntentionId intentionId,
  ) async {
    assignmentReads++;
    if (!intentions.contains(intentionId)) {
      return const TagAssignmentsError(TagAssignmentsIntentionNotFound());
    }
    return TagAssignmentsSuccess(
      TagAssignmentsSnapshot(
        intentionId: intentionId,
        items: tags
            .where(
              (tag) => assignments.contains(
                TagAssignment(tagId: tag.id, intentionId: intentionId),
              ),
            )
            .toList(),
        revision: revision,
      ),
    );
  }

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
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) async {
    catalogReads++;
    if (mode case TagCatalogSelectionMode(:final intentionId)
        when !intentions.contains(intentionId)) {
      return const TagCatalogError(TagCatalogIntentionNotFound());
    }
    return TagCatalogSuccess(switch (mode) {
      TagCatalogBrowseMode() => TagCatalogSnapshot(
        items: tags,
        revision: revision,
      ),
      TagCatalogSelectionMode(:final intentionId) =>
        TagCatalogSnapshot.selection(
          intentionId: intentionId,
          rows: [
            for (final tag in tags)
              TagSelectionRow(
                tag: tag,
                isAssigned: assignments.contains(
                  TagAssignment(tagId: tag.id, intentionId: intentionId),
                ),
              ),
          ],
          revision: revision,
        ),
    });
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    requestedId = id;
    return Stream.fromIterable(results);
  }
}

final class _FallbackTagReadSource with TagReadContractTestFallback {}
