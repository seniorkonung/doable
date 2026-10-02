import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_status_views.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_search_results.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

const _purpose = BrowseIntentionCatalog();
const _listKey = PageStorageKey<String>('search-results-test-list');

const _loadingRu = 'Загружаем намерения…';
const _unavailableRu = 'Не удалось загрузить намерения. Повторите попытку.';
const _emptyRu = 'Активных намерений пока нет.';
const _refreshUnavailableRu =
    'Список намерений не обновлён: не удалось получить изменения.';
const _refreshCorruptionRu =
    'Список намерений не обновлён: сохранённые данные повреждены.';
const _refreshUnexpectedRu =
    'Список намерений не обновлён из-за непредвиденной ошибки.';

/// Высота строки-образца выдачи.
const _rowExtent = 48.0;

final _list = find.byKey(_listKey);
final _refreshStatus = find.byType(IntentionCatalogRefreshStatusView);
final _refreshRetry = find.descendant(
  of: _refreshStatus,
  matching: find.byType(FilledButton),
);

final _star = find.byIcon(Icons.star);

Finder _row(int index) => find.byKey(ValueKey(testSummary(index: index).id));

final _health = _tag(1, 'Здоровье');
final _sport = _tag(2, 'Спорт');
final _other = _tag(3, 'Отдых');

/// Отказы обновления трёх категорий с их сообщениями.
final _refreshFailures = <(String, IntentionFailure, String)>[
  ('недоступности', const IntentionUnavailableFailure(), _refreshUnavailableRu),
  ('повреждения', const IntentionCorruptionFailure(), _refreshCorruptionRu),
  (
    'неожиданной ошибки',
    const IntentionUnexpectedFailure(),
    _refreshUnexpectedRu,
  ),
];

