import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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
