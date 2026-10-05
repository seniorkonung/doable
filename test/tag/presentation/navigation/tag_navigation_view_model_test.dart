import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Tag, LongTermRelation, TagAssignment;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/tag_storage_fixture.dart';

part 'tag_navigation_terminal_watch_scenarios.dart';
part 'tag_navigation_late_page_scenarios.dart';
part 'tag_navigation_catalog_integration_scenarios.dart';

void main() {
  _realTagNavigationCatalogScenarios();

  test(
    'одноимённые намерения доступны отдельно по идентичности между порциями',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final first = _intention(1, title: 'Одинаковое название');
      final second = _intention(2, title: first.title);
      h.reads.page(0, [first], cursor: _Cursor());
      await pumpEventQueue();
      expect(h.model.canActOn(first.id), isTrue);
      expect(h.model.canActOn(second.id), isFalse);
      final pending = h.model.loadMore();
      h.reads.page(1, [second]);
      await pending;

      final loaded = h.state as TagNavigationLoaded;
      expect(loaded.items.map((item) => item.id), [first.id, second.id]);
      expect(loaded.items.map((item) => item.title), [
        first.title,
        first.title,
      ]);
      expect(h.model.canActOn(first.id), isTrue);
      expect(h.model.canActOn(second.id), isTrue);
      expect(h.model.canActOn(_intention(3, title: first.title).id), isFalse);
    },
  );

  for (final scope in TaggedIntentionsScope.values) {
    test('изменение связи требует новую основу в охвате $scope', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      var index = 0;
      if (scope == TaggedIntentionsScope.archived) {
        h.model.setScope(scope);
        h.reads.page(index++, []);
        await pumpEventQueue();
      }
      final intention = _intention(
        1,
        archived: scope == TaggedIntentionsScope.archived,
      );
      h.reads.page(index++, [intention], cursor: _Cursor());
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.change(
        2,
        changes: [
          LongTermRelationDeletedChange(
            revision: const _Revision(2),
            relation: LongTermRelation(
              id: (LongTermRelationId.decode(
                '30000000-0000-4000-8000-000000000001',
              ) as LongTermRelationIdDecodingSuccess).id,
              sourceIntentionId: intention.id,
              relatedIntentionId: _intention(2).id,
              type: LongTermRelationType.need,
              priority: RelationPriority.p1,
              scope: RelationScope.active,
              creationSequence: RelationCreationSequence(1),
            ),
          ),
        ],
      );
      expect(h.model.canActOn(intention.id), isFalse);
      expect((h.state as TagNavigationLoaded).nextCursor, isNull);
      h.reads.page(index++, [
        _intention(2, archived: scope == TaggedIntentionsScope.archived),
      ]);
      await pending;
      expect(h.reads.queries.last.tagId, _tagId(1));
      expect(h.reads.queries.last.scope, scope);
      expect(h.reads.queries.last.cursor, isNull);
      h.reads.page(index, [intention], revision: 2);
      await pumpEventQueue();
      final loaded = h.state as TagNavigationLoaded;
      expect(loaded.items.single.id, intention.id);
      expect(
        loaded.revision.compareTo(const _Revision(2)),
        GraphRevisionOrder.same,
      );
      expect(h.model.canActOn(intention.id), isTrue);
    });
  }

  for (final continuation in [false, true]) {
    test(
      'удаление намерения исключает позднюю ${continuation ? 'подгрузку' : 'первую порцию'}',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        final deleted = _intention(1, title: 'Одинаковое название');
        final remaining = _intention(2, title: deleted.title);
        Future<void>? pending;
        if (continuation) {
          h.reads.page(0, [deleted], cursor: _Cursor());
          await pumpEventQueue();
          pending = h.model.loadMore();
        }
        h.change(
          2,
          changes: [
            IntentionCatalogDeleted(
              revision: const _Revision(2),
              entry: _Entry(deleted),
            ),
          ],
        );
        expect(h.model.canActOn(deleted.id), isFalse);
        final oldIndex = continuation ? 1 : 0;
        h.reads.page(oldIndex, [deleted]);
        if (pending != null) await pending;
        await pumpEventQueue();
        expect(h.model.canActOn(deleted.id), isFalse);
        expect(h.reads.queries.last.cursor, isNull);
        h.reads.page(oldIndex + 1, [remaining], revision: 2);
        await pumpEventQueue();
        final loaded = h.state as TagNavigationLoaded;
        expect(loaded.items.single.id, remaining.id);
        expect(h.model.canActOn(deleted.id), isFalse);
        expect(h.model.canActOn(remaining.id), isTrue);
      },
    );
  }

  test(
    'отсутствие наблюдения действует и после более нового постороннего пакета',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_intention(1)], cursor: _Cursor());
      await pumpEventQueue();
      h.change(3);
      h.reads.observe(null, revision: 2);
      expect(h.state, isA<TagNavigationTagMissing>());
      h.reads.page(1, [_intention(2)], revision: 3);
      await pumpEventQueue();
      expect(h.state, isA<TagNavigationTagMissing>());
      expect(h.reads.queries, hasLength(2));
    },
  );

  for (final source in ['пакет', 'наблюдение']) {
    test(
      '$source обновляет известное имя под более новой требуемой ревизией списка',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.reads.page(0, [_intention(1)], cursor: _Cursor());
        await pumpEventQueue();
        h.change(3);
        if (source == 'пакет') {
          h.change(
            2,
            changes: [
              TagRenamedChange(
                revision: const _Revision(2),
                before: _tag('Дом'),
                after: _tag('Быт'),
              ),
            ],
          );
        } else {
          h.reads.observe(_tag('Быт'), revision: 2);
        }
        final refreshing = h.state as TagNavigationLoaded;
        expect(refreshing.tag.name.value, 'Быт');
        expect(refreshing.canUseCurrentItems, isFalse);
        h.reads.observe(_tag('Дом'));
        expect((h.state as TagNavigationLoaded).tag.name.value, 'Быт');
        h.reads.page(1, [_intention(101)], tag: _tag('Быт'), revision: 3);
        await pumpEventQueue();
        expect((h.state as TagNavigationLoaded).canUseCurrentItems, isTrue);
        expect(h.reads.queries, hasLength(2));
      },
    );
  }

  test(
    'синхронный отказ подключения наблюдения остаётся типизированным',
    () async {
      final h = _Harness(reader: _Reads(throwOnWatch: true));
      addTearDown(h.dispose);
      await pumpEventQueue();
      final failed = h.state as TagNavigationInitialFailure;
      expect(failed.failure, isA<TaggedIntentionsUnexpectedFailure>());
      expect(failed.canRetry, isFalse);
      h.reads.fail(0, const TaggedIntentionsUnexpectedFailure());
      await pumpEventQueue();
      expect(h.state, isA<TagNavigationInitialFailure>());
    },
  );

  test('оба источника подписаны до первого обращения за страницей', () async {
    final h = _Harness(checkSubscriptions: true);
    addTearDown(h.dispose);
    h.reads.page(0, []);
    await pumpEventQueue();
    expect(h.state, isA<TagNavigationLoaded>());
  });

  for (final kind in ['исключение', 'завершение', 'чужой тег']) {
    test(
      '$kind наблюдения отключает действия без раскрытия исходной ошибки',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.reads.page(0, [_intention(1)], cursor: _Cursor());
        await pumpEventQueue();
        switch (kind) {
          case 'исключение':
            h.reads.watches.single.addError(StateError('SQL и личные данные'));
          case 'завершение':
            await h.reads.watches.single.close();
          case 'чужой тег':
            h.reads.observe(_tag('Дом', id: 2));
        }
        await pumpEventQueue();
        final failed = h.state as TagNavigationLoaded;
        expect(
          failed.refreshFailure?.category,
          kind == 'чужой тег'
              ? GraphFailureCategory.corruption
              : GraphFailureCategory.unexpected,
        );
        expect(h.model.canActOn(_intention(1).id), isFalse);
        await h.model.retryRefresh();
        expect(h.reads.queries, hasLength(1));
      },
    );
  }

  test(
    'освобождение отменяет оба источника и право поздней страницы',
    () async {
      final h = _Harness();
      final stateCount = h.states.length;
      h.dispose();
      expect(h.changes.hasListener, isFalse);
      expect(h.reads.watches.single.hasListener, isFalse);
      h.reads.page(0, [_intention(1)]);
      await pumpEventQueue();
      await h.model.retryRefresh();
      expect(h.model.canActOn(_intention(1).id), isFalse);
      expect(h.states, hasLength(stateCount));
      expect(h.reads.queries, hasLength(1));
    },
  );

  test(
    'истёкшее продолжение начинает первую порцию вместо повтора курсора',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_intention(1)], cursor: _Cursor());
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.reads.fail(1, const TaggedIntentionsSnapshotExpired());
      await pending;
      expect(
        (h.state as TagNavigationLoaded).freshness,
        TagNavigationFreshness.refreshing,
      );
      expect(h.reads.queries, hasLength(3));
      expect(h.reads.queries.last.cursor, isNull);
      expect(h.model.canActOn(_intention(1).id), isFalse);
      h.reads.page(2, [_intention(101)], revision: 2, epoch: 1);
      await pumpEventQueue();
      expect(
        (h.state as TagNavigationLoaded).items.single.id,
        _intention(101).id,
      );
      expect(
        (h.state as TagNavigationLoaded).revision.compareTo(
          const _Revision(2, 1),
        ),
        GraphRevisionOrder.same,
      );
    },
  );

  test(
    'повтор истёкших первых снимков ограничен и доступен новый явный повтор',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      for (var index = 0; index < 8; index++) {
        h.reads.fail(index, const TaggedIntentionsSnapshotExpired());
        await pumpEventQueue();
      }
      expect(h.reads.queries, hasLength(8));
      expect((h.state as TagNavigationInitialFailure).canRetry, isTrue);
      final retry = h.model.retryFirstPage();
      h.reads.page(8, []);
      await retry;
      expect(h.state, isA<TagNavigationLoaded>());
    },
  );

  for (final loaded in [false, true]) {
    test(
      'явный повтор ${loaded ? 'актуализации' : 'начала'} восстанавливает бюджет старых ответов',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        if (loaded) {
          h.reads.page(0, [_intention(1)], cursor: _Cursor());
          await pumpEventQueue();
        }
        h.change(10);
        final offset = loaded ? 1 : 0;
        for (var index = offset; index < offset + 8; index++) {
          h.reads.page(index, [_intention(2)]);
          await pumpEventQueue();
        }
        expect(h.reads.queries, hasLength(offset + 8));
        if (loaded) {
          final failed = h.state as TagNavigationLoaded;
          expect(failed.freshness, TagNavigationFreshness.stale);
          expect(
            failed.refreshFailure,
            isA<TaggedIntentionsUnavailableFailure>(),
          );
          expect(failed.items.single.id, _intention(1).id);
        } else {
          expect((h.state as TagNavigationInitialFailure).canRetry, isTrue);
        }
        final retry = loaded
            ? h.model.retryRefresh()
            : h.model.retryFirstPage();
        h.reads.page(offset + 8, [_intention(2)]);
        await retry;
        await pumpEventQueue();
        expect(h.reads.queries, hasLength(offset + 10));
        h.reads.page(offset + 9, [_intention(101)], revision: 10);
        await pumpEventQueue();
        expect(
          (h.state as TagNavigationLoaded).items.single.id,
          _intention(101).id,
        );
        expect((h.state as TagNavigationLoaded).canUseCurrentItems, isTrue);
      },
    );
  }

  test('сигналы во время актуализации объединяются без лишнего чтения свежей страницы', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)], cursor: _Cursor());
    await pumpEventQueue();
    h.change(2);
    h.change(3);
    h.change(4);
    h.reads.observe(_tag('Дом'), revision: 4);
    expect(h.reads.queries, hasLength(2));
    h.reads.page(1, [_intention(101)], revision: 4);
    await pumpEventQueue();
    h.change(4);
    h.change(3);
    h.reads.observe(_tag('Старое название'), revision: 3);
    expect(h.reads.queries, hasLength(2));
    expect((h.state as TagNavigationLoaded).tag.name.value, 'Дом');
    expect((h.state as TagNavigationLoaded).canUseCurrentItems, isTrue);
  });

  test(
    'новая эпоха отвергает прежние продолжение, пакет и наблюдение',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_intention(1)], revision: 10, cursor: _Cursor());
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.reads.observe(_tag('Быт'), revision: 1, epoch: 1);
      h.change(1, epoch: 1);
      h.reads.page(1, [_intention(2)], revision: 11);
      await pending;
      expect(h.reads.queries.last.cursor, isNull);
      expect((h.state as TagNavigationLoaded).canUseCurrentItems, isFalse);
      h.reads.page(
        2,
        [_intention(101)],
        tag: _tag('Быт'),
        revision: 1,
        epoch: 1,
      );
      await pumpEventQueue();
      h.reads.observe(null, revision: 12);
      h.change(
        12,
        changes: [
          TagDeletedChange(revision: const _Revision(12), tagId: _tagId(1)),
        ],
      );
      expect((h.state as TagNavigationLoaded).tag.name.value, 'Быт');
      expect(
        (h.state as TagNavigationLoaded).items.single.id,
        _intention(101).id,
      );
      expect(h.reads.queries, hasLength(3));
    },
  );

  for (final failure in const [
    TagReadUnavailableFailure(),
    TagReadCorruptionFailure(),
    TagReadUnexpectedFailure(),
  ]) {
    test(
      'отказ наблюдения категории ${failure.category} сохраняет строки без актуальных действий',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.reads.page(0, [_intention(1)], cursor: _Cursor());
        await pumpEventQueue();
        h.reads.watches.single.add(TagReadError(failure));
        final failed = h.state as TagNavigationLoaded;
        expect(failed.refreshFailure?.category, failure.category);
        expect(failed.items.single.id, _intention(1).id);
        expect(failed.nextCursor, isNull);
        expect(h.model.canActOn(_intention(1).id), isFalse);
        final retry = h.model.retryRefresh();
        if (failure is TagReadUnavailableFailure) {
          expect(h.reads.watchedIds, hasLength(2));
          expect(h.reads.watches.first.hasListener, isFalse);
          h.reads.observe(_tag('Дом'), index: 1);
          h.reads.page(1, [_intention(2)]);
          await retry;
          expect(h.model.canActOn(_intention(2).id), isTrue);
        } else {
          await retry;
          expect(h.reads.queries, hasLength(1));
          expect(h.state, same(failed));
        }
      },
    );
  }

  _testTerminalWatchRecovery();
  _testLatePageAfterWatchFailure();

  for (final loaded in [false, true]) {
    test(
      'наблюдение отсутствия ${loaded ? 'после загрузки' : 'до страницы'} действует без пакета',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        if (loaded) {
          h.reads.page(0, [_intention(1)], cursor: _Cursor());
          await pumpEventQueue();
          unawaited(h.model.loadMore());
        }
        h.reads.observe(null, revision: 2);
        expect(h.state, isA<TagNavigationTagMissing>());
        h.reads.page(loaded ? 1 : 0, [_intention(2)]);
        await pumpEventQueue();
        h.change(
          3,
          changes: [
            TagCreatedChange(
              revision: const _Revision(3),
              after: _tag('Дом', id: 2),
            ),
          ],
        );
        h.model.setScope(TaggedIntentionsScope.archived);
        expect(h.state, isA<TagNavigationTagMissing>());
        expect(h.state.tagId, _tagId(1));
        expect(h.state.scope, TaggedIntentionsScope.archived);
        expect(h.model.canActOn(_intention(1).id), isFalse);
        expect(h.reads.queries, hasLength(loaded ? 2 : 1));
      },
    );
  }

  for (final order in [
    ['страница', 'пакет', 'наблюдение'],
    ['страница', 'наблюдение', 'пакет'],
    ['пакет', 'страница', 'наблюдение'],
    ['пакет', 'наблюдение', 'страница'],
    ['наблюдение', 'страница', 'пакет'],
    ['наблюдение', 'пакет', 'страница'],
  ]) {
    test('опережающий снимок не откатывается: ${order.join(' → ')}', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      for (final source in order) {
        switch (source) {
          case 'страница':
            h.reads.page(
              0,
              [_intention(101)],
              tag: _tag('Новое название'),
              revision: 3,
            );
            await pumpEventQueue();
          case 'пакет':
            h.change(
              2,
              changes: [
                TagRenamedChange(
                  revision: const _Revision(2),
                  before: _tag('Дом'),
                  after: _tag('Промежуточное название'),
                ),
              ],
            );
          case 'наблюдение':
            h.reads.observe(_tag('Новое название'), revision: 3);
        }
      }
      await pumpEventQueue();
      final current = h.state as TagNavigationLoaded;
      expect(current.tag.name.value, 'Новое название');
      expect(
        current.revision.compareTo(const _Revision(3)),
        GraphRevisionOrder.same,
      );
      expect(current.canUseCurrentItems, isTrue);
      expect(h.reads.queries, hasLength(1));
    });
  }

  test(
    'переименование сразу видно, отказ актуализации повторяет только чтение',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_intention(1)], cursor: _Cursor());
      await pumpEventQueue();
      expect(h.model.canActOn(_intention(1).id), isTrue);
      h.change(
        2,
        changes: [
          TagRenamedChange(
            revision: const _Revision(2),
            before: _tag('Дом'),
            after: _tag('Быт'),
          ),
        ],
      );
      final refreshing = h.state as TagNavigationLoaded;
      expect(refreshing.tag.name.value, 'Быт');
      expect(refreshing.items.single.id, _intention(1).id);
      expect(refreshing.freshness, TagNavigationFreshness.refreshing);
      expect(refreshing.hasReachedEnd, isFalse);
      expect(h.model.canActOn(_intention(1).id), isFalse);
      h.reads.fail(1, const TaggedIntentionsUnavailableFailure());
      await pumpEventQueue();
      final failed = h.state as TagNavigationLoaded;
      expect(failed.freshness, TagNavigationFreshness.stale);
      expect(failed.refreshFailure, isA<TaggedIntentionsUnavailableFailure>());
      h.reads.observe(_tag('Быт'), revision: 2);
      expect(
        (h.state as TagNavigationLoaded).freshness,
        TagNavigationFreshness.stale,
      );
      await h.model.loadMore();
      await h.model.retryLoadMore();
      expect(h.reads.queries, hasLength(2));
      final retry = h.model.retryRefresh();
      expect(h.model.retryRefresh(), same(retry));
      expect(h.reads.queries.last.cursor, isNull);
      h.reads.page(2, [_intention(101)], tag: _tag('Быт'), revision: 2);
      await retry;
      expect((h.state as TagNavigationLoaded).canUseCurrentItems, isTrue);
      expect(h.model.canActOn(_intention(101).id), isTrue);
      expect(h.model.canActOn(_intention(1).id), isFalse);
    },
  );

  test(
    'смена тега отменяет прежнее наблюдение, смена охвата сохраняет текущее',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      expect(h.reads.watchedIds, [_tagId(1)]);
      h.model.setScope(TaggedIntentionsScope.archived);
      expect(h.reads.watchedIds, [_tagId(1)]);
      h.model.setTagId(_tagId(2));
      expect(h.reads.watchedIds, [_tagId(1), _tagId(2)]);
      h.reads.observe(null, revision: 2, index: 0);
      h.reads.page(0, []);
      await pumpEventQueue();
      expect(h.state, isA<TagNavigationInitialLoading>());
      h.reads.page(1, [], tag: _tag('Другой тег', id: 2));
      await pumpEventQueue();
      expect((h.state as TagNavigationLoaded).tag.name.value, 'Другой тег');
      h.reads.observe(null, revision: 2, index: 1);
      expect(h.state, isA<TagNavigationTagMissing>());
    },
  );

  test('пакет во время начального чтения запрещает прежнюю ревизию', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.change(2);
    h.reads.page(0, [_intention(1)]);
    await pumpEventQueue();
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.reads.queries, hasLength(2));
    expect(h.reads.queries.last.cursor, isNull);
    h.reads.page(1, [_intention(101)], revision: 2);
    await pumpEventQueue();
    expect(
      (h.state as TagNavigationLoaded).items.single.id,
      _intention(101).id,
    );
  });

  test(
    'общая ревизия обновляет первую порцию и сохраняет тег и охват',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setScope(TaggedIntentionsScope.archived);
      h.reads.page(0, []);
      await pumpEventQueue();
      h.reads.page(1, [_intention(1, archived: true)], cursor: _Cursor());
      await pumpEventQueue();
      final more = h.model.loadMore();
      h.reads.page(2, [_intention(101, archived: true)]);
      await more;
      h.change(2);
      expect(h.reads.queries, hasLength(4));
      expect(h.reads.queries.last.tagId, _tagId(1));
      expect(h.reads.queries.last.scope, TaggedIntentionsScope.archived);
      expect(h.reads.queries.last.cursor, isNull);
      expect((h.state as TagNavigationLoaded).nextCursor, isNull);
      h.reads.page(3, [_intention(2, archived: true)], revision: 2);
      await pumpEventQueue();
      expect(
        (h.state as TagNavigationLoaded).items.single.id,
        _intention(2).id,
      );
    },
  );

  for (final scope in TaggedIntentionsScope.values) {
    test('пакет создания с несколькими начальными тегами обновляет выдачу '
        'одним чтением без повторов и частичных состояний: $scope', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final archived = scope == TaggedIntentionsScope.archived;
      var index = 0;
      if (archived) {
        h.model.setScope(scope);
        h.reads.page(index++, []);
        await pumpEventQueue();
      }
      final first = _intention(1, archived: archived);
      final second = _intention(2, archived: archived);
      h.reads.page(index++, [first], cursor: _Cursor());
      await pumpEventQueue();
      final more = h.model.loadMore();
      h.reads.page(index++, [second]);
      await more;
      final before = h.state as TagNavigationLoaded;
      expect(before.hasReachedEnd, isTrue);
      final stateOffset = h.states.length;
      // Созданное намерение всегда активно и помечено обоими тегами.
      final created = _intention(3);
      final package = _creation(2, created, tagNumbers: [1, 2]);

      h.changes.add(package);
      final refreshing = h.state as TagNavigationLoaded;
      expect(refreshing.items, before.items);
      expect(refreshing.freshness, TagNavigationFreshness.refreshing);
      expect(refreshing.nextCursor, isNull);
      expect(h.model.canActOn(first.id), isFalse);
      expect(h.model.canActOn(created.id), isFalse);
      expect(h.reads.queries, hasLength(index + 1));
      final query = h.reads.queries.last;
      expect(query.tagId, _tagId(1));
      expect(query.scope, scope);
      expect(query.cursor, isNull);
      expect(query.pageSize, 50);
      // Повторная доставка того же пакета не начинает ещё одно чтение.
      h.changes.add(package);
      expect(h.reads.queries, hasLength(index + 1));

      final expected = archived ? [first, second] : [first, second, created];
      h.reads.page(index, expected, revision: 2);
      await pumpEventQueue();
      final loaded = h.state as TagNavigationLoaded;
      expect(
        loaded.items.map((item) => item.id),
        expected.map((item) => item.id),
      );
      expect(loaded.tagId, _tagId(1));
      expect(loaded.scope, scope);
      expect(
        loaded.revision.compareTo(const _Revision(2)),
        GraphRevisionOrder.same,
      );
      expect(loaded.canUseCurrentItems, isTrue);
      expect(h.model.canActOn(created.id), !archived);
      // Пакет публикует только начало актуализации и её полный результат.
      expect(h.states.skip(stateOffset), [same(refreshing), same(loaded)]);
      expect(h.reads.queries, hasLength(index + 1));
    });
  }

  for (final continuation in [false, true]) {
    test('поздняя ${continuation ? 'подгрузка' : 'первая порция'} до пакета '
        'создания не заменяет выдачу с созданным намерением', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final created = _intention(3);
      Future<void>? pending;
      if (continuation) {
        h.reads.page(0, [_intention(1)], cursor: _Cursor());
        await pumpEventQueue();
        pending = h.model.loadMore();
      }
      h.changes.add(_creation(2, created, tagNumbers: [1, 2]));
      expect(h.model.canActOn(_intention(1).id), isFalse);
      final lateIndex = continuation ? 1 : 0;
      // Чтение, начатое до создания, завершается прежним снимком.
      h.reads.page(lateIndex, [_intention(2)]);
      if (pending != null) await pending;
      await pumpEventQueue();
      expect(h.model.canActOn(_intention(2).id), isFalse);
      expect(h.reads.queries, hasLength(lateIndex + 2));
      expect(h.reads.queries.last.cursor, isNull);

      h.reads.page(lateIndex + 1, [
        _intention(1),
        _intention(2),
        created,
      ], revision: 2);
      await pumpEventQueue();
      final loaded = h.state as TagNavigationLoaded;
      expect(loaded.items.map((item) => item.id), [
        _intention(1).id,
        _intention(2).id,
        created.id,
      ]);
      expect(loaded.canUseCurrentItems, isTrue);
      expect(h.model.canActOn(created.id), isTrue);
      expect(h.reads.queries, hasLength(lateIndex + 2));
    });
  }

  test('подтверждённое удаление не возвращается поздней страницей', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.change(
      2,
      changes: [
        TagDeletedChange(revision: const _Revision(2), tagId: _tagId(1)),
      ],
    );
    expect(h.state, isA<TagNavigationTagMissing>());
    h.reads.page(0, [_intention(1)]);
    await pumpEventQueue();
    expect(h.state, isA<TagNavigationTagMissing>());
    expect(h.reads.queries, hasLength(1));
  });

  test(
    'вход выбирает активный охват и отличает пустоту от отсутствия тега',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      expect(h.state, isA<TagNavigationInitialLoading>());
      expect(h.state.tagId, _tagId(1));
      expect(h.state.scope, TaggedIntentionsScope.active);
      expect(h.reads.queries.single.cursor, isNull);
      expect(h.reads.queries.single.pageSize, 50);

      h.reads.page(0, []);
      await pumpEventQueue();
      final empty = h.state as TagNavigationLoaded;
      expect(empty.tag.name.value, 'Дом');
      expect(empty.isEmpty, isTrue);
      expect(empty.hasReachedEnd, isTrue);
      await h.model.loadMore();
      expect(h.reads.queries, hasLength(1));

      h.model.setScope(TaggedIntentionsScope.archived);
      expect(h.state, isA<TagNavigationInitialLoading>());
      expect(h.state.scope, TaggedIntentionsScope.archived);
      h.reads.fail(1, const TaggedIntentionsTagNotFound());
      await pumpEventQueue();
      expect(h.state, isA<TagNavigationTagMissing>());
      expect(h.state.tagId, _tagId(1));
      expect(h.state.scope, TaggedIntentionsScope.archived);
    },
  );

  test(
    'подгрузка сохраняет порядок назначений намерениям и выполняется один раз',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final cursor = _Cursor();
      h.reads.page(0, [_intention(1), _intention(101)], cursor: cursor);
      await pumpEventQueue();
      final base = h.state as TagNavigationLoaded;
      expect(base.isEmpty, isFalse);
      expect(base.hasReachedEnd, isFalse);

      final pending = h.model.loadMore();
      expect(h.model.loadMore(), same(pending));
      expect(h.reads.queries, hasLength(2));
      expect(h.reads.queries[1].cursor, same(cursor));
      expect(
        (h.state as TagNavigationLoaded).pageStatus,
        isA<TagNavigationPageLoading>(),
      );
      h.reads.page(1, [_intention(102), _intention(2)]);
      await pending;

      final loaded = h.state as TagNavigationLoaded;
      expect(loaded.items.map((item) => item.id), [
        _intention(1).id,
        _intention(101).id,
        _intention(102).id,
        _intention(2).id,
      ]);
      expect(loaded.hasReachedEnd, isTrue);
      expect(loaded.pageStatus, isA<TagNavigationPageIdle>());
      expect(() => loaded.items.clear(), throwsUnsupportedError);
      await h.model.loadMore();
      expect(h.reads.queries, hasLength(2));
    },
  );

  test(
    'повтор временного отказа продолжает тот же снимок без повторов строк',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final cursor = _Cursor();
      h.reads.page(0, [_intention(1)], cursor: cursor);
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.reads.fail(1, const TaggedIntentionsUnavailableFailure());
      await pending;
      final failed = h.state as TagNavigationLoaded;
      expect(failed.items.single.id, _intention(1).id);
      expect(failed.nextCursor, same(cursor));
      expect((failed.pageStatus as TagNavigationPageFailure).canRetry, isTrue);
      await h.model.loadMore();
      expect(h.reads.queries, hasLength(2));

      final retry = h.model.retryLoadMore();
      expect(h.reads.queries[2].cursor, same(cursor));
      expect(h.model.retryLoadMore(), same(retry));
      expect(h.reads.queries, hasLength(3));
      h.reads.page(2, [_intention(101)]);
      await retry;
      expect((h.state as TagNavigationLoaded).items, hasLength(2));
    },
  );

  test('смена охвата очищает список и отвергает позднее продолжение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    h.model.setScope(TaggedIntentionsScope.archived);
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.reads.queries, hasLength(2));
    h.reads.page(1, [_intention(2)]);
    await pending;
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.reads.queries[2].scope, TaggedIntentionsScope.archived);
    expect(h.reads.queries[2].cursor, isNull);
    h.reads.page(2, [_intention(102, archived: true)]);
    await pumpEventQueue();
    expect(
      (h.state as TagNavigationLoaded).items.single.id,
      _intention(102).id,
    );
  });

  test(
    'быстрые смены тега и охвата ждут запрос и читают только последний выбор',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setTagId(_tagId(2));
      h.model.setScope(TaggedIntentionsScope.archived);
      h.model.setTagId(_tagId(3));
      expect(h.reads.queries, hasLength(1));
      h.reads.fail(0, const TaggedIntentionsTagNotFound());
      await pumpEventQueue();
      expect(h.state, isA<TagNavigationInitialLoading>());
      expect(h.reads.queries, hasLength(2));
      expect(h.reads.queries[1].tagId, _tagId(3));
      expect(h.reads.queries[1].scope, TaggedIntentionsScope.archived);
      h.reads.page(1, [_intention(3, archived: true)]);
      await pumpEventQueue();
      expect(h.state.tagId, _tagId(3));
      expect(
        (h.state as TagNavigationLoaded).items.single.id,
        _intention(3).id,
      );
    },
  );

  test('ошибка нового тега не показывает список прежнего выбора', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)], cursor: _Cursor());
    await pumpEventQueue();
    h.model.setTagId(_tagId(2));
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.state.tagId, _tagId(2));
    h.reads.fail(1, const TaggedIntentionsUnavailableFailure());
    await pumpEventQueue();
    expect(h.state, isA<TagNavigationInitialFailure>());
    expect(h.state.tagId, _tagId(2));
    final retry = h.model.retryFirstPage();
    expect(h.model.retryFirstPage(), same(retry));
    expect(h.reads.queries, hasLength(3));
    expect(h.reads.queries[2].tagId, _tagId(2));
    expect(h.reads.queries[2].cursor, isNull);
    h.reads.page(2, [_intention(2)]);
    await retry;
    expect((h.state as TagNavigationLoaded).items.single.id, _intention(2).id);
  });

  test('возврат к прежнему охвату всё равно создаёт новое поколение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.setScope(TaggedIntentionsScope.archived);
    h.model.setScope(TaggedIntentionsScope.active);
    h.reads.page(0, [_intention(1)]);
    await pumpEventQueue();
    expect(h.state, isA<TagNavigationInitialLoading>());
    expect(h.reads.queries, hasLength(2));
    h.reads.page(1, [_intention(2)]);
    await pumpEventQueue();
    expect((h.state as TagNavigationLoaded).items.single.id, _intention(2).id);
  });

  test('повтор неизменного выбора не начинает новое чтение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.setTagId(_tagId(1));
    h.model.setScope(TaggedIntentionsScope.active);
    h.reads.page(0, [_intention(1)]);
    await pumpEventQueue();
    final loaded = h.state;
    h.model.setTagId(_tagId(1));
    h.model.setScope(TaggedIntentionsScope.active);
    expect(h.state, same(loaded));
    expect(h.reads.queries, hasLength(1));
  });

  test('смена тега из обработчика нового охвата не повторяет уже запущенное чтение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)]);
    await pumpEventQueue();
    final listener = h.container.listen(
      tagNavigationViewModelProvider(_tagId(1)),
      (_, next) {
        if (next is TagNavigationInitialLoading &&
            next.scope == TaggedIntentionsScope.archived &&
            next.tagId == _tagId(1)) {
          h.model.setTagId(_tagId(2));
        }
      },
    );
    addTearDown(listener.close);
    h.model.setScope(TaggedIntentionsScope.archived);
    expect(h.reads.queries, hasLength(2));
    expect(h.reads.queries.last.tagId, _tagId(2));
    h.reads.page(1, [_intention(2, archived: true)]);
    await pumpEventQueue();
    expect(h.state.tagId, _tagId(2));
    expect(h.state, isA<TagNavigationLoaded>());
    expect(h.reads.queries, hasLength(2));
  });

  const failures = [
    (
      failure: TaggedIntentionsInvalidCursor(),
      category: GraphFailureCategory.validation,
    ),
    (
      failure: TaggedIntentionsUnavailableFailure(),
      category: GraphFailureCategory.unavailable,
    ),
    (
      failure: TaggedIntentionsCorruptionFailure(),
      category: GraphFailureCategory.corruption,
    ),
    (
      failure: TaggedIntentionsUnexpectedFailure(),
      category: GraphFailureCategory.unexpected,
    ),
  ];
  for (final (:failure, :category) in failures) {
    test(
      'первый отказ категории $category различим и повторяется только при недоступности',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.reads.fail(0, failure);
        await pumpEventQueue();
        final failed = h.state as TagNavigationInitialFailure;
        expect(failed.failure, same(failure));
        expect(failed.failure.category, category);
        expect(failed.canRetry, category == GraphFailureCategory.unavailable);
        await h.model.loadMore();
        await h.model.retryLoadMore();
        expect(h.reads.queries, hasLength(1));
        final retry = h.model.retryFirstPage();
        if (failed.canRetry) {
          expect(h.state, isA<TagNavigationInitialLoading>());
          expect(h.reads.queries, hasLength(2));
          expect(h.reads.queries.last.cursor, isNull);
          h.reads.page(1, []);
          await retry;
          expect(h.state, isA<TagNavigationLoaded>());
        } else {
          await retry;
          expect(h.state, same(failed));
          expect(h.reads.queries, hasLength(1));
        }
      },
    );

    test(
      'отказ продолжения категории $category сохраняет строки и безопасный статус',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        final cursor = _Cursor();
        h.reads.page(0, [_intention(1)], cursor: cursor);
        await pumpEventQueue();
        final pending = h.model.loadMore();
        h.reads.fail(1, failure);
        await pending;
        final failed = h.state as TagNavigationLoaded;
        final status = failed.pageStatus as TagNavigationPageFailure;
        expect(failed.items.single.id, _intention(1).id);
        expect(failed.hasReachedEnd, isFalse);
        expect(status.failure, same(failure));
        expect(status.failure.category, category);
        expect(status.canRetry, category == GraphFailureCategory.unavailable);
        expect(failed.nextCursor, status.canRetry ? same(cursor) : isNull);
        await h.model.loadMore();
        await h.model.retryFirstPage();
        expect(h.reads.queries, hasLength(2));
        if (!status.canRetry) {
          await h.model.retryLoadMore();
          expect(h.state, same(failed));
          expect(h.reads.queries, hasLength(2));
        }
      },
    );
  }

  test('отсутствие тега в продолжении убирает все прежние строки', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reads.page(0, [_intention(1)], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    h.reads.fail(1, const TaggedIntentionsTagNotFound());
    await pending;
    expect(h.state, isA<TagNavigationTagMissing>());
    await h.model.loadMore();
    await h.model.retryFirstPage();
    await h.model.retryLoadMore();
    expect(h.reads.queries, hasLength(2));
  });

  for (final continuation in [false, true]) {
    test(
      'исключение чтения ${continuation ? 'продолжения' : 'первой порции'} скрывает исходную причину',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        if (continuation) {
          h.reads.page(0, [_intention(1)], cursor: _Cursor());
          await pumpEventQueue();
          unawaited(h.model.loadMore());
        }
        h.reads.pending.last.completeError(StateError('SQL и личные данные'));
        await pumpEventQueue();
        final failure = switch (h.state) {
          TagNavigationInitialFailure(:final failure) => failure,
          TagNavigationLoaded(
            pageStatus: TagNavigationPageFailure(:final failure),
          ) =>
            failure,
          _ => fail('Ожидался типизированный отказ'),
        };
        expect(failure, isA<TaggedIntentionsUnexpectedFailure>());
        await h.model.retryFirstPage();
        await h.model.retryLoadMore();
        expect(h.reads.queries, hasLength(continuation ? 2 : 1));
      },
    );

    test(
      'после освобождения ${continuation ? 'подгрузка' : 'первое чтение'} и обработчики не публикуют состояние',
      () async {
        final h = _Harness();
        if (continuation) {
          h.reads.page(0, [_intention(1)], cursor: _Cursor());
          await pumpEventQueue();
          unawaited(h.model.loadMore());
        }
        h.model.setScope(TaggedIntentionsScope.archived);
        final queryCount = h.reads.queries.length;
        final stateCount = h.states.length;
        h.dispose();
        h.model.setTagId(_tagId(2));
        h.model.setScope(TaggedIntentionsScope.active);
        await h.model.loadMore();
        await h.model.retryFirstPage();
        await h.model.retryLoadMore();
        h.reads.page(queryCount - 1, [_intention(2)]);
        await pumpEventQueue();
        expect(h.states, hasLength(stateCount));
        expect(h.reads.queries, hasLength(queryCount));
      },
    );
  }

  final invalidPages = <String, void Function(_Reads)>{
    'чужой тег': (reads) => reads.page(
      0,
      [],
      tag: Tag(id: _tagId(2), name: TagName.fromInput('Дом')),
    ),
    'чужой охват': (reads) =>
        reads.page(0, [], scope: TaggedIntentionsScope.archived),
    'другой размер': (reads) => reads.page(0, [], pageSize: 49),
  };
  for (final entry in invalidPages.entries) {
    test('несогласованная первая порция: ${entry.key}', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      entry.value(h.reads);
      await pumpEventQueue();
      final failed = h.state as TagNavigationInitialFailure;
      expect(failed.failure, isA<TaggedIntentionsUnexpectedFailure>());
      expect(failed.canRetry, isFalse);
    });
  }

  for (final revision in [
    const _Revision(0),
    const _Revision(2),
    const _Revision(1, 1),
  ]) {
    test(
      'продолжение другого снимка ${revision.value}/${revision.epoch} не смешивает строки',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.reads.page(0, [_intention(1)], cursor: _Cursor());
        await pumpEventQueue();
        final pending = h.model.loadMore();
        h.reads.page(
          1,
          [_intention(101)],
          revision: revision.value,
          epoch: revision.epoch,
        );
        await pending;
        final refreshing = h.state as TagNavigationLoaded;
        expect(refreshing.items.single.id, _intention(1).id);
        expect(refreshing.nextCursor, isNull);
        expect(refreshing.freshness, TagNavigationFreshness.refreshing);
        expect(h.reads.queries, hasLength(3));
        expect(h.reads.queries.last.cursor, isNull);
        h.reads.page(
          2,
          [_intention(102)],
          revision: revision.value < 1 ? 1 : revision.value,
          epoch: revision.epoch,
        );
        await pumpEventQueue();
        expect(
          (h.state as TagNavigationLoaded).items.single.id,
          _intention(102).id,
        );
      },
    );
  }

  test(
    'повтор идентичности с другим названием в продолжении не создаёт строк',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reads.page(0, [_intention(1)], cursor: _Cursor());
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.reads.page(1, [
        _intention(101),
        _intention(1, title: 'Другое название'),
      ]);
      await pending;
      final failed = h.state as TagNavigationLoaded;
      expect(failed.items, hasLength(1));
      final status = failed.pageStatus as TagNavigationPageFailure;
      expect(status.failure, isA<TaggedIntentionsUnexpectedFailure>());
      expect(status.canRetry, isFalse);
    },
  );
}