void main() {
  group('отказ обновления над загруженным списком', () {
    for (final (name, failure, message) in _refreshFailures) {
      testWidgets('появление и снятие отказа из-за $name не меняют смещение '
          'и экранное положение строки прокрученного списка', (tester) async {
        final h = await _open(tester);
        await h.load(_summaries(first: 40));
        h.position.jumpTo(300);
        await _settle(tester);
        final rowTop = _rowTop(tester, 'Намерение 33');

        await h.failRefresh(failure);

        expect(find.text(message), findsOneWidget);
        expect(
          _refreshRetry,
          failure is IntentionUnavailableFailure
              ? findsOneWidget
              : findsNothing,
        );
        expect(h.position.pixels, 300);
        expect(_rowTop(tester, 'Намерение 33'), rowTop);
        // Отказ лежит поверх верхнего края списка и не сжимает его область.
        expect(
          tester.getRect(_refreshStatus).top,
          moreOrLessEquals(tester.getRect(_list).top, epsilon: 0.01),
        );

        await h.recoverRefresh(totalCount: 40);

        expect(find.text(message), findsNothing);
        expect(h.position.pixels, 300);
        expect(_rowTop(tester, 'Намерение 33'), rowTop);
      });
    }

    for (final (name, count) in [
      ('прокручиваемый', 40),
      ('помещающийся на экране', 2),
    ]) {
      testWidgets('$name список, стоявший в начале, остаётся в начале: строки '
          'уходят из-под отказа и возвращаются после снятия', (tester) async {
        final h = await _open(tester);
        await h.load(_summaries(first: count));
        final first = 'Намерение $count';
        final listTop = tester.getRect(_list).top;
        expect(_rowTop(tester, first), moreOrLessEquals(listTop));

        await h.failRefresh(const IntentionUnavailableFailure());

        expect(tester.takeException(), isNull);
        expect(find.text(_refreshUnavailableRu), findsOneWidget);
        expect(
          _rowTop(tester, first),
          moreOrLessEquals(
            tester.getRect(_refreshStatus).bottom,
            epsilon: 0.01,
          ),
        );

        await h.recoverRefresh(totalCount: count);

        expect(tester.takeException(), isNull);
        expect(find.text(_refreshUnavailableRu), findsNothing);
        expect(_rowTop(tester, first), moreOrLessEquals(listTop));
      });
    }

    testWidgets('первая строка прокрученного списка достижима прокруткой под '
        'отказом', (tester) async {
      final h = await _open(tester);
      await h.load(_summaries(first: 40));
      h.position.jumpTo(300);
      await _settle(tester);
      await h.failRefresh(const IntentionCorruptionFailure());

      await tester.drag(_list, const Offset(0, 5000));
      await tester.pumpAndSettle();

      expect(
        _rowTop(tester, 'Намерение 40'),
        moreOrLessEquals(tester.getRect(_refreshStatus).bottom, epsilon: 0.01),
      );
    });
  });

  group('пустая выдача', () {
    testWidgets('без отказа обновления выводит только сообщение о пустоте', (
      tester,
    ) async {
      final h = await _open(tester);
      await h.load(const []);

      expect(h.confirmed, isA<IntentionCatalogEmpty>());
      expect(find.text(_emptyRu), findsOneWidget);
      expect(tester.getSize(_refreshStatus).height, 0);
      expect(
        find.descendant(of: _refreshStatus, matching: find.byType(Text)),
        findsNothing,
      );
    });

    for (final (name, failure, message) in _refreshFailures) {
      testWidgets('отказ обновления из-за $name стоит над сообщением о '
          'пустоте', (tester) async {
        final h = await _open(tester);
        await h.load(const []);

        await h.failRefresh(failure);

        expect(h.confirmed, isA<IntentionCatalogEmpty>());
        expect(find.text(message), findsOneWidget);
        expect(find.text(_emptyRu), findsOneWidget);
        expect(
          _refreshRetry,
          failure is IntentionUnavailableFailure
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          tester.getRect(_refreshStatus).bottom,
          lessThanOrEqualTo(tester.getRect(find.text(_emptyRu)).top),
        );
      });
    }
  });

  group('верхняя позиция при смене параметров', () {
    for (final (name, change) in <(String, void Function(_Harness))>[
      (
        'условий по тегам',
        (h) => h.notifier.changeTagFilter(IntentionTagFilter.empty),
      ),
      ('текста названия', (h) => h.notifier.changeTitleFilter('намерение')),
      ('охвата', (h) => h.notifier.changeScope(IntentionScope.archived)),
      (
        'порядка',
        (h) => h.notifier.changeOrder(IntentionCatalogOrder.createdAtAscending),
      ),
    ]) {
      testWidgets('смена $name при показанном прокрученном списке открывает '
          'выдачу со смещением ноль', (tester) async {
        final h = await _open(tester);
        await h.load(_summaries(first: 40));
        h.position.jumpTo(300);
        await _settle(tester);

        await h.changeParameters(change, _summaries(first: 40));

        expect(h.position.pixels, 0);
        expect(
          _rowTop(tester, 'Намерение 40'),
          moreOrLessEquals(tester.getRect(_list).top),
        );
      });

      testWidgets('смена $name при списке, снятом с экрана пустой выдачей, '
          'открывает выдачу со смещением ноль', (tester) async {
        final h = await _open(tester);
        await h.load(_summaries(first: 40));
        h.position.jumpTo(300);
        await _settle(tester);
        // Удаление обязательного тега снимает список с экрана без смены
        // параметров поиска.
        await h.deleteTag(_health);
        expect(_list, findsNothing);
        expect(find.text(_emptyRu), findsOneWidget);

        await h.changeParameters(change, _summaries(first: 40));

        expect(h.position.pixels, 0);
        expect(
          _rowTop(tester, 'Намерение 40'),
          moreOrLessEquals(tester.getRect(_list).top),
        );
      });

      testWidgets('первая после монтирования на уже загруженную выдачу смена '
          '$name открывает выдачу со смещением ноль', (tester) async {
        final h = await _open(tester, loadedBeforeMount: _summaries(first: 40));
        h.position.jumpTo(300);
        await _settle(tester);

        await h.changeParameters(change, _summaries(first: 40));

        expect(h.position.pixels, 0);
        expect(
          _rowTop(tester, 'Намерение 40'),
          moreOrLessEquals(tester.getRect(_list).top),
        );
      });
    }

    testWidgets('выдача, вернувшаяся после временной пустоты без смены '
        'параметров, сохраняет позицию', (tester) async {
      final h = await _open(tester);
      await h.load(_summaries(first: 40));
      h.position.jumpTo(300);
      await _settle(tester);
      await h.deleteTag(_health);
      expect(_list, findsNothing);

      // Согласование после удаления исключённого тега возвращает совпадения
      // без смены параметров.
      await h.deleteTag(_sport);
      h.repository.completeReconciliation(
        0,
        reconciliationFirstPortion(
          _summaries(first: 40, tags: const []),
          totalCount: 40,
          revision: h.revision,
        ),
      );
      await tester.pumpAndSettle();

      expect(h.position.pixels, 300);
    });
  });

  group('отличия каталога заданы параметрами', () {
    Future<_Harness> insertBeforeVisible(
      WidgetTester tester,
      IntentionSearchResultsViewAnchor viewAnchor,
    ) async {
      final h = await _open(tester, viewAnchor: viewAnchor);
      await h.load(_summaries(first: 60, step: 2));
      h.position.jumpTo(300);
      await _settle(tester);
      // Назначение обязательного тега добавляет строку перед видимой.
      final (command, result) = intentionTagAssignment(
        state: TagAssignmentState.assigned,
        tagId: _health.id,
        before: testSummary(index: 59, title: 'Намерение 59'),
        after: testSummary(index: 59, title: 'Намерение 59', tags: [_health]),
        revision: TestCatalogRevision(++h.revision),
      );
      await h.complete(command, result);
      expect((h.confirmed as IntentionCatalogLoaded).items, hasLength(31));
      return h;
    }

    testWidgets('якорь видимого намерения сохраняет его экранное положение '
        'при строке, добавленной перед ним', (tester) async {
      final h = await insertBeforeVisible(
        tester,
        IntentionSearchResultsViewAnchor.visibleIntention,
      );

      expect(h.position.pixels, 300 + _rowExtent);
    });

    testWidgets('без якоря согласование сохраняет смещение прокрутки', (
      tester,
    ) async {
      final h = await insertBeforeVisible(
        tester,
        IntentionSearchResultsViewAnchor.scrollOffset,
      );

      expect(h.position.pixels, 300);
    });

    testWidgets('место под кнопку страницы отводится после конца выдачи', (
      tester,
    ) async {
      final h = await _open(tester, trailingInset: 88);
      await h.load(_summaries(first: 40));

      h.position.jumpTo(h.position.maxScrollExtent);
      await _settle(tester);

      expect(
        tester.getRect(find.text('Намерение 1')).bottom,
        moreOrLessEquals(tester.getRect(_list).bottom - 88, epsilon: 0.01),
      );
    });
  });

  group('отметка избранного', () {
    for (final viewAnchor in IntentionSearchResultsViewAnchor.values) {
      testWidgets('подтверждённые отметка и её снятие меняют только звезду '
          'видимой строки прокрученного списка (${viewAnchor.name})', (
        tester,
      ) async {
        final h = await _open(tester, viewAnchor: viewAnchor);
        await h.load(_summaries(first: 40));
        h.position.jumpTo(300);
        await _settle(tester);
        final rowTops = {
          for (final index in [34, 33, 32])
            index: _rowTop(tester, 'Намерение $index'),
        };
        final before = h.confirmed as IntentionCatalogLoaded;
        expect(_star, findsNothing);

        for (final mark in [FavoriteMark.favorite, FavoriteMark.notFavorite]) {
          await h.confirmMark(33, mark);

          expect(
            find.descendant(of: _row(33), matching: _star),
            mark == FavoriteMark.favorite ? findsOneWidget : findsNothing,
          );
          expect(
            _star.evaluate().length,
            mark == FavoriteMark.favorite ? 1 : 0,
          );
          expect(h.position.pixels, 300);
          for (final MapEntry(key: index, value: top) in rowTops.entries) {
            expect(_rowTop(tester, 'Намерение $index'), top);
          }
          final current = h.confirmed as IntentionCatalogLoaded;
          expect(
            current.items.map((item) => item.id),
            before.items.map((item) => item.id),
          );
          expect(current.totalCount, 40);
          expect(find.text('Всего намерений: 40'), findsOneWidget);
          expect(tester.getSize(_refreshStatus).height, 0);
        }
        expect(h.repository.queries, hasLength(2));
        expect(h.repository.reconciliationQueries, isEmpty);
      });
    }

    testWidgets('отметка намерения вне загруженной части не меняет строки и '
        'позицию', (tester) async {
      final h = await _open(tester);
      await h.load(_summaries(first: 40));
      h.position.jumpTo(300);
      await _settle(tester);
      final rowTop = _rowTop(tester, 'Намерение 33');
      final before = h.confirmed as IntentionCatalogLoaded;

      // Намерение без обязательного тега в выдачу не входит.
      await h.confirmMark(77, FavoriteMark.favorite, tags: const []);

      final current = h.confirmed as IntentionCatalogLoaded;
      expect(current.items, before.items);
      expect(current.totalCount, 40);
      expect(_star, findsNothing);
      expect(h.position.pixels, 300);
      expect(_rowTop(tester, 'Намерение 33'), rowTop);
    });
  });

  group('состояния без выдачи', () {
    testWidgets('загрузка и устранимая недоступность показаны сообщениями '
        'страницы, а повтор читает первую порцию заново', (tester) async {
      final h = await _open(tester);
      expect(find.text(_loadingRu), findsOneWidget);

      h.repository.complete(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(tester);

      expect(find.text(_unavailableRu), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
      await _settle(tester);
      expect(h.repository.queries, hasLength(2));
      expect(find.text(_loadingRu), findsOneWidget);
    });
  });
}

Tag _tag(int index, String name) => Tag(
  id: switch (TagId.decode(
    '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  )) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError(
      'Некорректный идентификатор тега в тесте.',
    ),
  },
  name: TagName.fromInput(name),
);

/// Сводки с обязательным тегом в порядке убывания номера.
List<IntentionSummary> _summaries({
  required int first,
  int step = 1,
  List<Tag>? tags,
}) => [
  for (var index = first; index >= 1; index -= step)
    testSummary(
      index: index,
      title: 'Намерение $index',
      tags: tags ?? [_health],
    ),
];

double _rowTop(WidgetTester tester, String title) =>
    tester.getTopLeft(find.text(title)).dy;

/// Страница-образец: передаёт общему элементу выдачу своего назначения и
/// построение своих строк.
final class _Host extends ConsumerWidget {
  const _Host({required this.viewAnchor, required this.trailingInset});

  final IntentionSearchResultsViewAnchor viewAnchor;
  final double trailingInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return IntentionSearchResults(
      purpose: _purpose,
      catalog: ref.watch(intentionCatalogViewModelProvider(_purpose)),
      listKey: _listKey,
      messages: IntentionSearchResultsMessages(
        loading: localizations.catalogLoading,
        unavailable: localizations.catalogUnavailable,
        corruption: localizations.catalogCorruption,
        unexpected: localizations.catalogUnexpectedFailure,
      ),
      totalCountLabel: localizations.catalogTotalCount,
      emptyMessage: (empty) => localizations.catalogActiveEmpty,
      itemBuilder: (context, results, summary) => SizedBox(
        key: ValueKey(summary.id),
        height: _rowExtent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: Text(summary.title)),
            if (summary.favoriteMark == FavoriteMark.favorite)
              const Icon(Icons.star),
          ],
        ),
      ),
      viewAnchor: viewAnchor,
      trailingInset: trailingInset,
    );
  }
}

