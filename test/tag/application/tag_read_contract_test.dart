import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
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