final class _Harness {
  _Harness({_Reads? reader, bool checkSubscriptions = false})
    : reads = reader ?? _Reads() {
    if (checkSubscriptions) {
      reads.beforeRead = () {
        expect(changes.hasListener, isTrue);
        expect(reads.watches.single.hasListener, isTrue);
      };
    }
    container = ProviderContainer(
      overrides: [
        tagNavigationReaderProvider.overrideWithValue(reads),
        tagNavigationChangesProvider.overrideWithValue(changes.stream),
      ],
    );
    subscription = container.listen(
      tagNavigationViewModelProvider(_tagId(1)),
      (_, value) => states.add(value),
      fireImmediately: true,
    );
    model = container.read(tagNavigationViewModelProvider(_tagId(1)).notifier);
  }

  final _Reads reads;
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
    sync: true,
  );
  final states = <TagNavigationState>[];
  late final ProviderContainer container;
  late final ProviderSubscription<TagNavigationState> subscription;
  late final TagNavigationViewModel model;
  TagNavigationState get state => subscription.read();
  void change(
    int revision, {
    int epoch = 0,
    List<GraphChange> changes = const [],
  }) => this.changes.add(_Package(_Revision(revision, epoch), changes));
  void dispose() {
    container.dispose();
    unawaited(changes.close());
    reads.dispose();
  }
}