final class _Harness {
  _Harness(this._tester, this._container, this.repository);

  final WidgetTester _tester;
  final ProviderContainer _container;
  final ControlledCatalogRepository repository;
  int revision = 1;

  IntentionCatalogViewModel get notifier =>
      _container.read(intentionCatalogViewModelProvider(_purpose).notifier);

  IntentionCatalogConfirmedState get confirmed =>
      _container.read(intentionCatalogViewModelProvider(_purpose)).requireValue
          as IntentionCatalogConfirmedState;

  ScrollPosition get position => _tester
      .state<ScrollableState>(
        find.descendant(of: _list, matching: find.byType(Scrollable)),
      )
      .position;

  /// Загружает выдачу с обязательным и исключённым тегами: удаление первого
  /// опустошает её без чтения, удаление второго требует чтения недостающей
  /// части.
  Future<void> load(List<IntentionSummary> items) async {
    repository.complete(0, _page(const []));
    await _settle(_tester);
    notifier.changeTagFilter(
      IntentionTagFilter(
        requiredTagIds: [_health.id],
        excludedTagIds: [_sport.id],
      ),
    );
    await _settle(_tester);
    expect(repository.queries, hasLength(2));
    repository.complete(1, _page(items));
    await _tester.pumpAndSettle();
  }

