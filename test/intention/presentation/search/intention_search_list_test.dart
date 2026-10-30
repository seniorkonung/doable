import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/search/intention_search_list.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_reconciliation_test_support.dart';
import '../catalog/catalog_test_support.dart';
import '../../../support/tag_positions.dart';

/// Высота строки-образца выдачи.
const _rowExtent = 48.0;

/// Высота линии меток, которую добавляет отметка занятой пары.
const _markLineExtent = 20.0;

/// Список выдачи: ключ у него свой для каждого вида поиска, а на странице
/// теста он один.
final _list = find.byType(CustomScrollView);

void main() {
  group('состояния без строк', () {
    testWidgets('загрузка первой порции и пауза ввода показаны загрузкой', (
      tester,
    ) async {
      final h = await _open(tester);
      expect(_loading('Загружаем действия…'), findsOneWidget);

      h.repository.complete(0, _firstPage(_actions(3)));
      await _settle(tester);
      h.notifier.changeTitleFilter('бег');
      await _settle(tester);

      expect(_loading('Загружаем действия…'), findsOneWidget);
      expect(find.byType(CatalogHeader), findsNothing);
    });

    testWidgets('устранимый отказ первой порции повторяет её чтение', (
      tester,
    ) async {
      final h = await _open(tester);

      h.repository.complete(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(tester);
      expect(
        find.text('Не удалось загрузить действия. Повторите попытку.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Повторить'));
      await _settle(tester);

      expect(h.repository.queries, hasLength(2));
      expect(_loading('Загружаем действия…'), findsOneWidget);
    });

    testWidgets('повреждение первой порции показано отказом без повтора', (
      tester,
    ) async {
      final h = await _open(tester);

      h.repository.complete(
        0,
        const ResultFailure(IntentionCorruptionFailure()),
      );
      await _settle(tester);

      expect(
        find.text(
          'Сохранённые данные действий повреждены и не могут быть показаны.',
        ),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsNothing);
    });

    testWidgets('недопустимый фильтр названия не показывает ни состояния, '
        'ни заголовка выдачи', (tester) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(3)));
      await _settle(tester);

      h.notifier.changeTitleFilter('\uD800');
      await tester.pump(const Duration(milliseconds: 300));
      await _settle(tester);

      expect(h.notifier.selection.filterValidationFailure, isNotNull);
      expect(_listState, findsNothing);
      expect(find.byType(CatalogHeader), findsNothing);
    });

    testWidgets('пауза ввода во время прокрутки выдачи сразу стоит сверху', (
      tester,
    ) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(30)));
      await _settle(tester);
      await _flingDown(tester, h);

      h.notifier.changeTitleFilter('бег');
      await tester.pump();

      expect(_loading('Загружаем действия…'), findsOneWidget);
      expect(h.position.pixels, 0);
      expect(tester.getTopLeft(_listState).dy, tester.getTopLeft(_list).dy);
    });

    testWidgets('загрузка и отказ первой порции во время прокрутки выдачи '
        'сразу стоят сверху', (tester) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(30)));
      await _settle(tester);
      await _flingDown(tester, h);

      h.notifier.changeTagFilter(
        IntentionTagFilter(excludedTagIds: [_sport.id]),
      );
      await tester.pump();

      expect(_loading('Загружаем действия…'), findsOneWidget);
      expect(h.position.pixels, 0);
      expect(tester.getTopLeft(_listState).dy, tester.getTopLeft(_list).dy);

      await _waitForQueries(tester, h, 2);
      h.repository.complete(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Не удалось загрузить действия. Повторите попытку.'),
        findsOneWidget,
      );
      expect(h.position.pixels, 0);
      expect(tester.getTopLeft(_listState).dy, tester.getTopLeft(_list).dy);
    });
  });

  group('загруженная выдача', () {
    testWidgets('построенные строки подгружают порции, а кольцо подгрузки '
        'стоит в конце, только пока есть следующая порция', (tester) async {
      final h = await _open(tester, pageSize: 2);
      final all = _actions(5);

      h.repository.complete(0, _firstPage(all.sublist(0, 2), totalCount: 5));
      await _settle(tester);
      expect(_more, findsOneWidget);
      await _waitForQueries(tester, h, 2);
      h.repository.complete(1, _continuationPage(all.sublist(2, 4)));
      await _settle(tester);
      expect(_more, findsOneWidget);
      await _waitForQueries(tester, h, 3);
      h.repository.complete(
        2,
        _continuationPage(all.sublist(4), hasMore: false),
      );
      await _settle(tester);

      for (final summary in all) {
        expect(find.text(summary.title), findsOneWidget);
      }
      expect(_more, findsNothing);
      expect(h.repository.queries, hasLength(3));
    });

    testWidgets('кольцо подгрузки не строится, пока конец выдачи далеко '
        'от экрана', (tester) async {
      final h = await _open(tester, pageSize: 30);
      h.repository.complete(0, _firstPage(_actions(30), totalCount: 60));
      await _settle(tester);

      // Иначе анимация кольца вне экрана требовала бы кадров непрерывно.
      expect(_more, findsNothing);
      await tester.pumpAndSettle();
      h.position.jumpTo(h.position.maxScrollExtent);
      await _settle(tester);
      expect(_more, findsOneWidget);
    });

    testWidgets('устранимый отказ продолжения стоит в конце списка и '
        'повторяет подгрузку', (tester) async {
      final h = await _open(tester, pageSize: 2);
      final all = _actions(3);
      h.repository.complete(0, _firstPage(all.sublist(0, 2), totalCount: 3));
      await _settle(tester);
      await _waitForQueries(tester, h, 2);

      h.repository.complete(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(tester);
      expect(
        find.text('Не удалось загрузить следующие намерения.'),
        findsOneWidget,
      );
      expect(_more, findsNothing);
      await tester.tap(find.text('Повторить'));
      await _settle(tester);
      h.repository.complete(
        2,
        _continuationPage(all.sublist(2), hasMore: false),
      );
      await _settle(tester);

      expect(find.text(all.last.title), findsOneWidget);
      expect(
        find.text('Не удалось загрузить следующие намерения.'),
        findsNothing,
      );
    });

    testWidgets('добавление порции не останавливает идущую прокрутку', (
      tester,
    ) async {
      final h = await _open(tester, pageSize: 20);
      final all = _actions(40);
      h.repository.complete(0, _firstPage(all.sublist(0, 20), totalCount: 40));
      await _settle(tester);
      await _flingDown(tester, h);
      await _waitForQueries(tester, h, 2);

      h.repository.complete(
        1,
        _continuationPage(all.sublist(20), hasMore: false),
      );
      await _settle(tester);

      final confirmed = h.container
          .read(intentionCatalogViewModelProvider(h.purpose))
          .requireValue;
      expect((confirmed as IntentionCatalogLoaded).items, hasLength(40));
      await _expectScrollContinues(tester, h);
    });

    testWidgets('выдача нового запроса открывается с начала списка', (
      tester,
    ) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(30)));
      await _settle(tester);
      h.position.jumpTo(600);
      await _settle(tester);

      h.notifier.changeTagFilter(
        IntentionTagFilter(excludedTagIds: [_sport.id]),
      );
      await _waitForQueries(tester, h, 2);
      h.repository.complete(1, _firstPage(_actions(30)));
      await _settle(tester);

      expect(h.position.pixels, 0);
    });

    testWidgets('первая новая выдача после монтирования на уже загруженную '
        'открывается с начала списка', (tester) async {
      final h = await _open(tester, loadedBeforeMount: _actions(30));
      await _flingDown(tester, h);

      h.notifier.changeTagFilter(
        IntentionTagFilter(excludedTagIds: [_sport.id]),
      );
      await _waitForQueries(tester, h, 2);
      h.repository.complete(1, _firstPage(_actions(30)));
      await _settle(tester);

      expect(h.position.pixels, 0);
    });

    testWidgets('удаление исключённого тега открывает новую выдачу с начала '
        'списка', (tester) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(1)));
      await _settle(tester);
      h.notifier.changeTagFilter(
        IntentionTagFilter(excludedTagIds: [_sport.id]),
      );
      await _waitForQueries(tester, h, 2);
      h.repository.complete(1, _firstPage(_actions(30)));
      await _settle(tester);
      await _flingDown(tester, h);

      await acceptTagCommand(
        h.container,
        h.repository,
        DeleteTag(_sport.id),
        tagDeletionSuccess(
          tagId: _sport.id,
          revision: const TestCatalogRevision(2),
        ),
      ).future;
      await _waitForQueries(tester, h, 3);
      h.repository.complete(2, _firstPage(_actions(30)));
      await _settle(tester);

      expect(h.position.pixels, 0);
    });
  });

  group('пустой выбранный тип каталога при открытом охвате', () {
    for (final (locale, texts) in [
      (
        const Locale('ru'),
        (
          actionsText: 'Здесь появится намерение, отмеченное как действие.',
          intentionsText: 'Здесь всё отмечено как действия.',
          titles: {
            (IntentionScope.active, IntentionTypeChoice.actions):
                'Нет активных действий',
            (IntentionScope.active, IntentionTypeChoice.intentions):
                'Нет активных намерений',
            (IntentionScope.archived, IntentionTypeChoice.actions):
                'Нет действий в архиве',
            (IntentionScope.archived, IntentionTypeChoice.intentions):
                'Нет намерений в архиве',
            (IntentionScope.all, IntentionTypeChoice.actions):
                'Действий пока нет',
            (IntentionScope.all, IntentionTypeChoice.intentions):
                'Намерений пока нет',
          },
        ),
      ),
      (
        const Locale('en'),
        (
          actionsText: 'An intention marked as an action is shown here.',
          intentionsText: 'Everything here is marked as an action.',
          titles: {
            (IntentionScope.active, IntentionTypeChoice.actions):
                'No active actions',
            (IntentionScope.active, IntentionTypeChoice.intentions):
                'No active intentions',
            (IntentionScope.archived, IntentionTypeChoice.actions):
                'No actions in the archive',
            (IntentionScope.archived, IntentionTypeChoice.intentions):
                'No intentions in the archive',
            (IntentionScope.all, IntentionTypeChoice.actions): 'No actions yet',
            (IntentionScope.all, IntentionTypeChoice.intentions):
                'No intentions yet',
          },
        ),
      ),
    ]) {
      for (final MapEntry(key: (scope, type), value: title)
          in texts.titles.entries) {
        final actions = type == IntentionTypeChoice.actions;
        testWidgets('${locale.languageCode}, ${scope.name}, ${type.name}: '
            'заголовок «$title», текст и значок', (tester) async {
          final h = await _openCatalog(tester, locale: locale);
          h.notifier
            ..changeScope(scope)
            ..changeType(type);
          await tester.pump();
          h.repository.complete(
            h.repository.queries.length - 1,
            _otherTypeOnlyPage(shown: type),
          );
          await _settle(tester);

          expect(_inEmptyState(find.text(title)), findsOneWidget);
          expect(
            _inEmptyState(
              find.text(actions ? texts.actionsText : texts.intentionsText),
            ),
            findsOneWidget,
          );
          expect(
            _inEmptyState(
              _icon(actions ? DoableIconData.bolt : DoableIconData.intention),
            ),
            findsOneWidget,
          );
        });
      }
    }

    testWidgets('«Показать оба типа» выбирает тип «Все» в выбранном охвате', (
      tester,
    ) async {
      final h = await _openCatalog(tester, locale: const Locale('ru'));
      h.notifier
        ..changeScope(IntentionScope.archived)
        ..changeType(IntentionTypeChoice.actions);
      await tester.pump();
      h.repository.complete(
        h.repository.queries.length - 1,
        _otherTypeOnlyPage(shown: IntentionTypeChoice.actions),
      );
      await _settle(tester);

      await tester.tap(_inEmptyState(find.text('Показать оба типа')));
      await tester.pump();

      final query = h.repository.queries.last;
      expect(query.readinessFilter, IntentionReadinessFilter.all);
      expect(query.scope, IntentionScope.archived);
    });
  });

  group('согласование выдачи без смены параметров', () {
    testWidgets('строка, добавленная перед видимой, оставляет видимую строку '
        'на месте', (tester) async {
      final h = await _openSportActions(tester);
      h.position.jumpTo(300);
      await _settle(tester);
      final visibleTop = _rowTop(tester, 'Действие 46');

      await _assignSportToAction59(tester, h);

      final confirmed = h.container
          .read(intentionCatalogViewModelProvider(h.purpose))
          .requireValue;
      expect((confirmed as IntentionCatalogLoaded).items, hasLength(31));
      expect(h.position.pixels, 300 + _rowExtent + DoableMetrics.space2);
      expect(_rowTop(tester, 'Действие 46'), visibleTop);
    });

    testWidgets('верх списка в промежутке между строками: первая видимая '
        'строка остаётся на месте', (tester) async {
      final h = await _openSportActions(tester);
      // Строка 5 занимает 280–328, строка 6 начинается с 336.
      h.position.jumpTo(332);
      await _settle(tester);
      final visibleTop = _rowTop(tester, 'Действие 48');

      await _assignSportToAction59(tester, h);

      expect(_rowTop(tester, 'Действие 48'), visibleTop);
    });

    testWidgets('изменение строк после видимой не останавливает идущую '
        'прокрутку', (tester) async {
      final h = await _openSportActions(tester);
      await _flingDown(tester, h);

      await _acceptSportRemoval(h, 2, revision: 2);
      // Прокрутка уходит от смещения, запомненного при изменении, ещё до кадра
      // с новыми строками.
      await tester.pump(const Duration(milliseconds: 16));

      await _expectScrollContinues(tester, h);
    });

    testWidgets('строка, добавленная перед первой видимой, пока список закрыт '
        'страницей, оставляет видимую строку на месте', (tester) async {
      final h = await _openSportActions(tester);
      h.position.jumpTo(300);
      await _settle(tester);
      final visibleTop = _rowTop(tester, 'Действие 50');

      await _coverList(tester);
      await _assignSportToAction59(tester, h);
      await _uncoverList(tester);

      expect(_rowTop(tester, 'Действие 50'), visibleTop);
    });

    testWidgets('первая видимая строка и её соседи ушли из выдачи по одной, '
        'пока список закрыт страницей: на её месте стоит ближайшая оставшаяся '
        'строка', (tester) async {
      final h = await _openSportActions(tester);
      // Строка «Действие 50» занимает 280–328.
      h.position.jumpTo(300);
      await _settle(tester);
      final visibleTop = _rowTop(tester, 'Действие 50');

      await _coverList(tester);
      for (final (revision, index) in [(2, 50), (3, 48), (4, 52)]) {
        await _removeSportFromAction(tester, h, index, revision: revision);
      }
      await _uncoverList(tester);

      expect(_rowTop(tester, 'Действие 46'), visibleTop);
    });

    testWidgets('новая выдача, начатая после изменения строк, пока список '
        'закрыт страницей, стоит сверху', (tester) async {
      final h = await _openSportActions(tester);
      h.position.jumpTo(300);
      await _settle(tester);

      await _coverList(tester);
      await _assignSportToAction59(tester, h);
      h.notifier.changeTagFilter(
        IntentionTagFilter(excludedTagIds: [_sport.id]),
      );
      await _waitForQueries(tester, h, 3);
      h.repository.complete(2, _firstPage(_actions(30)));
      await _settle(tester);
      await _uncoverList(tester);

      expect(h.position.pixels, 0);
      expect(_rowTop(tester, 'Действие 30'), tester.getTopLeft(_list).dy);
    });

    testWidgets('подтверждённая операция меняет строки новой выдачи, начатой, '
        'пока список закрыт страницей: выдача стоит сверху', (tester) async {
      final h = await _openSportActions(tester);
      h.position.jumpTo(300);
      await _settle(tester);

      await _coverList(tester);
      // Первая строка новой выдачи — новое действие, а за ним идут действия
      // прежней: их строки список уже строил.
      h.notifier.changeTagFilter(IntentionTagFilter.empty);
      await _waitForQueries(tester, h, 3);
      h.repository.complete(2, _firstPage([_action(61), ..._actions(60)]));
      await _settle(tester);
      await _assignSportToAction59(tester, h);
      await _uncoverList(tester);

      expect(h.position.pixels, 0);
      expect(_rowTop(tester, 'Действие 61'), tester.getTopLeft(_list).dy);
    });
  });

  group('согласование отметок занятых пар', () {
    testWidgets('отметка появилась у строки над первой видимой, пока список '
        'закрыт страницей: видимая строка остаётся на месте', (tester) async {
      final h = await _openRelationParticipants(tester);
      h.repository.complete(0, _firstPage(_actions(30)));
      await _settle(tester);
      h.position.jumpTo(300);
      await _settle(tester);
      final visibleTop = _rowTop(tester, 'Действие 25');

      await _coverList(tester);
      await _createOccupyingRelation(tester, h, _action(28));
      await _uncoverList(tester);

      expect(_loadedOf(h).pairOccupants, hasLength(1));
      expect(_rowTop(tester, 'Действие 25'), visibleTop);
    });

    testWidgets('отметка снята у строки над первой видимой, пока список '
        'закрыт страницей: видимая строка остаётся на месте', (tester) async {
      final relation = _occupyingRelation(_action(28));
      final h = await _openRelationParticipants(tester);
      h.repository.complete(
        0,
        _firstPage(
          _actions(30),
          pairOccupants: {
            _action(28).id: PairOccupant(
              relationId: relation.id,
              scope: relation.scope,
            ),
          },
        ),
      );
      await _settle(tester);
      h.position.jumpTo(300);
      await _settle(tester);
      final visibleTop = _rowTop(tester, 'Действие 25');

      await _coverList(tester);
      await _deleteOccupyingRelation(tester, h, relation);
      await _uncoverList(tester);

      expect(_loadedOf(h).pairOccupants, isEmpty);
      expect(_rowTop(tester, 'Действие 25'), visibleTop);
    });
  });
}

