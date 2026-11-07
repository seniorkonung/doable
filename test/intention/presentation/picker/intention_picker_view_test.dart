import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_purpose_sheet.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_reconciliation_test_support.dart';
import '../catalog/catalog_test_support.dart';
import '../../../long_term_relation/presentation/relation_graph_test_support.dart'
    show testRelationId;
import '../../../support/tag_positions.dart';

const _screen = Size(390, 844);
const _closeLabel = 'Закрыть поиск';
const _emptyScopeMessage = 'Доступных активных действий нет.';
final _purposeDescription = IntentionPickerPurposeDescription(
  subtitle: 'Добавить в «Нужно»',
  sheetLine: 'Новые связи в «Нужно»',
  buildSheetBody: (_) => const SizedBox.shrink(),
);

const _filterFieldKey = ValueKey('participant-picker-filter');
final _filterField = find.byKey(_filterFieldKey);
final _filterButton = find.byType(FilterButton);
final _list = find.byKey(
  const PageStorageKey<String>('participant-picker-list'),
);

void main() {
  for (final (locale, title) in [
    (const Locale('ru'), 'Выбор намерений'),
    (const Locale('en'), 'Choose intentions'),
  ]) {
    {
      final purpose = _participants();
      const keyPrefix = 'participant-picker';
      testWidgets(
        '${locale.languageCode}: $keyPrefix открывает показ и упорядочивание до выдачи, с числом, после отказа и при недопустимом фильтре',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final ru = locale.languageCode == 'ru';
          final shown = ru ? 'Намерения' : 'Intentions';
          final h = await _open(tester, locale: locale, purpose: purpose);
          final header = find.byType(CatalogHeader);
          final sheetTitle = ru ? 'Показать и упорядочить' : 'Show and sort';

          Future<void> openAndClose(
            String label, {
            bool sortByName = false,
          }) async {
            expect(
              tester.getSemantics(header),
              isSemantics(
                label: label,
                isButton: true,
                hasTapAction: true,
                hasExpandedState: true,
                isExpanded: false,
              ),
            );
            await tester.tap(header);
            // Ожидаем переход листа, пока индикатор выдачи ещё вращается.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.text(sheetTitle), findsOneWidget);
            expect(tester.widget<CatalogHeader>(header).expanded, isTrue);
            // Поиск для выбора не предлагает ни охвата, ни вида.
            for (final caption in [
              ru ? 'Показать' : 'Show',
              ru ? 'Тип' : 'Type',
            ]) {
              expect(
                find.descendant(
                  of: find.byType(Sheet),
                  matching: find.text(caption),
                ),
                findsNothing,
              );
            }
            if (sortByName) {
              await tester.tap(
                find.descendant(
                  of: find.byType(Sheet),
                  matching: find.text(ru ? 'Сортировка' : 'Sort by'),
                ),
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              await tester.tap(
                find.widgetWithText(MenuItemButton, ru ? 'Название' : 'Name'),
              );
              await tester.pump();
              await tester.pump();
            }
            Navigator.of(tester.element(find.byType(Sheet))).pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.getSemantics(header), isSemantics(isExpanded: false));
          }

          // Первая порция ещё не подтверждена: число не объявляется.
          await openAndClose(
            ru
                ? 'Показать и упорядочить. Показаны: $shown. Сортировка: Создание, сначала новые.'
                : 'Show and sort. Showing: $shown. Sorted by: Created, newest first.',
          );
          h.repository.complete(0, _firstPage(_actions(1)));
          await tester.pumpAndSettle();
          await openAndClose(
            ru
                ? 'Показать и упорядочить. Показаны: $shown, 1. Сортировка: Создание, сначала новые.'
                : 'Show and sort. Showing: $shown, 1. Sorted by: Created, newest first.',
            sortByName: true,
          );

          h.repository.complete(
            h.repository.queries.length - 1,
            const ResultFailure(IntentionUnavailableFailure()),
          );
          await tester.pumpAndSettle();
          final withoutCount = ru
              ? 'Показать и упорядочить. Показаны: $shown. Сортировка: Название, от А до Я.'
              : 'Show and sort. Showing: $shown. Sorted by: Name, A to Z.';
          await openAndClose(withoutCount);

          await tester.enterText(
            find.byKey(ValueKey('$keyPrefix-filter')),
            'а' * 256,
          );
          await tester.pump();
          await openAndClose(withoutCount);
          semantics.dispose();
        },
      );

      testWidgets(
        '${locale.languageCode}: $keyPrefix показывает текущую сортировку без прежнего числа до подтверждения новой выдачи',
        (tester) async {
          final ru = locale.languageCode == 'ru';
          final initialTitle = ru ? 'Намерения' : 'Intentions';
          final initialSummary = ru
              ? 'Создание, сначала новые'
              : 'Created, newest first';
          final h = await _open(tester, locale: locale, purpose: purpose);
          final notifier = h.container.read(
            intentionCatalogViewModelProvider(purpose).notifier,
          );

          expect(_header(initialTitle, null), findsOneWidget);
          expect(find.text(initialSummary), findsOneWidget);
          h.repository.complete(0, _firstPage(_actions(3), totalCount: 13));
          await tester.pump();
          await tester.pump();
          expect(_header(initialTitle, 13), findsOneWidget);

          for (final (order, ruSummary, enSummary) in [
            (
              IntentionCatalogOrder.createdAtAscending,
              'Создание, сначала старые',
              'Created, oldest first',
            ),
            (
              IntentionCatalogOrder.updatedAtAscending,
              'Изменение, сначала старые',
              'Changed, oldest first',
            ),
            (
              IntentionCatalogOrder.updatedAtDescending,
              'Изменение, сначала новые',
              'Changed, newest first',
            ),
            (
              IntentionCatalogOrder.titleAscending,
              'Название, от А до Я',
              'Name, A to Z',
            ),
            (
              IntentionCatalogOrder.titleDescending,
              'Название, от Я до А',
              'Name, Z to A',
            ),
          ]) {
            notifier.changeOrder(order);
            await tester.pump();
            expect(_header(initialTitle, null), findsOneWidget);
            expect(find.text(ru ? ruSummary : enSummary), findsOneWidget);
          }
          h.repository.complete(
            h.repository.queries.length - 1,
            const ResultFailure(IntentionUnavailableFailure()),
          );
          await tester.pumpAndSettle();
          expect(_header(initialTitle, null), findsOneWidget);
          expect(
            find.text(ru ? 'Название, от Я до А' : 'Name, Z to A'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        '${locale.languageCode}: $keyPrefix показывает намерения обоих видов без выбора вида',
        (tester) async {
          final h = await _open(tester, locale: locale, purpose: purpose);
          final notifier = h.container.read(
            intentionCatalogViewModelProvider(purpose).notifier,
          );
          final initialQuery = h.repository.queries.single;
          h.repository.complete(
            0,
            _firstPage([
              testSummary(
                index: 2,
                title: 'Вспомогательное',
                kind: IntentionKind.supporting,
              ),
              testSummary(index: 1, title: 'Главное'),
            ]),
          );
          await tester.pumpAndSettle();

          expect(
            initialQuery.kindFilter,
            IntentionKindFilter.mainAndSupporting,
          );
          expect(initialQuery.counting, IntentionCatalogCounting.totalOnly);
          expect(find.text('Вспомогательное'), findsOneWidget);
          expect(find.text('Главное'), findsOneWidget);

          notifier.changeKind(IntentionKindFilter.supportingOnly);
          await tester.pumpAndSettle();
          expect(h.repository.queries, hasLength(1));
          expect(notifier.selection.show, isA<IntentionShowFixed>());
          expect(find.text('Главное'), findsOneWidget);
        },
      );

      testWidgets('${locale.languageCode}: шапка «$title» с крестиком, '
          'который закрывает экран', (tester) async {
        final semantics = tester.ensureSemantics();
        final h = await _open(tester, locale: locale, purpose: purpose);

        expect(
          tester.getSemantics(_title(title)),
          isSemantics(label: title, isHeader: true),
        );
        expect(find.byKey(ValueKey('$keyPrefix-filter')), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(ValueKey('$keyPrefix-cancel'))),
          isSemantics(label: _closeLabel, isButton: true, hasTapAction: true),
        );
        await tester.tap(find.byKey(ValueKey('$keyPrefix-cancel')));
        await tester.pump(const Duration(seconds: 1));

        expect(h.closes, 1);
        semantics.dispose();
      });
    }
  }

  for (final (locale, done, unfiltered, filtered) in [
    (
      const Locale('ru'),
      'Готово',
      'Фильтр по тегам',
      'Фильтр по тегам, 2 условия',
    ),
    (
      const Locale('en'),
      'Done',
      'Filter by tags',
      'Filter by tags, 2 conditions',
    ),
  ]) {
    testWidgets('${locale.languageCode}: кнопка фильтра показывает число '
        'условий', (tester) async {
      final semantics = tester.ensureSemantics();
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      final h = await _open(tester, locale: locale, tags: [health, sport]);
      h.repository.complete(0, _firstPage(_actions(3)));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterButton>(_filterButton).count, 0);
      expect(
        tester.getSemantics(_filterButton),
        isSemantics(label: unfiltered, isButton: true, hasTapAction: true),
      );

      await tester.tap(_filterButton);
      await tester.pumpAndSettle();
      await tester.tap(_panelRow(health));
      await tester.pump();
      // Первое нажатие требует тег, второе исключает его.
      await tester.tap(_panelRow(sport));
      await tester.pump();
      await tester.tap(_panelRow(sport));
      await tester.pump();
      await tester.tap(find.text(done));
      await tester.pump();
      h.repository.complete(
        h.repository.queries.length - 1,
        _firstPage(const []),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<FilterButton>(_filterButton).count, 2);
      expect(
        tester.getSemantics(_filterButton),
        isSemantics(label: filtered, isButton: true, hasTapAction: true),
      );
      // Под полем поиска условий нет: названия тегов не показаны нигде.
      expect(find.text('Здоровье'), findsNothing);
      expect(find.text('Спорт'), findsNothing);
      expect(
        h.repository.queries.last.tagFilter,
        IntentionTagFilter(
          requiredTagIds: [health.id],
          excludedTagIds: [sport.id],
        ),
      );
      semantics.dispose();
    });
  }

  for (final (locale, texts) in [
    (
      const Locale('ru'),
      (
        intentions: 'Намерения',
        byTitle: (
          'Нет намерений с таким названием',
          'Попробуйте название короче.',
        ),
        byTags: (
          'Нет намерений под эти теги',
          'Измените теги в фильтре или сбросьте его.',
        ),
        byBoth: (
          'Намерения не найдены',
          'Измените название или условия по тегам.',
        ),
        scope: 'Выбрать не из чего',
        reset: 'Сбросить фильтры',
        showBoth: 'Показать оба типа',
      ),
    ),
    (
      const Locale('en'),
      (
        intentions: 'Intentions',
        byTitle: ('No intentions with this name', 'Try a shorter name.'),
        byTags: (
          'No intentions match these tags',
          'Change the tags in the filter or reset it.',
        ),
        byBoth: (
          'No intentions found',
          'Change the name or the tag conditions.',
        ),
        scope: 'Nothing to choose from',
        reset: 'Reset filters',
        showBoth: 'Show both types',
      ),
    ),
  ]) {
    final lang = locale.languageCode;
    for (final (scenario, filter, required, message, reset) in [
      (
        'пустая выдача по условиям отличается от пустого охвата',
        '',
        true,
        texts.byTags,
        true,
      ),
      (
        'пустая выдача по названию называет намерения',
        'бег',
        false,
        texts.byTitle,
        true,
      ),
      ('пустая выдача называет обе причины', 'бег', true, texts.byBoth, true),
      (
        'пустой охват без фильтров не предлагает ни сброс, ни показ обоих типов',
        '',
        false,
        (texts.scope, _emptyScopeMessage),
        false,
      ),
    ]) {
      testWidgets('$lang: $scenario', (tester) async {
        final sport = _tag(1, 'Спорт');
        final purpose = _participants();
        final h = await _open(tester, locale: locale, purpose: purpose);
        await tester.enterText(find.byKey(_filterFieldKey), filter);
        if (required) {
          h.conditions(purpose).cycle(sport.id);
        }
        await tester.pump(const Duration(milliseconds: 300));
        h.repository.complete(
          h.repository.queries.length - 1,
          _firstPage(const []),
        );
        await tester.pumpAndSettle();

        final (title, text) = message;
        expect(_header(texts.intentions, 0), findsOneWidget);
        expect(_inEmptyState(title), findsOneWidget);
        expect(_inEmptyState(text), findsOneWidget);
        expect(
          _inEmptyState(texts.reset),
          reset ? findsOneWidget : findsNothing,
        );
        expect(_inEmptyState(texts.showBoth), findsNothing);
      });
    }

    {
      final purpose = SelectRelationParticipant(
        pairProbe: RelationPairProbe(
          counterpartId: _action(9).id,
          candidateRole: RelationParticipantRole.related,
        ),
        session: IntentionSearchSession(),
      );
      final header = texts.intentions;
      final items = [testSummary(title: 'Быть здоровым')];
      testWidgets(
        '$lang: «${texts.reset}» снимает название и условия, сохраняя порядок и ограничения',
        (tester) async {
          final sport = _tag(1, 'Спорт');
          final work = _tag(2, 'Работа');
          final h = await _open(tester, locale: locale, purpose: purpose);
          h.container
              .read(intentionCatalogViewModelProvider(purpose).notifier)
              .changeOrder(IntentionCatalogOrder.titleDescending);
          final field = _filterField;
          await tester.enterText(field, 'бег');
          final conditions = h.conditions(purpose)
            ..cycle(sport.id)
            // Второй шаг круга исключает тег.
            ..cycle(work.id)
            ..cycle(work.id);
          await tester.pump(const Duration(milliseconds: 300));
          h.repository.complete(
            h.repository.queries.length - 1,
            _firstPage(const []),
          );
          await tester.pumpAndSettle();
          expect(conditions.current.conditions, hasLength(2));
          final filteredQuery = h.repository.queries.last;

          await tester.tap(_inEmptyState(texts.reset));
          await tester.pump();
          final query = h.repository.queries.last;
          expect(query.titleFilter, isNull);
          expect(query.tagFilter, IntentionTagFilter.empty);
          expect(query.cursor, isNull);
          expect(query.kindFilter, IntentionKindFilter.mainAndSupporting);
          expect(query.order, IntentionCatalogOrder.titleDescending);
          expect(query.scope, filteredQuery.scope);
          expect(query.pairProbe, filteredQuery.pairProbe);
          h.repository.complete(
            h.repository.queries.length - 1,
            _firstPage(items),
          );
          await tester.pumpAndSettle();

          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: field,
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            isEmpty,
          );
          expect(tester.widget<FilterButton>(_filterButton).count, 0);
          expect(_header(header, items.length), findsOneWidget);
          expect(find.text(items.first.title), findsOneWidget);
          expect(
            find.text(
              locale.languageCode == 'ru'
                  ? 'Название, от Я до А'
                  : 'Name, Z to A',
            ),
            findsOneWidget,
          );
          expect(find.byType(EmptyState), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'поле поиска, фильтр и заголовок остаются на месте при прокрутке',
    (tester) async {
      final h = await _open(tester, purpose: _participants());
      h.repository.complete(0, _firstPage(_actions(20)));
      await tester.pumpAndSettle();
      final field = tester.getRect(_filterField);
      final button = tester.getRect(_filterButton);
      final header = tester.getRect(find.byType(CatalogHeader));
      expect(header.top, field.bottom + 4);
      expect(_header('Намерения', 20), findsOneWidget);

      await tester.drag(_list, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.getRect(_filterField), field);
      expect(tester.getRect(_filterButton), button);
      expect(tester.getRect(find.byType(CatalogHeader)), header);
    },
  );

  for (final (locale, error) in [
    (const Locale('ru'), 'Используйте не более 255 символов.'),
    (const Locale('en'), 'Use no more than 255 characters.'),
  ]) {
    testWidgets('${locale.languageCode}: недопустимый фильтр показан строкой '
        'поля без выдачи', (tester) async {
      final h = await _open(tester, locale: locale);
      h.repository.complete(0, _firstPage(_actions(3)));
      await tester.pumpAndSettle();

      await tester.enterText(_filterField, 'а' * 256);
      await tester.pump();
      expect(
        _header(locale.languageCode == 'ru' ? 'Намерения' : 'Intentions', null),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _filterField, matching: find.text(error)),
        findsOneWidget,
      );
      expect(
        _header(locale.languageCode == 'ru' ? 'Намерения' : 'Intentions', null),
        findsOneWidget,
      );
      expect(find.byWidgetPredicate((w) => w is ListState), findsNothing);
      expect(find.text('Действие 1'), findsNothing);
    });
  }

  testWidgets('при тексте масштаба 2 и открытой клавиатуре шапка, поле и '
      'первая строка видны, а список прокручивается', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final h = await _open(tester);
    h.repository.complete(0, _firstPage(_actions(10)));
    await tester.pumpAndSettle();
    await tester.showKeyboard(_filterField);
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    const aboveKeyboard = 844.0 - keyboard;
    final bar = tester.getRect(find.byType(TopBar));
    final field = tester.getRect(_filterField);
    final firstRow = tester.getRect(_row(10));
    expect(bar.top, greaterThanOrEqualTo(0));
    expect(field.top, greaterThanOrEqualTo(bar.bottom));
    expect(firstRow.top, greaterThan(field.bottom));
    expect(firstRow.bottom, lessThanOrEqualTo(aboveKeyboard));
    expect(tester.getRect(_list).bottom, lessThanOrEqualTo(aboveKeyboard));

    await tester.drag(_list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: _list, matching: find.byType(Scrollable)),
          )
          .position
          .pixels,
      greaterThan(0),
    );
    expect(tester.getRect(_filterField), field);
    expect(tester.takeException(), isNull);
  });

  testWidgets('выбор передаёт сводку строки с ревизией выдачи, из которой '
      'строка построена, а стрелка — идентификатор', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await _open(tester);
    final sport = _tag(1, 'Спорт');
    final renamed = Tag(
      id: sport.id,
      name: TagName.fromInput('Бег'),
      color: sport.color,
      position: sport.position,
    );
    final summary = testSummary(
      index: 1,
      title: 'Бегать по утрам',
      tags: [sport],
    );
    h.repository.complete(0, _firstPage([summary]));
    await tester.pumpAndSettle();

    await acceptTagCommand(
      h.container,
      h.repository,
      UpdateTag(tagId: sport.id, name: renamed.name, color: renamed.color),
      tagRenameSuccess(
        before: sport,
        after: renamed,
        revision: const TestCatalogRevision(2),
      ),
    ).future;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Бегать по утрам'));
    await tester.tap(find.bySemanticsLabel(RegExp('Открыть страницу')));

    final pick = h.picks.single;
    expect(pick.value.id, summary.id);
    expect(pick.value.tags.single.name.value, 'Бег');
    expect(
      pick.revision.compareTo(const TestCatalogRevision(2)),
      GraphRevisionOrder.same,
    );
    expect(h.openedDetails, [summary.id]);
    semantics.dispose();
  });

  for (final (locale, reasons) in [
    (
      const Locale('ru'),
      [
        'Уже добавлено',
        'Уже добавлено, в архиве',
        'Уже в группе "Можно использовать"',
        'Уже в группе "Можно использовать", в архиве',
      ],
    ),
    (
      const Locale('en'),
      [
        'Already added',
        'Already added, archived',
        'Already in group "Can use"',
        'Already in group "Can use", archived',
      ],
    ),
  ]) {
    testWidgets(
      '${locale.languageCode}: отметка свободной строки и причины занятых строк сохраняют выдачу',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final h = await _open(
          tester,
          locale: locale,
          checkable: true,
          purpose: SelectRelationParticipant(
            session: IntentionSearchSession(),
            pairProbe: RelationPairProbe(
              counterpartId: testSummary(index: 9).id,
              candidateRole: RelationParticipantRole.related,
            ),
          ),
        );
        final items = _actions(6);
        h.repository.complete(
          0,
          _firstPage(
            items,
            pairOccupants: {
              for (var i = 0; i < 4; i++)
                items[i].id: PairOccupant(
                  relationId: testRelationId(i + 1),
                  type: i < 2
                      ? LongTermRelationType.need
                      : LongTermRelationType.can,
                  scope: i.isEven
                      ? RelationScope.active
                      : RelationScope.archived,
                ),
            },
          ),
        );
        await tester.pumpAndSettle();
        for (final reason in reasons) {
          expect(find.text(reason), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp("${RegExp.escape(reason)}\$")),
            findsOneWidget,
          );
        }
        expect(
          _header(locale.languageCode == 'ru' ? 'Намерения' : 'Intentions', 6),
          findsOneWidget,
        );
        await tester.tap(find.text(items.first.title));
        expect(h.picks, isEmpty);
        await tester.tap(find.text(items.last.title));
        expect(h.picks.single.value.id, items.last.id);
        expect(
          tester.getSemantics(
            find.bySemanticsLabel(
              RegExp("^${RegExp.escape(items.last.title)},"),
            ),
          ),
          isSemantics(
            hasCheckedState: true,
            isChecked: false,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(
            find.bySemanticsLabel(RegExp("^${RegExp.escape(items[4].title)},")),
          ),
          isSemantics(
            hasCheckedState: true,
            isChecked: true,
            hasTapAction: true,
          ),
        );
        await tester.tap(
          find.bySemanticsLabel(
            locale.languageCode == 'ru'
                ? 'Открыть страницу намерения «${items.first.title}»'
                : 'Open the page of intention ${items.first.title}',
          ),
        );
        expect(h.openedDetails, [items.first.id]);
        semantics.dispose();
      },
    );
  }

  group('создание намерения в поиске с отметками', () {
    final participants = SelectRelationParticipant(
      session: IntentionSearchSession(),
      pairProbe: RelationPairProbe(
        counterpartId: testSummary(index: 9).id,
        candidateRole: RelationParticipantRole.related,
      ),
    );

    for (final (locale, plusLabel, rowText) in [
      (const Locale('ru'), 'Создать намерение', 'Создать «Плавать»'),
      (const Locale('en'), 'Create intention', 'Create “Плавать”'),
    ]) {
      testWidgets(
        '${locale.languageCode}: плюс просит создание с пустым названием, '
        'а строка «Создать» — с подстрокой',
        (tester) async {
          final h = await _open(
            tester,
            locale: locale,
            checkable: true,
            purpose: participants,
            purposeDescription: _purposeDescription,
          );
          h.repository.complete(0, _firstPage(const []));
          await tester.pumpAndSettle();
          await _showTitleResults(tester, h, ' Плавать ');

          await tester.tap(find.bySemanticsLabel(plusLabel));
          await tester.tap(find.text(rowText));

          expect(h.creations.map((creation) => creation.title), [
            '',
            'Плавать',
          ]);
        },
      );
    }

    testWidgets('просьба страницы очищает поле и фильтр названия и сохраняет '
        'условия по тегам', (tester) async {
      final sport = _tag(1, 'Спорт');
      final h = await _open(
        tester,
        checkable: true,
        purpose: participants,
        purposeDescription: _purposeDescription,
        tags: [sport],
      );
      h.repository.complete(0, _firstPage(const []));
      await tester.pumpAndSettle();
      h.conditions(participants).cycle(sport.id);
      await tester.pump();
      h.repository.complete(1, _firstPage(const []));
      await tester.pumpAndSettle();
      await _showTitleResults(tester, h, 'Плавать');

      await tester.tap(find.text('Создать «Плавать»'));
      h.creations.single.clearTitle();
      await tester.pump();

      expect(find.text('Плавать'), findsNothing);
      final query = h.repository.queries.last;
      expect(query.titleFilter, isNull);
      expect(query.tagFilter.requiredTagIds, [sport.id]);
    });

    testWidgets('поиск с выбором одного намерения плюса и строки не имеет', (
      tester,
    ) async {
      final h = await _open(
        tester,
        purpose: participants,
        purposeDescription: _purposeDescription,
      );
      h.repository.complete(0, _firstPage(const []));
      await tester.pumpAndSettle();
      await _showTitleResults(tester, h, 'Плавать');

      expect(find.bySemanticsLabel('Создать намерение'), findsNothing);
      expect(find.text('Создать «Плавать»'), findsNothing);
    });
  });

  for (final brightness in Brightness.values) {
    for (final locale in [const Locale('ru'), const Locale('en')]) {
      testWidgets(
        '${locale.languageCode}, ${brightness.name}: при пустом поле поиска цели касания не '
        'меньше tap-min, подписаны и контрастны',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final h = await _open(tester, brightness: brightness, locale: locale);
          h.repository.complete(0, _firstPage(_actions(3)));
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantics.dispose();
        },
      );
    }
  }
}