  Future<void> complete(TagCommand command, TagCommandResult result) async {
    final accepted = acceptTagCommand(_container, repository, command, result);
    await accepted.future;
    await _settle(_tester);
  }

  /// Подтверждает отметку либо её снятие: краткие снимки до и после
  /// различаются только отметкой.
  Future<void> confirmMark(
    int index,
    FavoriteMark mark, {
    List<Tag>? tags,
  }) async {
    IntentionSummary summary(FavoriteMark mark) => testSummary(
      index: index,
      title: 'Намерение $index',
      tags: tags ?? [_health],
      favoriteMark: mark,
    );
    final after = summary(mark);
    final commandIndex = repository.commands.length;
    final accepted =
        _container
                .read(graphCommandCoordinatorProvider.notifier)
                .acceptExisting(switch (mark) {
                  FavoriteMark.favorite => MarkIntentionFavorite(after.id),
                  FavoriteMark.notFavorite => UnmarkIntentionFavorite(after.id),
                }, presentationTitle: after.title)
            as IntentionCommandAccepted;
    repository.completeCommand(
      commandIndex,
      ResultSuccess(
        IntentionSaved(
          testIntention(index: index, title: after.title),
          catalogMutation: IntentionCatalogUpdated(
            revision: TestCatalogRevision(++revision),
            before: TestCatalogEntrySnapshot(
              summary(switch (mark) {
                FavoriteMark.favorite => FavoriteMark.notFavorite,
                FavoriteMark.notFavorite => FavoriteMark.favorite,
              }),
            ),
            after: TestCatalogEntrySnapshot(after),
          ),
        ),
      ),
    );
    await accepted.future;
    await _settle(_tester);
  }