final _sport = Tag(
  id: switch (TagId.decode('00000000-0000-4000-8000-000000000001')) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError(
      'Некорректный идентификатор тега в тесте.',
    ),
  },
  name: TagName.fromInput('Спорт'),
  color: null,
  position: tagPositionAt(1),
);

/// Кольцо подгрузки: видимого текста у него нет, только доступное название.
final _more = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == 'Загружаем ещё действия',
);

/// Виды состояния списка — закрытые наследники [ListState].
final _listState = find.byWidgetPredicate((widget) => widget is ListState);

Finder _loading(String text) =>
    find.descendant(of: _listState, matching: find.text(text));

Finder _inEmptyState(Finder finder) =>
    find.descendant(of: find.byType(EmptyState), matching: finder);

Finder _icon(DoableIconData icon) => find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == icon,
);

IntentionSummary _action(int index, {List<Tag> tags = const []}) => testSummary(
  index: index,
  title: 'Действие $index',
  readiness: IntentionReadiness.ready,
  tags: tags,
);

/// Готовые к действию сводки в порядке выдачи: от новых к старым.
List<IntentionSummary> _actions(int count) => [
  for (var index = count; index >= 1; index--) _action(index),
];

double _rowTop(WidgetTester tester, String title) =>
    tester.getTopLeft(find.text(title)).dy;

