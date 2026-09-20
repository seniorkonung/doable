import 'dart:async';

import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neighborhood_test_support.dart';

void main() {
  test('первое чтение открывает активную исходящую группу «нужно»', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    expect(
      harness.state,
      isA<RelationGroupInitialLoad>().having(
        (value) => value.selection,
        'выбор',
        RelationGroupSelection.initial,
      ),
    );
    expect(repository.requestCount, 1);
    final query = repository.queryAt(0);
    expect(query.intentionId, harness.intentionId);
    expect(query.type, LongTermRelationType.need);
    expect(query.direction, RelationDirection.outgoing);
    expect(query.scope, RelationScope.active);
    expect(query.pageSize, 50);
    expect(query.cursor, isNull);
  });

  test('успешное отсутствие связей отличается от ошибки', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: const [],
        counts: testRelationCounts(activeCanOutgoing: 3),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    expect(
      harness.state,
      isA<RelationGroupEmpty>()
          .having((value) => value.totalCount, 'количество группы', 0)
          .having(
            (value) => value.counts.activeCanOutgoing,
            'количество другой группы',
            3,
          ),
    );
  });

  test('первая порция большой группы сохраняет продолжение', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();

    expect(
      harness.loaded,
      isA<RelationGroupLoaded>()
          .having((value) => value.items.length, 'загружено строк', 2)
          .having((value) => value.totalCount, 'полное количество', 5)
          .having(
            (value) => value.hasConfirmedEnd,
            'подтверждённый конец',
            false,
          )
          .having(
            (value) => value.progress,
            'процесс',
            isA<RelationGroupIdle>(),
          ),
    );
  });

  test('малая группа сразу даёт подтверждённый конец', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(index: 0, from: 1, count: 3, totalCount: 3);
    await pumpEventQueue();

    expect(harness.loaded.hasConfirmedEnd, isTrue);
    expect(harness.loaded.items.length, 3);
  });

  test('повторная прокрутка не отправляет то же продолжение дважды', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();

    harness.scrollTo(1);
    harness.scrollTo(1);

    expect(repository.requestCount, 2);
    expect(repository.queryAt(1).cursor, isA<TestRelationGroupCursor>());
    expect(harness.loaded.progress, isA<RelationGroupLoadingMore>());
  });

  test('далёкая от конца прокрутка не запрашивает продолжение', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository, prefetchRemaining: 0);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 3,
      totalCount: 9,
      nextCursor: const TestRelationGroupCursor(3),
    );
    await pumpEventQueue();

    harness.scrollTo(0);

    expect(repository.requestCount, 1);
  });

  test('подгрузка присоединяет строки без повторов', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);

    // Повторная доставка уже полученной строки не добавляет её второй раз.
    repository.completePage(
      1,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.intentionId, from: 2, count: 4),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    expect(harness.relationIds, [
      for (var index = 1; index <= 5; index += 1) testRelationId(index),
    ]);
    expect(harness.loaded.hasConfirmedEnd, isTrue);
    expect(harness.loaded.totalCount, 5);
    expect(harness.loaded.progress, isA<RelationGroupIdle>());
  });

  test('смена типа начинает новую группу с первой порции', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(index: 0, from: 1, count: 2, totalCount: 2);
    await pumpEventQueue();

    harness.viewModel.selectType(LongTermRelationType.can);

    expect(harness.state, isA<RelationGroupInitialLoad>());
    expect(repository.requestCount, 2);
    final query = repository.queryAt(1);
    expect(query.type, LongTermRelationType.can);
    expect(query.direction, RelationDirection.outgoing);
    expect(query.scope, RelationScope.active);
    expect(query.cursor, isNull);
  });

  test('переключение в архив сохраняет тип и направление', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.viewModel.selectDirection(RelationDirection.incoming);
    harness.viewModel.selectScope(RelationScope.archived);
    harness.viewModel.selectType(LongTermRelationType.can);

    expect(repository.requestCount, 4);
    final query = repository.queryAt(3);
    expect(query.type, LongTermRelationType.can);
    expect(query.direction, RelationDirection.incoming);
    expect(query.scope, RelationScope.archived);
    expect(harness.state.selection.scope, RelationScope.archived);
  });

  test('повторный выбор той же группы не перечитывает её', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.viewModel.selectType(LongTermRelationType.need);
    harness.viewModel.selectDirection(RelationDirection.outgoing);
    harness.viewModel.selectScope(RelationScope.active);

    expect(repository.requestCount, 1);
  });

  test('поздний ответ прежней группы не попадает в новый выбор', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);

    harness.viewModel.selectScope(RelationScope.archived);
    repository.completePage(
      1,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.intentionId, from: 3, count: 3),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    expect(harness.state, isA<RelationGroupInitialLoad>());

    harness.completeFirstPage(
      index: 2,
      from: 10,
      count: 1,
      totalCount: 1,
      scope: RelationScope.archived,
    );
    await pumpEventQueue();

    expect(harness.relationIds, [testRelationId(10)]);
  });

  test('ошибка подгрузки сохраняет строки, продолжение и количество', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);
    repository.failRead(1, const RelationGroupUnavailableFailure());
    await pumpEventQueue();

    final loaded = harness.loaded;
    expect(loaded.items.length, 2);
    expect(loaded.totalCount, 5);
    expect(loaded.hasConfirmedEnd, isFalse);
    expect(
      loaded.progress,
      isA<RelationGroupLoadMoreFailure>()
          .having(
            (value) => value.failure,
            'причина',
            isA<RelationGroupUnavailableFailure>(),
          )
          .having((value) => value.canRetry, 'повтор доступен', true),
    );
  });

  test('повтор подгрузки продолжает список один раз', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 4,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);
    repository.failRead(1, const RelationGroupUnavailableFailure());
    await pumpEventQueue();

    harness.retryLoadMore();
    expect(repository.requestCount, 3);
    repository.completePage(
      2,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.intentionId, from: 3, count: 2),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    expect(harness.relationIds.length, 4);
    expect(harness.loaded.progress, isA<RelationGroupIdle>());
  });

  test('неустранимый отказ подгрузки не предлагает обычный повтор', () async {
    final failures = <RelationGroupReadFailure>[
      const RelationGroupCorruptionFailure(),
      const RelationGroupUnexpectedFailure(),
      const RelationGroupReadValidationFailure(),
    ];
    for (final failure in failures) {
      final repository = ControlledNeighborhoodRepository();
      final harness = _NeighborhoodHarness(repository);
      addTearDown(harness.dispose);

      harness.completeFirstPage(
        index: 0,
        from: 1,
        count: 2,
        totalCount: 5,
        nextCursor: const TestRelationGroupCursor(2),
      );
      await pumpEventQueue();
      harness.scrollTo(1);
      repository.failRead(1, failure);
      await pumpEventQueue();

      final progress = harness.loaded.progress;
      expect(
        progress,
        isA<RelationGroupLoadMoreFailure>().having(
          (value) => value.canRetry,
          'повтор доступен',
          false,
        ),
        reason: '$failure',
      );
      harness.retryLoadMore();
      expect(repository.requestCount, 2, reason: '$failure');
      expect(harness.loaded.hasConfirmedEnd, isFalse, reason: '$failure');
    }
  });

  test('первое чтение различает категории отказа', () async {
    final failures = <RelationGroupReadFailure, bool>{
      const RelationGroupUnavailableFailure(): true,
      const RelationGroupCorruptionFailure(): false,
      const RelationGroupUnexpectedFailure(): false,
      const RelationGroupReadValidationFailure(): false,
      RelationGroupIntentionNotFoundFailure(testIntentionId(1)): false,
    };
    for (final entry in failures.entries) {
      final repository = ControlledNeighborhoodRepository();
      final harness = _NeighborhoodHarness(repository);
      addTearDown(harness.dispose);

      repository.failRead(0, entry.key);
      await pumpEventQueue();

      expect(
        harness.state,
        isA<RelationGroupInitialFailure>()
            .having((value) => value.failure, 'причина', same(entry.key))
            .having((value) => value.canRetry, 'повтор доступен', entry.value),
        reason: '${entry.key}',
      );
    }
  });

  test('устаревший снимок первой порции не объявляется повреждением', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    repository.failRead(0, const RelationGroupSnapshotExpired());
    await pumpEventQueue();

    expect(
      harness.state,
      isA<RelationGroupInitialFailure>().having(
        (value) => value.failure,
        'причина',
        isA<RelationGroupUnexpectedFailure>(),
      ),
    );
  });

  test('повтор первого чтения доступен только при недоступности', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    repository.failRead(0, const RelationGroupCorruptionFailure());
    await pumpEventQueue();
    harness.retryFirstPage();
    expect(repository.requestCount, 1);

    harness.viewModel.selectType(LongTermRelationType.can);
    repository.failRead(1, const RelationGroupUnavailableFailure());
    await pumpEventQueue();
    harness.retryFirstPage();

    expect(repository.requestCount, 3);
    expect(repository.queryAt(2).type, LongTermRelationType.can);
    expect(repository.queryAt(2).cursor, isNull);
  });

  test('ошибка первого чтения не подставляет строки прежней группы', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(index: 0, from: 1, count: 2, totalCount: 2);
    await pumpEventQueue();

    harness.viewModel.selectScope(RelationScope.archived);
    repository.failRead(1, const RelationGroupUnavailableFailure());
    await pumpEventQueue();

    expect(harness.state, isA<RelationGroupInitialFailure>());
    expect(harness.state, isNot(isA<RelationGroupConfirmedState>()));
  });

  test('исключение чтения даёт безопасный отказ без пустого списка', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    repository.throwOnRead(0, StateError('сбой хранилища'));
    await pumpEventQueue();

    expect(
      harness.state,
      isA<RelationGroupInitialFailure>().having(
        (value) => value.failure,
        'причина',
        isA<RelationGroupUnexpectedFailure>(),
      ),
    );
  });

  test('недопустимая полнота первой порции не публикуется', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    // Конец списка объявлен при неполной выдаче группы.
    harness.completeFirstPage(index: 0, from: 1, count: 2, totalCount: 5);
    await pumpEventQueue();

    expect(
      harness.state,
      isA<RelationGroupInitialFailure>().having(
        (value) => value.failure,
        'причина',
        isA<RelationGroupUnexpectedFailure>(),
      ),
    );
  });

  test('недопустимая полнота продолжения сохраняет прежние строки', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);

    repository.completePage(
      1,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.intentionId, from: 3, count: 1),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    expect(harness.loaded.items.length, 2);
    expect(harness.loaded.hasConfirmedEnd, isFalse);
    expect(
      harness.loaded.progress,
      isA<RelationGroupLoadMoreFailure>().having(
        (value) => value.failure,
        'причина',
        isA<RelationGroupUnexpectedFailure>(),
      ),
    );
  });

  test('строка чужой группы не становится выдачей выбранной', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    repository.completePage(
      0,
      RelationGroupFirstPage(
        items: [
          testGroupRow(
            ownerId: harness.intentionId,
            index: 1,
            type: LongTermRelationType.can,
          ),
        ],
        counts: testRelationCounts(activeNeedOutgoing: 1),
        nextCursor: null,
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();

    expect(
      harness.state,
      isA<RelationGroupInitialFailure>().having(
        (value) => value.failure,
        'причина',
        isA<RelationGroupUnexpectedFailure>(),
      ),
    );
  });

  test('устаревшее продолжение приводит к новой основе списка', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository, pageSize: 2);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);
    repository.completePage(
      1,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.intentionId, from: 3, count: 2),
        nextCursor: const TestRelationGroupCursor(4),
        revision: const TestGraphRevision(4),
      ),
    );
    await pumpEventQueue();
    expect(harness.relationIds.length, 4);

    harness.scrollTo(3);
    repository.failRead(2, const RelationGroupSnapshotExpired());
    await pumpEventQueue();

    // Прежняя пара остаётся доступной с состоянием обновления.
    expect(harness.loaded.progress, isA<RelationGroupRefreshing>());
    expect(harness.loaded.items.length, 4);
    expect(harness.loaded.totalCount, 5);
    expect(repository.requestCount, 4);
    expect(repository.queryAt(3).cursor, isNull);

    harness.completeFirstPage(
      index: 3,
      from: 1,
      count: 2,
      totalCount: 6,
      nextCursor: const TestRelationGroupCursor(2),
      revision: const TestGraphRevision(9),
    );
    await pumpEventQueue();
    expect(harness.loaded.items.length, 4);
    expect(harness.loaded.totalCount, 5);

    repository.completePage(
      4,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.intentionId, from: 3, count: 2),
        nextCursor: const TestRelationGroupCursor(4),
        revision: const TestGraphRevision(9),
      ),
    );
    await pumpEventQueue();
    repository.completePage(
      5,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.intentionId, from: 5, count: 2),
        nextCursor: null,
        revision: const TestGraphRevision(9),
      ),
    );
    await pumpEventQueue();

    // Замена публикуется целиком: прежний предел плюс запрошенная порция.
    expect(harness.relationIds.length, 6);
    expect(harness.loaded.totalCount, 6);
    expect(harness.loaded.hasConfirmedEnd, isTrue);
    expect(harness.loaded.progress, isA<RelationGroupIdle>());
    expect(repository.requestCount, 6);
  });

  test('порция другой ревизии не смешивается с загруженной частью', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);
    repository.completePage(
      1,
      RelationGroupContinuationPage(
        items: testGroupRows(ownerId: harness.intentionId, from: 3, count: 2),
        nextCursor: null,
        revision: const TestGraphRevision(9),
      ),
    );
    await pumpEventQueue();

    expect(harness.loaded.items.length, 2);
    expect(harness.loaded.progress, isA<RelationGroupRefreshing>());
    expect(repository.requestCount, 3);
    expect(repository.queryAt(2).cursor, isNull);
  });

  test('ошибка обновления сохраняет прежнюю подтверждённую пару', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);
    repository.failRead(1, const RelationGroupSnapshotExpired());
    await pumpEventQueue();
    repository.failRead(2, const RelationGroupUnavailableFailure());
    await pumpEventQueue();

    final loaded = harness.loaded;
    expect(loaded.items.length, 2);
    expect(loaded.totalCount, 5);
    expect(loaded.hasConfirmedEnd, isFalse);
    expect(
      loaded.progress,
      isA<RelationGroupRefreshFailure>().having(
        (value) => value.canRetry,
        'повтор доступен',
        true,
      ),
    );

    harness.retryRefresh();
    expect(repository.requestCount, 4);
    expect(repository.queryAt(3).cursor, isNull);
  });

  test('изменение графа во время сборки не даёт смешанный список', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository, pageSize: 2);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);
    repository.failRead(1, const RelationGroupSnapshotExpired());
    await pumpEventQueue();

    harness.completeFirstPage(
      index: 2,
      from: 1,
      count: 2,
      totalCount: 4,
      nextCursor: const TestRelationGroupCursor(2),
      revision: const TestGraphRevision(9),
    );
    await pumpEventQueue();
    repository.failRead(3, const RelationGroupSnapshotExpired());
    await pumpEventQueue();

    // Сборка начинается заново с первой порции, прежняя пара сохраняется.
    expect(harness.loaded.items.length, 2);
    expect(harness.loaded.totalCount, 5);
    expect(harness.loaded.progress, isA<RelationGroupRefreshing>());
    expect(repository.requestCount, 5);
    expect(repository.queryAt(4).cursor, isNull);

    harness.completeFirstPage(
      index: 4,
      from: 1,
      count: 2,
      totalCount: 2,
      revision: const TestGraphRevision(11),
    );
    await pumpEventQueue();

    expect(harness.relationIds.length, 2);
    expect(harness.loaded.totalCount, 2);
    expect(harness.loaded.hasConfirmedEnd, isTrue);
    expect(harness.loaded.progress, isA<RelationGroupIdle>());
  });

  test('обновление публикует подтверждённое отсутствие связей', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _NeighborhoodHarness(repository);
    addTearDown(harness.dispose);

    harness.completeFirstPage(
      index: 0,
      from: 1,
      count: 2,
      totalCount: 5,
      nextCursor: const TestRelationGroupCursor(2),
    );
    await pumpEventQueue();
    harness.scrollTo(1);
    repository.failRead(1, const RelationGroupSnapshotExpired());
    await pumpEventQueue();

    repository.completePage(
      2,
      RelationGroupFirstPage(
        items: const [],
        counts: testRelationCounts(),
        nextCursor: null,
        revision: const TestGraphRevision(9),
      ),
    );
    await pumpEventQueue();

    expect(harness.state, isA<RelationGroupEmpty>());
  });
}