final class _Package implements ConfirmedGraphChangePackage {
  const _Package(this.revision, this.changes);
  @override
  final GraphRevision revision;
  @override
  final List<GraphChange> changes;
}

final class _Reads with TagReadContractTestFallback implements TagReadContract {
  _Reads({this.throwOnWatch = false, this.terminalWatches = false});
  final bool throwOnWatch;
  final bool terminalWatches;
  void Function()? beforeRead;
  final queries = <TaggedIntentionsQuery>[];
  final pending = <Completer<TaggedIntentionsPageResult>>[];
  final watchedIds = <TagId>[];
  final watches = <StreamController<TagReadResult>>[];
  final doneCallbacks = <void Function()>[];
  final dataCallbacks = <void Function(TagReadResult)>[];
  final errorCallbacks = <void Function(Object)>[];

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    if (throwOnWatch) throw StateError('SQL и личные данные');
    watchedIds.add(id);
    final watch = terminalWatches
        ? StreamController<TagReadResult>(sync: true)
        : StreamController<TagReadResult>.broadcast(sync: true);
    watches.add(watch);
    return _CapturedWatchStream(
      watch.stream,
      captureDone: doneCallbacks.add,
      captureData: dataCallbacks.add,
      captureError: errorCallbacks.add,
    );
  }

  void observe(Tag? tag, {int revision = 1, int epoch = 0, int index = 0}) =>
      watches[index].add(
        TagReadSuccess(
          GraphSnapshot(value: tag, revision: _Revision(revision, epoch)),
        ),
      );

  void dispose() {
    for (final watch in watches) {
      unawaited(watch.close());
    }
  }

  @override
  Future<TaggedIntentionsPageResult> getTaggedIntentionsPage(
    TaggedIntentionsQuery query,
  ) {
    beforeRead?.call();
    queries.add(query);
    final result = Completer<TaggedIntentionsPageResult>();
    pending.add(result);
    return result.future;
  }

  void page(
    int index,
    List<TaggedIntention> items, {
    TaggedIntentionsCursor? cursor,
    Tag? tag,
    TaggedIntentionsScope? scope,
    int? pageSize,
    int revision = 1,
    int epoch = 0,
  }) {
    final query = queries[index];
    pending[index].complete(
      TaggedIntentionsPageSuccess(
        TaggedIntentionsPage(
          tag: tag ?? Tag(id: query.tagId, name: TagName.fromInput('Дом')),
          scope: scope ?? query.scope,
          items: items,
          pageSize: pageSize ?? query.pageSize,
          nextCursor: cursor,
          revision: _Revision(revision, epoch),
        ),
      ),
    );
  }

  void fail(int index, TaggedIntentionsReadFailure failure) =>
      pending[index].complete(TaggedIntentionsPageError(failure));
}