Result<IntentionCatalogPage> _firstPage(
  List<IntentionSummary> items, {
  int? totalCount,
  Map<IntentionId, PairOccupant>? pairOccupants,
}) {
  final total = totalCount ?? items.length;
  return ResultSuccess(
    IntentionCatalogFirstPage(
      items: items,
      totalCount: total,
      nextCursor: total > items.length ? const TestCatalogCursor() : null,
      revision: const TestCatalogRevision(1),
      pairOccupants: pairOccupants,
    ),
  );
}

/// Пустая первая порция, у которой в обоих охватах нет намерений типа
/// [shown], а есть только другого типа.
Result<IntentionCatalogPage> _otherTypeOnlyPage({
  required IntentionTypeChoice shown,
}) {
  final counts = switch (shown) {
    IntentionTypeChoice.actions => IntentionTypeCounts(all: 2, actions: 0),
    IntentionTypeChoice.intentions => IntentionTypeCounts(all: 2, actions: 2),
    IntentionTypeChoice.all => throw ArgumentError.value(shown, 'shown'),
  };
  return ResultSuccess(
    IntentionCatalogFirstPage(
      items: const [],
      totalCount: 0,
      counts: IntentionCountsByScopeAndType(active: counts, archived: counts),
      nextCursor: null,
      revision: const TestCatalogRevision(1),
    ),
  );
}