SelectRelationParticipant _participants() => SelectRelationParticipant(
  session: IntentionSearchSession(),
  pairProbe: RelationPairProbe(
    counterpartId: testSummary(index: 999).id,
    candidateRole: RelationParticipantRole.related,
  ),
);

Finder _title(String text) =>
    find.descendant(of: find.byType(TopBar), matching: find.text(text));

Finder _header(String title, int? count) => find.byWidgetPredicate(
  (widget) =>
      widget is CatalogHeader && widget.title == title && widget.count == count,
);

Finder _inEmptyState(String text) =>
    find.descendant(of: find.byType(EmptyState), matching: find.text(text));

Finder _row(int index) => find.byKey(
  ValueKey('participant-picker-${_action(index).id.toCanonicalString()}'),
);

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

IntentionSummary _action(int index) =>
    testSummary(index: index, title: 'Действие $index');

/// Сводки действий в порядке выдачи: от новых к старым.
List<IntentionSummary> _actions(int count) => [
  for (var index = count; index >= 1; index--) _action(index),
];

Result<IntentionCatalogPage> _firstPage(
  List<IntentionSummary> items, {
  int? totalCount,
  Map<IntentionId, PairOccupant>? pairOccupants,
  int? exactTitleCount,
}) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: items,
    totalCount: totalCount ?? items.length,
    counts: const IntentionCountsTotalOnly(),
    nextCursor: (totalCount ?? items.length) > items.length
        ? const TestCatalogCursor()
        : null,
    revision: const TestCatalogRevision(1),
    pairOccupants: pairOccupants,
    exactTitleCount: exactTitleCount,
  ),
);