final class _Cursor implements TaggedIntentionsCursor {}

final class _Revision implements GraphRevision {
  const _Revision(this.value, [this.epoch = 0]);
  final int value;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _Revision || epoch != other.epoch) {
      return GraphRevisionOrder.differentEpoch;
    }
    return value < other.value
        ? GraphRevisionOrder.older
        : value > other.value
        ? GraphRevisionOrder.newer
        : GraphRevisionOrder.same;
  }
}

Tag _tag(String name, {int id = 1}) =>
    Tag(id: _tagId(id), name: TagName.fromInput(name));

TagId _tagId(int n) => (TagId.decode(
  '10000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

TaggedIntention _intention(int n, {bool archived = false, String? title}) =>
    TaggedIntention(
      id: (IntentionId.decode(
        '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
      ) as IntentionIdDecodingSuccess).id,
      title: title ?? 'Намерение $n',
      archiveState: archived
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
    );

/// Пакет единого создания: одна каталожная мутация с окончательным снимком и
/// факты всех начальных назначений на одной ревизии, как в `IntentionSaved`.
_Package _creation(
  int revision,
  TaggedIntention intention, {
  required List<int> tagNumbers,
}) {
  final at = _Revision(revision);
  return _Package(at, [
    IntentionCatalogCreated(
      revision: at,
      entry: _Entry(
        intention,
        readiness: IntentionReadiness.ready,
        favoriteMark: FavoriteMark.favorite,
        tags: [
          for (final number in tagNumbers) _tag('Тег $number', id: number),
        ],
      ),
    ),
    for (final number in tagNumbers)
      TagAssignmentChangedChange(
        revision: at,
        assignment: TagAssignment(
          tagId: _tagId(number),
          intentionId: intention.id,
        ),
        state: TagAssignmentState.assigned,
      ),
  ]);
}

final class _Entry extends Fake implements IntentionCatalogEntrySnapshot {
  _Entry(
    TaggedIntention intention, {
    IntentionReadiness readiness = IntentionReadiness.notReady,
    FavoriteMark favoriteMark = FavoriteMark.notFavorite,
    List<Tag> tags = const [],
  }) : summary = IntentionSummary(
         id: intention.id,
         title: intention.title,
         hasDescription: false,
         readiness: readiness,
         archiveState: intention.archiveState,
         activeRelationCount: 0,
         createdAt: IntentionTimestamp(DateTime.utc(2026)),
         updatedAt: IntentionTimestamp(DateTime.utc(2026)),
         tags: tags,
         favoriteMark: favoriteMark,
       );

  @override
  final IntentionSummary summary;
}