Result<IntentionCatalogPage> _continuationPage(
  List<IntentionSummary> items, {
  bool hasMore = true,
}) => ResultSuccess(
  IntentionCatalogContinuationPage(
    items: items,
    nextCursor: hasMore ? const TestCatalogCursor() : null,
    revision: const TestCatalogRevision(1),
  ),
);

final class _Harness {
  _Harness(this._tester, this.container, this.repository, this.purpose);

  final WidgetTester _tester;
  final ProviderContainer container;
  final ControlledCatalogRepository repository;
  final IntentionCatalogPurpose purpose;

  IntentionCatalogViewModel get notifier =>
      container.read(intentionCatalogViewModelProvider(purpose).notifier);

  ScrollPosition get position => _tester
      .state<ScrollableState>(
        find.descendant(of: _list, matching: find.byType(Scrollable)),
      )
      .position;
}

Future<_Harness> _open(
  WidgetTester tester, {
  IntentionCatalogPurpose? purpose,
  Locale locale = const Locale('ru'),
  int pageSize = 100,
  List<IntentionSummary>? loadedBeforeMount,
}) async {
  final repository = ControlledCatalogRepository();
  // Подгрузка начинается, когда построена последняя загруженная строка.
  final container = reconciliationCatalogContainer(
    repository,
    pageSize: pageSize,
    prefetchRemaining: 0,
  );
  addTearDown(container.dispose);
  final h = _Harness(
    tester,
    container,
    repository,
    purpose ?? SelectDailyChoiceAction(session: IntentionSearchSession()),
  );
  if (loadedBeforeMount != null) {
    // Модель удерживает другой слушатель: выдача монтируется на готовую
    // порцию и не видит уведомлений её загрузки.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(intentionCatalogViewModelProvider(h.purpose));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    h.repository.complete(0, _firstPage(loadedBeforeMount));
    await _settle(tester);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: IntentionSearchList(
            purpose: h.purpose,
            // Линия меток отмеченной строки делает её выше.
            rowBuilder: (context, results, summary) => SizedBox(
              height: results.pairOccupants.containsKey(summary.id)
                  ? _rowExtent + _markLineExtent
                  : _rowExtent,
              child: Text(summary.title),
            ),
            emptyScope: (_) => const EmptyState(
              title: 'Выбрать не из чего',
              text: 'Доступных активных действий нет.',
            ),
            onResetFilters: () {},
            bottomPadding: DoableMetrics.space10,
          ),
        ),
      ),
    ),
  );
  return h;
}