/// Вводит подстроку [title], которой не называется ни одно активное намерение.
Future<void> _showTitleResults(
  WidgetTester tester,
  _Harness h,
  String title,
) async {
  await tester.enterText(find.byType(EditableText), title);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  h.repository.complete(
    h.repository.queries.length - 1,
    _firstPage(const [], exactTitleCount: 0),
  );
  await tester.pumpAndSettle();
}

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
  color: null,
  position: tagPositionAt(number),
);

final class _Harness {
  _Harness(this.container, this.repository);

  final ProviderContainer container;
  final ControlledCatalogRepository repository;
  int closes = 0;
  final picks = <GraphSnapshot<IntentionSummary>>[];
  final openedDetails = <IntentionId>[];
  final creations = <({String title, VoidCallback clearTitle})>[];

  IntentionTagConditionsViewModel conditions(IntentionPickerPurpose purpose) =>
      container.read(intentionTagConditionsViewModelProvider(purpose).notifier);
}

Future<_Harness> _open(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
  Brightness brightness = Brightness.light,
  IntentionPickerPurpose? purpose,
  List<Tag>? tags,
  bool checkable = false,
  IntentionPickerPurposeDescription? purposeDescription,
}) async {
  tester.view
    ..physicalSize = _screen
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = ControlledCatalogRepository()..tagCatalogItems = tags;
  final container = reconciliationCatalogContainer(repository);
  addTearDown(container.dispose);
  final h = _Harness(container, repository);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: doableTheme(brightness),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IntentionPickerView(
          purpose: purpose ?? _participants(),
          closeLabel: _closeLabel,
          emptyScopeMessage: _emptyScopeMessage,
          onClose: () => h.closes++,
          rowBehavior: checkable
              ? IntentionPickerCheckable(
                  group: IntentionRelationGroup.needs,
                  selectedIds: {_action(2).id},
                  onToggle: h.picks.add,
                  onCreate: (title, clearTitle) =>
                      h.creations.add((title: title, clearTitle: clearTitle)),
                )
              : IntentionPickerSingle(onPick: h.picks.add),
          onOpenDetails: h.openedDetails.add,
          purposeDescription: purposeDescription,
        ),
      ),
    ),
  );
  await tester.pump();
  return h;
}
