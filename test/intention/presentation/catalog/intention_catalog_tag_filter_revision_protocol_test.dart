import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

enum _PendingRead {
  firstPage('первая порция'),
  continuation('продолжение'),
  recovery('восстановление'),
  recoveryRetry('повтор восстановления');

  const _PendingRead(this.description);
  final String description;
}

enum _LateOutcome {
  success('успех'),
  unavailable('недоступность'),
  exception('исключение');

  const _LateOutcome(this.description);
  final String description;
}

void main() {
  test('поздняя первая порция не меняет границу новой выдачи', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      pageSize: 1,
      prefetchRemaining: 0,
    );
    final provider = intentionCatalogViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(container.dispose);
    addTearDown(subscription.close);
    final model = container.read(provider.notifier);
    final filter = IntentionTagFilter(requiredTagIds: [_tag(3).id]);
    model.changeTitleFilter('ходить');
    model.changeTagFilter(filter);
    await waitForCatalogQueries(repository, 2);
    final currentFirst = testSummary(
      index: 2,
      title: 'Ходить сейчас',
      tags: [_tag(3)],
    );
    final currentCursor = TestCatalogCursor();
    repository.complete(1, _firstPage(currentFirst, currentCursor));
    final current = await container.read(provider.future);
    repository.complete(
      0,
      _firstPage(testSummary(index: 4), const TestCatalogCursor()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).requireValue, same(current));

    final before = testSummary(index: 3, title: 'Читать', tags: [_tag(3)]);
    final after = testSummary(
      index: 3,
      title: 'Ходить в парк',
      tags: [_tag(3)],
    );
    await completeCatalogCommand(
      container,
      repository,
      UpdateIntention(id: after.id, title: after.title, description: null),
      IntentionSaved(
        testIntention(index: 3, title: after.title),
        catalogMutation: IntentionCatalogUpdated(
          revision: const TestCatalogRevision(1),
          before: TestCatalogEntrySnapshot(before),
          after: TestCatalogEntrySnapshot(after),
        ),
      ),
    );
    final loaded =
        container.read(provider).requireValue as IntentionCatalogLoaded;
    expect(loaded.items, [after, currentFirst]);
    expect(loaded.totalCount, 3);
    expect(loaded.nextCursor, same(currentCursor));
    expect(loaded.query.tagFilter, filter);
  });

  final original = IntentionTagFilter(
    requiredTagIds: [_tag(1).id],
    excludedTagIds: [_tag(4).id],
  );
  for (final (name, filter) in [
    (
      'обязательного',
      IntentionTagFilter(
        requiredTagIds: [_tag(3).id],
        excludedTagIds: [_tag(4).id],
      ),
    ),
    (
      'исключённого',
      IntentionTagFilter(
        requiredTagIds: [_tag(1).id],
        excludedTagIds: [_tag(2).id],
      ),
    ),
  ]) {
    for (final read in _PendingRead.values) {
      for (final outcome in _LateOutcome.values) {
        testWidgets(
          'замена $name тега во время debounce отвергает поздний ответ: '
          '${read.description}, ${outcome.description}',
          (tester) async {
            final repository = ControlledCatalogRepository();
            final container = reconciliationCatalogContainer(
              repository,
              pageSize: 1,
              prefetchRemaining: 0,
            );
            final provider = intentionCatalogViewModelProvider(
              const BrowseIntentionCatalog(),
            );
            final subscription = container.listen(provider, (_, _) {});
            addTearDown(container.dispose);
            addTearDown(subscription.close);
            repository.complete(0, _emptyPage());
            await tester.pump(Duration.zero);
            final model = container.read(provider.notifier);
            model.changeTagFilter(original);
            await tester.pump(Duration.zero);
            expect(repository.queries, hasLength(2));
            expect(repository.queryAt(1).tagFilter, original);

            const oldCursor = TestCatalogCursor();
            final oldFirst = testSummary(
              index: 4,
              title: 'Ходить прежде',
              tags: [_tag(1), _tag(2)],
            );
            final oldSecond = testSummary(
              index: 3,
              title: 'Ходить раньше',
              tags: [_tag(1), _tag(2)],
            );
            Future<void>? oldRequest;
            if (read != _PendingRead.firstPage) {
              repository.complete(1, _firstPage(oldFirst, oldCursor));
              await tester.pump(Duration.zero);
              final continuation = model.loadNextPageIfNeeded(visibleIndex: 0);
              await tester.pump(Duration.zero);
              expect(repository.queries, hasLength(3));
              if (read == _PendingRead.continuation) {
                oldRequest = continuation;
              } else {
                repository.complete(
                  2,
                  const ResultFailure(IntentionGenericValidationFailure()),
                );
                await tester.pump(Duration.zero);
                await continuation;
                final recovery = model.recoverFromInvalidCursor();
                await tester.pump(Duration.zero);
                expect(repository.queryAt(3).cursor, isNull);
                if (read == _PendingRead.recovery) {
                  oldRequest = recovery;
                } else {
                  repository.complete(
                    3,
                    const ResultFailure(IntentionUnavailableFailure()),
                  );
                  await tester.pump(Duration.zero);
                  await recovery;
                  oldRequest = model.retryRecovery();
                  await tester.pump(Duration.zero);
                  expect(repository.queryAt(4).cursor, isNull);
                }
              }
            }
            final oldIndex = repository.queries.length - 1;
            expect(repository.queryAt(oldIndex).tagFilter, original);
            expect(
              repository.queryAt(oldIndex).cursor,
              read == _PendingRead.continuation ? same(oldCursor) : isNull,
            );

            model.changeTitleFilter('ходить');
            await tester.pump(const Duration(milliseconds: 100));
            expect(
              container.read(provider).requireValue,
              isA<IntentionCatalogDebouncing>(),
            );
            expect(repository.queries, hasLength(oldIndex + 1));
            model.changeTagFilter(filter);
            await tester.pump(Duration.zero);
            final newIndex = oldIndex + 1;
            expect(repository.queries, hasLength(newIndex + 1));
            expect(repository.queryAt(newIndex).cursor, isNull);
            expect(repository.queryAt(newIndex).tagFilter, filter);
            expect(
              repository.queryAt(newIndex).titleFilter?.map((text) => text),
              'ходить',
            );

            // Новый запрос имеет продолжение, чтобы поздний finally прежнего
            // чтения не мог снять блокировку параллельной подгрузки.
            final newCursor = TestCatalogCursor();
            final newFirst = testSummary(
              index: 2,
              title: 'Ходить теперь',
              tags: [_tag(1), _tag(3)],
            );
            final newSecond = testSummary(
              index: 1,
              title: 'Ходить сейчас',
              tags: [_tag(1), _tag(3)],
            );
            expect(repository.queryAt(newIndex).includes(oldFirst), isFalse);
            expect(repository.queryAt(newIndex).includes(newFirst), isTrue);
            repository.complete(newIndex, _firstPage(newFirst, newCursor));
            await tester.pump(Duration.zero);
            final newRequest = model.loadNextPageIfNeeded(visibleIndex: 0);
            await tester.pump(Duration.zero);
            final current = container.read(provider).requireValue;
            expect(
              current,
              isA<IntentionCatalogLoaded>().having(
                (state) => state.continuation,
                'подгрузка',
                isA<IntentionCatalogContinuationLoading>(),
              ),
            );
            final requestCount = repository.queries.length;
            switch (outcome) {
              case _LateOutcome.success:
                repository.complete(
                  oldIndex,
                  read == _PendingRead.continuation
                      ? _continuationPage(oldSecond)
                      : _firstPage(oldFirst, oldCursor),
                );
              case _LateOutcome.unavailable:
                repository.complete(
                  oldIndex,
                  const ResultFailure(IntentionUnavailableFailure()),
                );
              case _LateOutcome.exception:
                repository.failPage(oldIndex, StateError('Поздний отказ.'));
            }
            await tester.pump(Duration.zero);
            if (oldRequest != null) await oldRequest;
            expect(container.read(provider).requireValue, same(current));
            await model.loadNextPageIfNeeded(visibleIndex: 0);
            expect(repository.queries, hasLength(requestCount));
            expect(repository.queryAt(newIndex + 1).cursor, same(newCursor));
            expect(repository.queryAt(newIndex + 1).tagFilter, filter);

            repository.complete(newIndex + 1, _continuationPage(newSecond));
            await tester.pump(Duration.zero);
            await newRequest;
            final loaded =
                container.read(provider).requireValue as IntentionCatalogLoaded;
            expect(loaded.items, [newFirst, newSecond]);
            expect(loaded.totalCount, 2);
            expect(loaded.query.tagFilter, filter);
            expect(loaded.nextCursor, isNull);
            expect(
              loaded.continuation,
              isA<IntentionCatalogContinuationIdle>(),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(repository.queries, hasLength(requestCount));
          },
        );
      }
    }
  }

  group('согласование после удаления исключённого тега', () {
    final health = _tag(1);
    final rest = _tag(2);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );

    test('новая ревизия между порциями оставляет кандидата неопубликованным '
        'и повторяет получение для неё', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(
        repository,
        pageSize: 2,
        prefetchRemaining: 0,
      );
      final published = _observePublished(container);
      final tenth = testSummary(index: 10, tags: [health]);
      final eighth = testSummary(index: 8, tags: [health]);
      final before = await _loadCompleted(container, repository, filter, [
        tenth,
        eighth,
      ]);
      published.clear();

      await _completeTagDelete(container, repository, rest.id, revision: 2);
      await waitForReconciliationQueries(repository, 1);
      final twelfth = testSummary(index: 12, tags: [health]);
      final eleventh = testSummary(index: 11, tags: [health]);
      repository.completeReconciliation(
        0,
        _reconciliationFirst(
          [twelfth, eleventh],
          totalCount: 5,
          nextCursor: const TestReconciliationCursor(),
          revision: 2,
        ),
      );
      await waitForReconciliationQueries(repository, 2);
      // Продолжение отражает уже следующую ревизию: смесь ревизий не
      // публикуется, чтение ждёт её подтверждённый пакет.
      repository.completeReconciliation(
        1,
        _reconciliationContinuation([
          testSummary(index: 9, tags: [health]),
        ], revision: 3),
      );
      await Future<void>.delayed(Duration.zero);
      expect(published, isEmpty);
      expect(repository.reconciliationQueries, hasLength(2));

      await completeIntentionTagAssignment(
        container,
        repository,
        state: TagAssignmentState.absent,
        tagId: health.id,
        before: tenth,
        after: testSummary(index: 10),
        revision: const TestCatalogRevision(3),
      );
      await waitForReconciliationQueries(repository, 3);
      final repeated = repository.reconciliationQueryAt(2);
      expect(repeated.catalogQuery, same(before.query));
      expect(repeated.boundary, isA<IntentionCatalogCompletedBoundary>());
      expect(repeated.window.storedIntentionIds, [eighth.id]);
      expect(repeated.cursor, isNull);
      expect(published, isEmpty);

      final ninth = testSummary(index: 9, tags: [health]);
      repository.completeReconciliation(
        2,
        _reconciliationFirst(
          [twelfth, eleventh],
          totalCount: 4,
          nextCursor: const TestReconciliationCursor(),
          revision: 3,
        ),
      );
      await waitForReconciliationQueries(repository, 4);
      expect(repository.reconciliationQueryAt(3).cursor, isNotNull);
      repository.completeReconciliation(
        3,
        _reconciliationContinuation([ninth], revision: 3),
      );
      await Future<void>.delayed(Duration.zero);

      final current = _currentLoaded(container);
      expect(current.items.map((item) => item.id), [
        twelfth.id,
        eleventh.id,
        ninth.id,
        eighth.id,
      ]);
      expect(current.totalCount, 4);
      expect(current.revision, _revision(3));
      expect(current.refresh, isA<IntentionCatalogRefreshIdle>());
      expect(current.query, same(before.query));
      expect(published, [same(current)]);
      expect(repository.queries, hasLength(2));
    });

    for (final responseFirst in [false, true]) {
      test(
        responseFirst
            ? 'ответ более новой ревизии до её пакета не применяет пакет дважды'
            : 'пакет во время чтения применяется к кандидату один раз',
        () async {
          final repository = ControlledCatalogRepository();
          final container = reconciliationCatalogContainer(repository);
          final published = _observePublished(container);
          final tenth = testSummary(index: 10, tags: [health]);
          final eighth = testSummary(index: 8, tags: [health]);
          final before = await _loadCompleted(container, repository, filter, [
            tenth,
            eighth,
          ]);
          published.clear();

          await _completeTagDelete(container, repository, rest.id, revision: 2);
          await waitForReconciliationQueries(repository, 1);
          final ninth = testSummary(index: 9, tags: [health]);
          final seventh = testSummary(index: 7, tags: [health]);
          Future<void> assignSeventh() => completeIntentionTagAssignment(
            container,
            repository,
            state: TagAssignmentState.assigned,
            tagId: health.id,
            before: testSummary(index: 7),
            after: seventh,
            revision: const TestCatalogRevision(3),
          );

          if (responseFirst) {
            repository.completeReconciliation(
              0,
              _reconciliationFirst(
                [ninth, seventh],
                totalCount: 4,
                revision: 3,
              ),
            );
            await Future<void>.delayed(Duration.zero);
            expect(published, isEmpty);
            expect(repository.reconciliationQueries, hasLength(1));
            await assignSeventh();
            await waitForReconciliationQueries(repository, 2);
            final repeated = repository.reconciliationQueryAt(1);
            expect(repeated.catalogQuery, same(before.query));
            expect(repeated.window.storedIntentionIds, [
              tenth.id,
              eighth.id,
              seventh.id,
            ]);
            expect(published, isEmpty);
            repository.completeReconciliation(
              1,
              _reconciliationFirst([ninth], totalCount: 4, revision: 3),
            );
          } else {
            await assignSeventh();
            expect(published, isEmpty);
            expect(repository.reconciliationQueries, hasLength(1));
            repository.completeReconciliation(
              0,
              _reconciliationFirst([ninth], totalCount: 3, revision: 2),
            );
          }
          await Future<void>.delayed(Duration.zero);

          final current = _currentLoaded(container);
          expect(current.items.map((item) => item.id), [
            tenth.id,
            ninth.id,
            eighth.id,
            seventh.id,
          ]);
          expect(current.totalCount, 4);
          expect(current.revision, _revision(3));
          expect(current.query, same(before.query));
          expect(published, [same(current)]);
          expect(
            repository.reconciliationQueries,
            hasLength(responseFirst ? 2 : 1),
          );
          expect(repository.queries, hasLength(2));
        },
      );
    }

    test('запоздалое чтение старой ревизии не возвращает удалённый тег и '
        'прежнее количество', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final published = _observePublished(container);
      final tenth = testSummary(index: 10, tags: [health]);
      final before = await _loadCompleted(container, repository, filter, [
        tenth,
      ]);
      published.clear();

      await _completeTagDelete(container, repository, rest.id, revision: 2);
      await waitForReconciliationQueries(repository, 1);
      repository.completeReconciliation(
        0,
        _reconciliationFirst(
          [
            testSummary(index: 9, tags: [health, rest]),
          ],
          totalCount: 1,
          revision: 1,
        ),
      );
      await waitForReconciliationQueries(repository, 2);
      expect(published, isEmpty);
      final repeated = repository.reconciliationQueryAt(1);
      expect(repeated.catalogQuery, same(before.query));
      expect(repeated.window.storedIntentionIds, [tenth.id]);
      expect(repeated.cursor, isNull);

      final ninth = testSummary(index: 9, tags: [health]);
      repository.completeReconciliation(
        1,
        _reconciliationFirst([ninth], totalCount: 2, revision: 2),
      );
      await Future<void>.delayed(Duration.zero);

      final current = _currentLoaded(container);
      expect(current.items.map((item) => item.id), [tenth.id, ninth.id]);
      for (final item in current.items) {
        expect(item.tags.map((tag) => tag.id), [health.id]);
      }
      expect(current.totalCount, 2);
      expect(current.revision, _revision(2));
      expect(published, [same(current)]);
    });

    test('непрерывные изменения задерживают публикацию, но опубликованное '
        'содержимое остаётся подтверждённым', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final published = _observePublished(container);
      final tenth = testSummary(index: 10, tags: [health]);
      final before = await _loadCompleted(container, repository, filter, [
        tenth,
      ]);
      published.clear();

      await _completeTagDelete(container, repository, rest.id, revision: 2);
      for (var revision = 3; revision <= 5; revision++) {
        final index = revision - 3;
        await waitForReconciliationQueries(repository, index + 1);
        repository.completeReconciliation(
          index,
          _reconciliationFirst([], totalCount: 1, revision: revision),
        );
        await Future<void>.delayed(Duration.zero);
        expect(published, isEmpty);
        expect(container.read(_provider).requireValue, same(before));
        await _completeTagRename(
          container,
          repository,
          health,
          revision: revision,
        );
      }
      await waitForReconciliationQueries(repository, 4);
      repository.completeReconciliation(
        3,
        _reconciliationFirst([], totalCount: 1, revision: 5),
      );
      await Future<void>.delayed(Duration.zero);

      final current = _currentLoaded(container);
      expect(current.items.map((item) => item.id), [tenth.id]);
      expect(current.items.single.tags.single.name.value, 'Тег 1 (5)');
      expect(current.totalCount, 1);
      expect(current.revision, _revision(5));
      expect(published, [same(current)]);
    });
  });

  group('полное создание во время чтения выдачи', () {
    final health = _tag(1);
    final sport = _tag(2);
    final rest = _tag(3);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [sport.id],
    );
    final created = testSummary(
      index: 9,
      title: 'Ходить в лес',
      readiness: IntentionReadiness.ready,
      tags: [health, rest],
      favoriteMark: FavoriteMark.favorite,
    );

    for (final (name, pageRevision, packageFirst) in [
      ('пакет до ответа прежней ревизии', 1, true),
      ('пакет до ответа, уже отражающего создание', 2, true),
      ('ответ, уже отражающий создание, до пакета', 2, false),
    ]) {
      test('первая порция и пакет создания согласуются без повторной строки '
          'и отката: $name', () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(repository);
        final subscription = container.listen(_provider, (_, _) {});
        addTearDown(container.dispose);
        addTearDown(subscription.close);
        final model = container.read(_provider.notifier);
        model.changeTitleFilter('ходить');
        model.changeTagFilter(filter);
        await waitForCatalogQueries(repository, 2);
        final older = testSummary(
          index: 3,
          title: 'Ходить в парк',
          tags: [health],
        );
        final reflectsCreation = pageRevision == 2;
        final Result<IntentionCatalogPage> page = ResultSuccess(
          IntentionCatalogFirstPage(
            items: reflectsCreation ? [created, older] : [older],
            totalCount: reflectsCreation ? 2 : 1,
            nextCursor: null,
            revision: TestCatalogRevision(pageRevision),
          ),
        );

        IntentionCatalogState? loadedBeforePackage;
        if (packageFirst) {
          await completeFullCreation(
            container,
            repository,
            created,
            revision: const TestCatalogRevision(2),
          );
          repository.complete(1, page);
        } else {
          repository.complete(1, page);
          loadedBeforePackage = await container.read(_provider.future);
          await completeFullCreation(
            container,
            repository,
            created,
            revision: const TestCatalogRevision(2),
          );
        }

        final current = await container.read(_provider.future);
        expect(current, isA<IntentionCatalogLoaded>());
        final loaded = current as IntentionCatalogLoaded;
        expect(loaded.items, [created, older]);
        expect(loaded.totalCount, 2);
        expect(loaded.nextCursor, isNull);
        expect(loaded.revision, _revision(2));
        expect(loaded.query.tagFilter, filter);
        expect(loaded.query.titleFilter?.map((text) => text), 'ходить');
        if (loadedBeforePackage != null) {
          expect(loaded, same(loadedBeforePackage));
        }
        expect(repository.queries, hasLength(2));
      });
    }

    for (final (name, continuationRevision, packageFirst) in [
      ('пакет во время продолжения прежней ревизии', 1, true),
      ('пакет до продолжения, уже отражающего создание', 2, true),
      ('продолжение, уже отражающее создание, до пакета', 2, false),
    ]) {
      test('созданное намерение за границей загруженной области учитывается '
          'количеством и приходит с продолжением один раз: $name', () async {
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(
          repository,
          pageSize: 2,
          prefetchRemaining: 0,
        );
        final subscription = container.listen(_provider, (_, _) {});
        addTearDown(container.dispose);
        addTearDown(subscription.close);
        final model = container.read(_provider.notifier);
        model.changeOrder(IntentionCatalogOrder.createdAtAscending);
        model.changeTagFilter(filter);
        await waitForCatalogQueries(repository, 2);
        expect(
          repository.queryAt(1).order,
          IntentionCatalogOrder.createdAtAscending,
        );
        const cursor = TestCatalogCursor();
        final first = testSummary(index: 1, tags: [health]);
        final second = testSummary(index: 2, tags: [health]);
        final third = testSummary(index: 3, tags: [health]);
        repository.complete(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: [first, second],
              totalCount: 3,
              nextCursor: cursor,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
        final loaded =
            await container.read(_provider.future) as IntentionCatalogLoaded;
        final continuation = model.loadNextPageIfNeeded(visibleIndex: 1);
        await waitForCatalogQueries(repository, 3);
        expect(repository.queryAt(2).cursor, same(cursor));
        final Result<IntentionCatalogPage> reflectingCreation = ResultSuccess(
          IntentionCatalogContinuationPage(
            items: [third, created],
            nextCursor: null,
            revision: const TestCatalogRevision(2),
          ),
        );

        if (packageFirst) {
          await completeFullCreation(
            container,
            repository,
            created,
            revision: const TestCatalogRevision(2),
          );
          final counted = _currentLoaded(container);
          expect(counted.items, [first, second]);
          expect(counted.totalCount, 4);
          expect(
            counted.continuation,
            isA<IntentionCatalogContinuationLoading>(),
          );
          if (continuationRevision == 1) {
            repository.complete(
              2,
              ResultSuccess(
                IntentionCatalogContinuationPage(
                  items: [third],
                  nextCursor: null,
                  revision: const TestCatalogRevision(1),
                ),
              ),
            );
            await waitForCatalogQueries(repository, 4);
            expect(repository.queryAt(3).cursor, same(cursor));
            repository.complete(3, reflectingCreation);
          } else {
            repository.complete(2, reflectingCreation);
          }
        } else {
          repository.complete(2, reflectingCreation);
          await Future<void>.delayed(Duration.zero);
          final pending = _currentLoaded(container);
          expect(pending.items, [first, second]);
          expect(pending.totalCount, 3);
          expect(
            pending.continuation,
            isA<IntentionCatalogContinuationLoading>(),
          );
          await completeFullCreation(
            container,
            repository,
            created,
            revision: const TestCatalogRevision(2),
          );
        }
        await continuation;

        final current = _currentLoaded(container);
        expect(current.items, [first, second, third, created]);
        expect(current.totalCount, 4);
        expect(current.nextCursor, isNull);
        expect(current.revision, _revision(2));
        expect(current.query, same(loaded.query));
        expect(current.continuation, isA<IntentionCatalogContinuationIdle>());
        expect(
          repository.queries,
          hasLength(continuationRevision == 1 ? 4 : 3),
        );
      });
    }

    test('пакет создания во время согласования области применяется к '
        'кандидату одним изменением ревизии', () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      final published = _observePublished(container);
      final tenth = testSummary(index: 10, tags: [health]);
      final before = await _loadCompleted(container, repository, filter, [
        tenth,
      ]);
      published.clear();

      await _completeTagDelete(container, repository, sport.id, revision: 2);
      await waitForReconciliationQueries(repository, 1);
      final createdAfterDeletion = testSummary(
        index: 11,
        title: 'Ходить в лес',
        readiness: IntentionReadiness.ready,
        tags: [health, rest],
        favoriteMark: FavoriteMark.favorite,
      );
      await completeFullCreation(
        container,
        repository,
        createdAfterDeletion,
        revision: const TestCatalogRevision(3),
      );
      expect(published, isEmpty);
      expect(container.read(_provider).requireValue, same(before));

      final ninth = testSummary(index: 9, tags: [health]);
      repository.completeReconciliation(
        0,
        _reconciliationFirst([ninth], totalCount: 2, revision: 2),
      );
      await Future<void>.delayed(Duration.zero);

      final current = _currentLoaded(container);
      expect(current.items, [createdAfterDeletion, tenth, ninth]);
      expect(current.totalCount, 3);
      expect(current.revision, _revision(3));
      expect(current.refresh, isA<IntentionCatalogRefreshIdle>());
      expect(current.query, same(before.query));
      expect(published, [same(current)]);
      expect(repository.reconciliationQueries, hasLength(1));
      expect(repository.queries, hasLength(2));
    });
  });
}