/// Открывает выдачу каталога намерений с открытым охватом и типом.
Future<_Harness> _openCatalog(WidgetTester tester, {required Locale locale}) =>
    _open(tester, purpose: const BrowseIntentionCatalog(), locale: locale);

/// Открывает выдачу с обязательным тегом «Спорт»: 30 строк, чётные действия
/// от 60 до 2.
Future<_Harness> _openSportActions(WidgetTester tester) async {
  final h = await _open(tester);
  h.notifier.changeTagFilter(IntentionTagFilter(requiredTagIds: [_sport.id]));
  await _waitForQueries(tester, h, 2);
  h.repository.complete(
    1,
    _firstPage([
      for (var index = 60; index >= 1; index -= 2)
        _action(index, tags: [_sport]),
    ]),
  );
  await _settle(tester);
  return h;
}

/// Участник другой роли в поиске участника связи: выбирается связанное.
final _counterpart = testSummary(index: 100);

/// Открывает выдачу поиска участника с пробой пары: отметки занятых пар
/// следуют за подтверждёнными изменениями связей.
Future<_Harness> _openRelationParticipants(WidgetTester tester) => _open(
  tester,
  purpose: SelectRelationParticipant(
    selectionContext: RelationParticipantSelectionContext.activeRelation,
    session: IntentionSearchSession(),
    pairProbe: RelationPairProbe(
      counterpartId: _counterpart.id,
      candidateRole: RelationParticipantRole.related,
    ),
  ),
);