final class _NeighborhoodHarness {
  _NeighborhoodHarness(
    this.repository, {
    int pageSize = 50,
    int? prefetchRemaining,
  }) : intentionId = testIntentionId(1) {
    _container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        relationNeighborhoodPagingPolicyProvider.overrideWithValue(
          RelationNeighborhoodPagingPolicy(
            pageSize: pageSize,
            prefetchRemaining: prefetchRemaining ?? pageSize - 1,
          ),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    _subscription = _container.listen(
      relationNeighborhoodViewModelProvider(intentionId),
      (_, _) {},
      fireImmediately: true,
    );
  }

  final ControlledNeighborhoodRepository repository;
  final IntentionId intentionId;
  late final ProviderContainer _container;
  late final ProviderSubscription<RelationNeighborhoodState> _subscription;

  RelationNeighborhoodViewModel get viewModel => _container.read(
    relationNeighborhoodViewModelProvider(intentionId).notifier,
  );

  RelationNeighborhoodState get state =>
      _container.read(relationNeighborhoodViewModelProvider(intentionId));

  RelationGroupLoaded get loaded => state as RelationGroupLoaded;

  List<LongTermRelationId> get relationIds => [
    for (final item in loaded.items) item.relation.id,
  ];

  /// Прокрутка не ожидает ответа: порция приходит по команде теста.
  void scrollTo(int visibleIndex) =>
      unawaited(viewModel.loadMoreIfNeeded(visibleIndex: visibleIndex));

  void retryFirstPage() => unawaited(viewModel.retryFirstPage());

  void retryLoadMore() => unawaited(viewModel.retryLoadMore());

  void retryRefresh() => unawaited(viewModel.retryRefresh());

  void completeFirstPage({
    required int index,
    required int from,
    required int count,
    required int totalCount,
    RelationGroupCursor? nextCursor,
    GraphRevision revision = const TestGraphRevision(4),
    LongTermRelationType type = LongTermRelationType.need,
    RelationDirection direction = RelationDirection.outgoing,
    RelationScope scope = RelationScope.active,
  }) {
    repository.completePage(
      index,
      RelationGroupFirstPage(
        items: testGroupRows(
          ownerId: intentionId,
          from: from,
          count: count,
          type: type,
          direction: direction,
          scope: scope,
        ),
        counts: testCountsForGroup(
          count: totalCount,
          type: type,
          direction: direction,
          scope: scope,
        ),
        nextCursor: nextCursor,
        revision: revision,
      ),
    );
  }

  void dispose() {
    _subscription.close();
    _container.dispose();
  }
}