Result<IntentionCatalogPage> _emptyPage() => ResultSuccess(
  IntentionCatalogFirstPage(
    items: const [],
    totalCount: 0,
    nextCursor: null,
    revision: const TestCatalogRevision(0),
  ),
);

Result<IntentionCatalogPage> _firstPage(
  IntentionSummary item,
  IntentionCatalogCursor cursor,
) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: [item],
    totalCount: 2,
    nextCursor: cursor,
    revision: const TestCatalogRevision(0),
  ),
);

Result<IntentionCatalogPage> _continuationPage(IntentionSummary item) =>
    ResultSuccess(
      IntentionCatalogContinuationPage(
        items: [item],
        nextCursor: null,
        revision: const TestCatalogRevision(0),
      ),
    );

Tag _tag(int number) => Tag(
  id: switch (TagId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  )) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError('Неверный ID тега.'),
  },
  name: TagName.fromInput('Тег $number'),
);

const _browse = BrowseIntentionCatalog();
final _provider = intentionCatalogViewModelProvider(_browse);

/// Загружает полностью завершённую выдачу с условиями по тегам.
Future<IntentionCatalogLoaded> _loadCompleted(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  IntentionTagFilter filter,
  List<IntentionSummary> items,
) async {
  await waitForCatalogQueries(repository, 1);
  repository.complete(0, _emptyPage());
  await container.read(_provider.future);
  container.read(_provider.notifier).changeTagFilter(filter);
  await waitForCatalogQueries(repository, 2);
  repository.complete(
    1,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: items,
        totalCount: items.length,
        nextCursor: null,
        revision: const TestCatalogRevision(1),
      ),
    ),
  );
  return await container.read(_provider.future) as IntentionCatalogLoaded;
}