IntentionCatalogLoaded _loadedOf(_Harness h) =>
    h.container.read(intentionCatalogViewModelProvider(h.purpose)).requireValue
        as IntentionCatalogLoaded;

/// Связь, которая занимает пару участника другой роли и строки [candidate].
LongTermRelation _occupyingRelation(IntentionSummary candidate) => testRelation(
  sourceIntentionId: _counterpart.id,
  relatedIntentionId: candidate.id,
);

/// Подтверждение команды связи на ревизии 2: первая порция читалась на первой.
LongTermRelationCommandResult _confirmedRelation(
  LongTermRelationCommandSuccess success,
) =>
    GraphCommandSucceeded<
      LongTermRelationCommandSuccess,
      LongTermRelationCommandFailure
    >(
      ConfirmedGraphResult(
        revision: const TestCatalogRevision(2),
        value: success,
      ),
    );

/// Подтверждённое создание связи отмечает строку [candidate].
Future<void> _createOccupyingRelation(
  WidgetTester tester,
  _Harness h,
  IntentionSummary candidate,
) async {
  final relation = _occupyingRelation(candidate);
  await acceptRelationCommand(
    h.container,
    h.repository,
    CreateLongTermRelation(
      sourceIntentionId: relation.sourceIntentionId,
      relatedIntentionId: relation.relatedIntentionId,
      type: relation.type,
      priority: relation.priority,
      description: null,
    ),
    _confirmedRelation(
      LongTermRelationCreated(
        relation: relation,
        description: null,
        changes: [
          LongTermRelationCreatedChange(
            revision: const TestCatalogRevision(2),
            relation: relation,
          ),
        ],
      ),
    ),
  ).future;
  await _settle(tester);
}