  Future<void> deleteTag(Tag tag) => complete(
    DeleteTag(tag.id),
    tagDeletionSuccess(
      tagId: tag.id,
      revision: TestCatalogRevision(++revision),
    ),
  );

  /// Подтверждает удаление исключённого тега и завершает чтение
  /// согласования заданным отказом.
  Future<void> failRefresh(IntentionFailure failure) async {
    final read = repository.reconciliationQueries.length;
    await deleteTag(_sport);
    expect(repository.reconciliationQueries, hasLength(read + 1));
    repository.completeReconciliation(read, ResultFailure(failure));
    await _tester.pumpAndSettle();
  }

  /// Снимает отказ любой категории автоматическим повтором: следующий
  /// подтверждённый пакет заново читает недостающую часть.
  Future<void> recoverRefresh({required int totalCount}) async {
    final read = repository.reconciliationQueries.length;
    final renamed = Tag(id: _other.id, name: TagName.fromInput('Покой'));
    await complete(
      RenameTag(tagId: _other.id, name: renamed.name),
      tagRenameSuccess(
        before: _other,
        after: renamed,
        revision: TestCatalogRevision(++revision),
      ),
    );
    expect(repository.reconciliationQueries, hasLength(read + 1));
    repository.completeReconciliation(
      read,
      reconciliationFirstPortion(
        const [],
        totalCount: totalCount,
        revision: revision,
      ),
    );
    await _tester.pumpAndSettle();
  }

  /// Меняет параметры поиска и отвечает на первую порцию новой выдачи.
  Future<void> changeParameters(
    void Function(_Harness) change,
    List<IntentionSummary> items,
  ) async {
    final answered = repository.queries.length;
    change(this);
    for (var attempt = 0; repository.queries.length == answered; attempt++) {
      if (attempt == 1000) {
        fail('Смена параметров не начала новую выдачу.');
      }
      await _tester.pump(const Duration(milliseconds: 1));
    }
    repository.complete(answered, _page(items));
    await _tester.pumpAndSettle();
  }

  Result<IntentionCatalogFirstPage> _page(List<IntentionSummary> items) =>
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: items,
          totalCount: items.length,
          nextCursor: null,
          revision: TestCatalogRevision(revision),
        ),
      );
}

Future<_Harness> _open(
  WidgetTester tester, {
  IntentionSearchResultsViewAnchor viewAnchor =
      IntentionSearchResultsViewAnchor.scrollOffset,
  double trailingInset = 0,
  List<IntentionSummary>? loadedBeforeMount,
}) async {
  final repository = ControlledCatalogRepository();
  final container = reconciliationCatalogContainer(repository);
  addTearDown(container.dispose);
  final harness = _Harness(tester, container, repository);
  Future<void> pump(Widget body) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: body),
      ),
    ),
  );
  if (loadedBeforeMount != null) {
    // Модель удерживает другой слушатель: элемент выдачи монтируется на
    // готовую выдачу и не видит уведомлений её загрузки.
    await pump(
      Consumer(
        builder: (context, ref, _) {
          ref.watch(intentionCatalogViewModelProvider(_purpose));
          return const SizedBox.shrink();
        },
      ),
    );
    await harness.load(loadedBeforeMount);
  }
  await pump(_Host(viewAnchor: viewAnchor, trailingInset: trailingInset));
  return harness;
}

/// Завершённое чтение публикует состояние в микрозадаче, а перестроение
/// приходит следующим кадром.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
