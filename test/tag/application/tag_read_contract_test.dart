import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('запрос помеченных намерений проверяет размер и сохраняет выбор', () {
    final tagId = _tag(1, 'Дом').id;
    const cursor = _TaggedIntentionsCursor();
    final defaultQuery = TaggedIntentionsQuery(
      tagId: tagId,
      scope: TaggedIntentionsScope.active,
    );
    expect(defaultQuery.pageSize, 50);
    expect(defaultQuery.cursor, isNull);

    for (final size in [1, 100]) {
      final query = TaggedIntentionsQuery(
        tagId: tagId,
        scope: TaggedIntentionsScope.archived,
        pageSize: size,
        cursor: cursor,
      );
      expect(query.tagId, tagId);
      expect(query.scope, TaggedIntentionsScope.archived);
      expect(query.pageSize, size);
      expect(query.cursor, same(cursor));
    }
    for (final size in [-1, 0, 101]) {
      expect(
        () => TaggedIntentionsQuery(
          tagId: tagId,
          scope: TaggedIntentionsScope.active,
          pageSize: size,
        ),
        throwsA(
          isA<TaggedIntentionsQueryValidationException>().having(
            (error) => error.failure,
            'причина отказа',
            TaggedIntentionsQueryValidationFailure.pageSizeOutOfRange,
          ),
        ),
      );
    }
  });

  test('страницы обоих охватов сохраняют одноимённые намерения и снимок', () {
    final tag = _tag(1, 'Дом');
    const cursor = _TaggedIntentionsCursor();
    const revision = _Revision();
    for (final (scope, archiveState) in [
      (TaggedIntentionsScope.active, IntentionArchiveState.active),
      (TaggedIntentionsScope.archived, IntentionArchiveState.archived),
    ]) {
      final rows = [
        for (final id in [_intentionId(2), _intentionId(1)])
          TaggedIntention(
            id: id,
            title: ' Намерение ',
            archiveState: archiveState,
          ),
      ];
      final page = TaggedIntentionsPage(
        tag: tag,
        scope: scope,
        items: rows,
        pageSize: 2,
        nextCursor: cursor,
        revision: revision,
      );
      rows.clear();

      final List<TaggedIntention> items = page.items;
      expect(page.tag, same(tag));
      expect(page.scope, scope);
      expect(page.pageSize, 2);
      expect(page.revision, same(revision));
      expect(page.nextCursor, same(cursor));
      expect(items.map((item) => item.id), [_intentionId(2), _intentionId(1)]);
      expect(items.map((item) => item.title), ['Намерение', 'Намерение']);
      expect(items.map((item) => item.archiveState), [
        archiveState,
        archiveState,
      ]);
      expect(() => items.clear(), throwsUnsupportedError);
    }
  });

  test('пустой охват сохраняет тег и ревизию без продолжения', () {
    final tag = _tag(1, 'Дом');
    const revision = _Revision();
    for (final scope in TaggedIntentionsScope.values) {
      final empty = TaggedIntentionsPage(
        tag: tag,
        scope: scope,
        items: const [],
        pageSize: 50,
        nextCursor: null,
        revision: revision,
      );
      expect(empty.items, isEmpty);
      expect(empty.tag.id, tag.id);
      expect(empty.scope, scope);
      expect(empty.revision, same(revision));
      expect(empty.nextCursor, isNull);
      expect(() => empty.items.clear(), throwsUnsupportedError);
    }
  });

  test('страница отклоняет недопустимый размер и превышение границы', () {
    final intention = TaggedIntention(
      id: _intentionId(1),
      title: 'Намерение',
      archiveState: IntentionArchiveState.active,
    );
    for (final size in [-1, 0, 101]) {
      expect(
        () => TaggedIntentionsPage(
          tag: _tag(1, 'Дом'),
          scope: TaggedIntentionsScope.active,
          items: [intention],
          pageSize: size,
          nextCursor: null,
          revision: const _Revision(),
        ),
        throwsA(isA<TaggedIntentionsPageValidationException>()),
      );
    }
    expect(
      () => TaggedIntentionsPage(
        tag: _tag(1, 'Дом'),
        scope: TaggedIntentionsScope.active,
        items: [
          intention,
          TaggedIntention(
            id: _intentionId(2),
            title: 'Другое намерение',
            archiveState: IntentionArchiveState.active,
          ),
        ],
        pageSize: 1,
        nextCursor: null,
        revision: const _Revision(),
      ),
      throwsA(isA<TaggedIntentionsPageValidationException>()),
    );
  });

  test('страница допускает 100 намерений и отклоняет 101 без усечения', () {
    final rows = [
      for (var number = 1; number <= 101; number++)
        TaggedIntention(
          id: _intentionId(number),
          title: 'Намерение $number',
          archiveState: IntentionArchiveState.active,
        ),
    ];
    final page = TaggedIntentionsPage(
      tag: _tag(1, 'Дом'),
      scope: TaggedIntentionsScope.active,
      items: rows.take(100).toList(),
      pageSize: 100,
      nextCursor: null,
      revision: const _Revision(),
    );
    expect(page.items.map((item) => item.id), [
      for (var number = 1; number <= 100; number++) _intentionId(number),
    ]);
    expect(
      () => TaggedIntentionsPage(
        tag: _tag(1, 'Дом'),
        scope: TaggedIntentionsScope.active,
        items: rows,
        pageSize: 100,
        nextCursor: null,
        revision: const _Revision(),
      ),
      throwsA(isA<TaggedIntentionsPageValidationException>()),
    );
  });

  test('пустая страница не допускает продолжения', () {
    expect(
      () => TaggedIntentionsPage(
        tag: _tag(1, 'Дом'),
        scope: TaggedIntentionsScope.active,
        items: const [],
        pageSize: 50,
        nextCursor: const _TaggedIntentionsCursor(),
        revision: const _Revision(),
      ),
      throwsA(isA<TaggedIntentionsPageValidationException>()),
    );
  });

  test('страница отклоняет намерение из другого архивного охвата', () {
    for (final (scope, archiveState) in [
      (TaggedIntentionsScope.active, IntentionArchiveState.archived),
      (TaggedIntentionsScope.archived, IntentionArchiveState.active),
    ]) {
      expect(
        () => TaggedIntentionsPage(
          tag: _tag(1, 'Дом'),
          scope: scope,
          items: [
            TaggedIntention(
              id: _intentionId(1),
              title: 'Намерение',
              archiveState: archiveState,
            ),
          ],
          pageSize: 1,
          nextCursor: null,
          revision: const _Revision(),
        ),
        throwsA(isA<TaggedIntentionsPageValidationException>()),
      );
    }
  });

  test('страница не допускает повтор одной идентичности намерения', () {
    expect(
      () => TaggedIntentionsPage(
        tag: _tag(1, 'Дом'),
        scope: TaggedIntentionsScope.active,
        items: [
          for (final title in ['Название', 'Другое название'])
            TaggedIntention(
              id: _intentionId(1),
              title: title,
              archiveState: IntentionArchiveState.active,
            ),
        ],
        pageSize: 2,
        nextCursor: null,
        revision: const _Revision(),
      ),
      throwsA(isA<TaggedIntentionsPageValidationException>()),
    );
  });

  test('краткие данные намерения отклоняют недопустимое название', () {
    for (final title in [' ', 'а' * 256, 'а\u0000', '\uD800']) {
      expect(
        () => TaggedIntention(
          id: _intentionId(1),
          title: title,
          archiveState: IntentionArchiveState.active,
        ),
        throwsA(isA<IntentionTextValidationException>()),
      );
    }
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

final class _TaggedIntentionsCursor implements TaggedIntentionsCursor {
  const _TaggedIntentionsCursor();
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is _Revision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}
