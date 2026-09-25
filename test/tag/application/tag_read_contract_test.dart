import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

final class _Cursor implements TagCatalogCursor {
  const _Cursor();
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
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) async =>
      TagCatalogPageSuccess(
        TagCatalogPage(
          items: const [],
          pageSize: query.pageSize,
          nextCursor: null,
          revision: const _Revision(),
        ),
      );

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    requestedId = id;
    return Stream.fromIterable(results);
  }
}
