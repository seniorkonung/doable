import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
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
import '../../../support/tag_positions.dart';

const _purpose = BrowseIntentionCatalog();
const _listKey = PageStorageKey<String>('search-results-test-list');

const _loadingRu = 'Загружаем намерения…';
const _unavailableRu = 'Не удалось загрузить намерения. Повторите попытку.';
const _emptyRu = 'Активных намерений пока нет.';

/// Высота строки-образца выдачи.
const _rowExtent = 48.0;

final _list = find.byKey(_listKey);

final _health = _tag(1, 'Здоровье');
final _sport = _tag(2, 'Спорт');

void main() {
  group('верхняя позиция новой выдачи', () {
    for (final (name, change) in <(String, void Function(_Harness))>[
      ('условий по тегам', _clearTagConditions),
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
    }

    // Смена любого параметра идёт одним путём; на краях списка проверяется
    // смена условий по тегам.
    testWidgets(
      'смена условий по тегам при списке, снятом с экрана пустой выдачей, '
      'открывает выдачу со смещением ноль',
      (tester) async {
        final h = await _open(tester);
        await h.load(_summaries(first: 40));
        h.position.jumpTo(300);
        await _settle(tester);
        // Удаление обязательного тега начинает новую выдачу, и её пустая
        // первая порция снимает список с экрана.
        final restarted = h.repository.queries.length;
        await h.deleteTag(_health);
        h.repository.complete(restarted, h._page(const []));
        await tester.pumpAndSettle();
        expect(_list, findsNothing);
        expect(find.text(_emptyRu), findsOneWidget);

        await h.changeParameters(_clearTagConditions, _summaries(first: 40));

        expect(h.position.pixels, 0);
        expect(
          _rowTop(tester, 'Намерение 40'),
          moreOrLessEquals(tester.getRect(_list).top),
        );
      },
    );

    testWidgets('первая после монтирования на уже загруженную выдачу смена '
        'условий по тегам открывает выдачу со смещением ноль', (tester) async {
      final h = await _open(tester, loadedBeforeMount: _summaries(first: 40));
      h.position.jumpTo(300);
      await _settle(tester);

      await h.changeParameters(_clearTagConditions, _summaries(first: 40));

      expect(h.position.pixels, 0);
      expect(
        _rowTop(tester, 'Намерение 40'),
        moreOrLessEquals(tester.getRect(_list).top),
      );
    });

    testWidgets('удаление исключённого тега при показанном прокрученном '
        'списке открывает новую выдачу со смещением ноль', (tester) async {
      final h = await _open(tester);
      await h.load(_summaries(first: 40));
      h.position.jumpTo(300);
      await _settle(tester);

      final restarted = h.repository.queries.length;
      await h.deleteTag(_sport);
      expect(h.repository.queries, hasLength(restarted + 1));
      h.repository.complete(restarted, h._page(_summaries(first: 40)));
      await tester.pumpAndSettle();

      expect(h.position.pixels, 0);
      expect(
        _rowTop(tester, 'Намерение 40'),
        moreOrLessEquals(tester.getRect(_list).top),
      );
    });
  });

  group('согласование выдачи без смены параметров', () {
    testWidgets('сохраняет экранное положение видимого намерения при строке, '
        'добавленной перед ним', (tester) async {
      final h = await _open(tester);
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

      expect(h.position.pixels, 300 + _rowExtent);
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
  color: null,
  position: tagPositionAt(index),
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

void _clearTagConditions(_Harness h) =>
    h.notifier.changeTagFilter(IntentionTagFilter.empty);

double _rowTop(WidgetTester tester, String title) =>
    tester.getTopLeft(find.text(title)).dy;

/// Страница-образец: передаёт общему элементу выдачу своего назначения и
/// построение своих строк.
final class _Host extends ConsumerWidget {
  const _Host();

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
          children: [Expanded(child: Text(summary.title))],
        ),
      ),
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

  /// Загружает выдачу с обязательным и исключённым тегами: удаление любого
  /// из них снимает его условие и начинает новую выдачу.
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

  Future<void> deleteTag(Tag tag) => complete(
    DeleteTag(tag.id),
    tagDeletionSuccess(
      tagId: tag.id,
      revision: TestCatalogRevision(++revision),
    ),
  );

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
  await pump(const _Host());
  return harness;
}

/// Завершённое чтение публикует состояние в микрозадаче, а перестроение
/// приходит следующим кадром.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