/// Собирает подтверждённые состояния, опубликованные после подписки.
List<IntentionCatalogConfirmedState> _observePublished(
  ProviderContainer container,
) {
  final published = <IntentionCatalogConfirmedState>[];
  final subscription = container.listen(_provider, (_, next) {
    if (next.value case final IntentionCatalogConfirmedState confirmed) {
      published.add(confirmed);
    }
  });
  addTearDown(container.dispose);
  addTearDown(subscription.close);
  return published;
}

IntentionCatalogLoaded _currentLoaded(ProviderContainer container) =>
    container.read(_provider).requireValue as IntentionCatalogLoaded;

Result<IntentionCatalogReconciliationOutcome> _reconciliationFirst(
  List<IntentionSummary> items, {
  required int totalCount,
  IntentionCatalogReconciliationCursor? nextCursor,
  required int revision,
}) => ResultSuccess(
  IntentionCatalogReconciliationFirstPortion(
    items: items,
    totalCount: totalCount,
    nextCursor: nextCursor,
    revision: TestCatalogRevision(revision),
  ),
);

Result<IntentionCatalogReconciliationOutcome> _reconciliationContinuation(
  List<IntentionSummary> items, {
  required int revision,
}) => ResultSuccess(
  IntentionCatalogReconciliationContinuationPortion(
    items: items,
    nextCursor: null,
    revision: TestCatalogRevision(revision),
  ),
);

Future<void> _completeTagDelete(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  TagId tagId, {
  required int revision,
}) async {
  final graphRevision = TestCatalogRevision(revision);
  await completeTagCommand(
    container,
    repository,
    DeleteTag(tagId),
    TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: graphRevision,
        value: TagDeleted(
          TagDeletedChange(revision: graphRevision, tagId: tagId),
        ),
      ),
    ),
  );
}

/// Переименовывает тег в «<прежнее название> (<ревизия>)».
Future<void> _completeTagRename(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  Tag tag, {
  required int revision,
}) async {
  final graphRevision = TestCatalogRevision(revision);
  final after = Tag(
    id: tag.id,
    name: TagName.fromInput('${tag.name.value} ($revision)'),
  );
  await completeTagCommand(
    container,
    repository,
    RenameTag(tagId: tag.id, name: after.name),
    TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: graphRevision,
        value: TagRenamed(
          TagRenamedChange(revision: graphRevision, before: tag, after: after),
        ),
      ),
    ),
  );
}

Matcher _revision(int sequence) => isA<TestCatalogRevision>().having(
  (revision) => revision.sequence,
  'sequence',
  sequence,
);