/// Подтверждённое удаление связи снимает отметку её строки.
Future<void> _deleteOccupyingRelation(
  WidgetTester tester,
  _Harness h,
  LongTermRelation relation,
) async {
  await acceptRelationCommand(
    h.container,
    h.repository,
    DeleteLongTermRelation(relation.id),
    _confirmedRelation(
      LongTermRelationDeleted(
        relation: relation,
        changes: [
          LongTermRelationDeletedChange(
            revision: const TestCatalogRevision(2),
            relation: relation,
          ),
        ],
      ),
    ),
  ).future;
  await _settle(tester);
}

/// Назначение обязательного тега добавляет строку перед видимой.
Future<void> _assignSportToAction59(WidgetTester tester, _Harness h) async {
  final (command, result) = intentionTagAssignment(
    state: TagAssignmentState.assigned,
    tagId: _sport.id,
    before: _action(59),
    after: _action(59, tags: [_sport]),
    revision: const TestCatalogRevision(2),
  );
  await acceptTagCommand(h.container, h.repository, command, result).future;
  await _settle(tester);
}

/// Снятие обязательного тега убирает строку из выдачи.
Future<void> _removeSportFromAction(
  WidgetTester tester,
  _Harness h,
  int index, {
  required int revision,
}) async {
  await _acceptSportRemoval(h, index, revision: revision);
  await _settle(tester);
}

/// Подтверждает снятие обязательного тега без следующего кадра.
Future<void> _acceptSportRemoval(
  _Harness h,
  int index, {
  required int revision,
}) async {
  final (command, result) = intentionTagAssignment(
    state: TagAssignmentState.absent,
    tagId: _sport.id,
    before: _action(index, tags: [_sport]),
    after: _action(index),
    revision: TestCatalogRevision(revision),
  );
  await acceptTagCommand(h.container, h.repository, command, result).future;
}

/// Закрывает выдачу непрозрачной страницей: скрытый список не перестраивается
/// по изменениям модели.
Future<void> _coverList(WidgetTester tester) async {
  unawaited(
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
  );
  await tester.pumpAndSettle();
  expect(_list, findsNothing);
}

Future<void> _uncoverList(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
}

/// Бросает выдачу вниз и оставляет её прокручиваться по инерции: пока
/// прокрутка движется, смещение не прижимается к краю сжавшегося содержимого.
Future<void> _flingDown(WidgetTester tester, _Harness h) async {
  await tester.fling(_list, const Offset(0, -300), 2000);
  await tester.pump(const Duration(milliseconds: 50));
  expect(h.position.pixels, greaterThan(0));
  expect(h.position.activity!.velocity, isNot(0));
}

/// Проверяет, что инерция бросока не оборвана и список движется дальше.
Future<void> _expectScrollContinues(WidgetTester tester, _Harness h) async {
  expect(h.position.activity!.velocity, isNot(0));
  final pixels = h.position.pixels;
  await tester.pump(const Duration(milliseconds: 16));
  expect(h.position.pixels, greaterThan(pixels));
}

/// Ждёт чтения порции, которое модель начинает после кадра.
Future<void> _waitForQueries(WidgetTester tester, _Harness h, int count) async {
  for (var attempt = 0; h.repository.queries.length < count; attempt++) {
    if (attempt == 100) {
      fail('Не дождались $count запросов каталога.');
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// Завершённое чтение публикует состояние в микрозадаче, перестроение
/// приходит следующим кадром, а подгрузка запрашивается после кадра строки.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}
