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
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
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

const _screen = Size(390, 844);
const _closeLabel = 'Закрыть поиск';
const _emptyScopeMessage = 'Доступных активных действий нет.';
const _revision = TestCatalogRevision(1);

final _actionField = find.byKey(const ValueKey('daily-choice-action-filter'));
final _filterButton = find.byType(FilterButton);
final _list = find.byKey(
  const PageStorageKey<String>('daily-choice-action-list'),
);

void main() {
  for (final (locale, action, intention) in [
    (const Locale('ru'), 'Выбор действия', 'Выбор намерения'),
    (const Locale('en'), 'Choose an action', 'Choose an intention'),
  ]) {
    for (final (purpose, title, keyPrefix) in [
      (
        SelectDailyChoiceAction(session: IntentionSearchSession()),
        action,
        'daily-choice-action',
      ),
      (
        SelectDailyChoiceSource(session: IntentionSearchSession()),
        intention,
        'daily-choice-source',
      ),
      (
        SelectRelationParticipant(
          selectionContext: RelationParticipantSelectionContext.activeRelation,
          session: IntentionSearchSession(),
        ),
        intention,
        'participant-picker',
      ),
    ]) {
      testWidgets(
        '${locale.languageCode}: $keyPrefix открывает показ и упорядочивание до выдачи, с числом, после отказа и при недопустимом фильтре',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final ru = locale.languageCode == 'ru';
          final type = purpose is SelectDailyChoiceAction
              ? (ru ? 'Действия' : 'Actions')
              : (ru ? 'Все' : 'All');
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
            final typeRow = tester.getSemantics(
              find.descendant(
                of: find.byType(Sheet),
                matching: find.bySemanticsLabel(ru ? 'Тип' : 'Type'),
              ),
            );
            expect(
              typeRow.value,
              purpose is SelectDailyChoiceAction
                  ? (ru ? 'Только действия' : 'Actions only')
                  : (ru ? 'Намерения и действия' : 'Intentions and actions'),
            );
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
                ? 'Показать и упорядочить. Тип: $type. Сортировка: Создание, сначала новые.'
                : 'Show and sort. Type: $type. Sorted by: Created, newest first.',
          );
          h.repository.complete(0, _firstPage(_actions(1)));
          await tester.pumpAndSettle();
          await openAndClose(
            ru
                ? 'Показать и упорядочить. Тип: $type, 1. Сортировка: Создание, сначала новые.'
                : 'Show and sort. Type: $type, 1. Sorted by: Created, newest first.',
            sortByName: true,
          );

          h.repository.complete(
            h.repository.queries.length - 1,
            const ResultFailure(IntentionUnavailableFailure()),
          );
          await tester.pumpAndSettle();
          final withoutCount = ru
              ? 'Показать и упорядочить. Тип: $type. Сортировка: Название, от А до Я.'
              : 'Show and sort. Type: $type. Sorted by: Name, A to Z.';
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
        '${locale.languageCode}: $keyPrefix показывает текущие тип и сортировку без прежнего числа до подтверждения новой выдачи',
        (tester) async {
          final ru = locale.languageCode == 'ru';
          final pinned = purpose is SelectDailyChoiceAction;
          final initialTitle = pinned
              ? (ru ? 'Действия' : 'Actions')
              : (ru ? 'Все' : 'All');
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

          if (!pinned) {
            notifier.changeType(IntentionTypeChoice.intentions);
            await tester.pump();
            expect(
              _header(ru ? 'Намерения' : 'Intentions', null),
              findsOneWidget,
            );
            expect(find.text(initialSummary), findsOneWidget);
            h.repository.complete(
              h.repository.queries.length - 1,
              _firstPage(const []),
            );
            await tester.pumpAndSettle();
            expect(_header(ru ? 'Намерения' : 'Intentions', 0), findsOneWidget);
            notifier.changeType(IntentionTypeChoice.actions);
            await tester.pump();
            expect(_header(ru ? 'Действия' : 'Actions', null), findsOneWidget);
            h.repository.complete(
              h.repository.queries.length - 1,
              _firstPage(_actions(2)),
            );
            await tester.pumpAndSettle();
          }

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
            expect(_header(ru ? 'Действия' : 'Actions', null), findsOneWidget);
            expect(find.text(ru ? ruSummary : enSummary), findsOneWidget);
          }
          h.repository.complete(
            h.repository.queries.length - 1,
            const ResultFailure(IntentionUnavailableFailure()),
          );
          await tester.pumpAndSettle();
          expect(_header(ru ? 'Действия' : 'Actions', null), findsOneWidget);
          expect(
            find.text(ru ? 'Название, от Я до А' : 'Name, Z to A'),
            findsOneWidget,
          );
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
        actions: 'Действия',
        intentions: 'Все',
        intentionsOnly: 'Намерения',
        byTitle: (
          'Нет действий с таким названием',
          'Попробуйте название короче.',
        ),
        byTags: (
          'Нет действий под эти теги',
          'Измените теги в фильтре или сбросьте его.',
        ),
        byBoth: (
          'Намерения не найдены',
          'Измените название или условия по тегам.',
        ),
        actionsByBoth: (
          'Действия не найдены',
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
        actions: 'Actions',
        intentions: 'All',
        intentionsOnly: 'Intentions',
        byTitle: ('No actions with this name', 'Try a shorter name.'),
        byTags: (
          'No actions match these tags',
          'Change the tags in the filter or reset it.',
        ),
        byBoth: (
          'No intentions found',
          'Change the name or the tag conditions.',
        ),
        actionsByBoth: (
          'No actions found',
          'Change the name or the tag conditions.',
        ),
        scope: 'Nothing to choose from',
        reset: 'Reset filters',
        showBoth: 'Show both types',
      ),
    ),
  ]) {
    final lang = locale.languageCode;
    for (final (
          scenario,
          purpose,
          type,
          filter,
          required,
          header,
          message,
          reset,
        )
        in [
          (
            'пустая выдача по названию советует название короче',
            SelectDailyChoiceAction(session: IntentionSearchSession()),
            IntentionTypeChoice.actions,
            'бег',
            false,
            texts.actions,
            texts.byTitle,
            true,
          ),
          (
            'пустая выдача по условиям отличается от пустого охвата',
            SelectDailyChoiceSource(session: IntentionSearchSession()),
            IntentionTypeChoice.actions,
            '',
            true,
            texts.actions,
            texts.byTags,
            true,
          ),
          (
            'пустая выдача называет обе причины',
            SelectDailyChoiceSource(session: IntentionSearchSession()),
            IntentionTypeChoice.all,
            'бег',
            true,
            texts.intentions,
            texts.byBoth,
            true,
          ),
          (
            'пустая выдача по названию называет выбранные действия в поиске исходного намерения',
            SelectDailyChoiceSource(session: IntentionSearchSession()),
            IntentionTypeChoice.actions,
            'бег',
            false,
            texts.actions,
            texts.byTitle,
            true,
          ),
          (
            'пустая выдача по названию и тегам называет выбранные действия',
            SelectDailyChoiceSource(session: IntentionSearchSession()),
            IntentionTypeChoice.actions,
            'бег',
            true,
            texts.actions,
            texts.actionsByBoth,
            true,
          ),
          (
            'пустой охват без фильтров не предлагает сброс',
            SelectDailyChoiceAction(session: IntentionSearchSession()),
            IntentionTypeChoice.actions,
            '',
            false,
            texts.actions,
            (texts.scope, _emptyScopeMessage),
            false,
          ),
          (
            'пустой охват при открытом типе «Намерения» не предлагает действия',
            SelectDailyChoiceSource(session: IntentionSearchSession()),
            IntentionTypeChoice.intentions,
            '',
            false,
            texts.intentionsOnly,
            (texts.scope, _emptyScopeMessage),
            false,
          ),
        ]) {
      testWidgets('$lang: $scenario', (tester) async {
        final sport = _tag(1, 'Спорт');
        final h = await _open(tester, locale: locale, purpose: purpose);
        h.container
            .read(intentionCatalogViewModelProvider(purpose).notifier)
            .changeType(type);
        final prefix = switch (purpose) {
          SelectDailyChoiceAction() => 'daily-choice-action',
          SelectDailyChoiceSource() => 'daily-choice-source',
          SelectRelationParticipant() => 'participant-picker',
        };
        await tester.enterText(find.byKey(ValueKey('$prefix-filter')), filter);
        if (required) {
          h.conditions(purpose).cycle(sport, snapshotRevision: _revision);
        }
        await tester.pump(const Duration(milliseconds: 300));
        h.repository.complete(
          h.repository.queries.length - 1,
          _firstPage(const []),
        );
        await tester.pumpAndSettle();

        final (title, text) = message;
        expect(_header(header, 0), findsOneWidget);
        expect(_inEmptyState(title), findsOneWidget);
        expect(_inEmptyState(text), findsOneWidget);
        expect(
          _inEmptyState(texts.reset),
          reset ? findsOneWidget : findsNothing,
        );
        expect(_inEmptyState(texts.showBoth), findsNothing);
      });
    }

    for (final (purpose, type, prefix, header, items) in [
      (
        SelectDailyChoiceAction(session: IntentionSearchSession()),
        IntentionTypeChoice.actions,
        'daily-choice-action',
        texts.actions,
        _actions(3),
      ),
      (
        SelectRelationParticipant(
          selectionContext:
              RelationParticipantSelectionContext.archivedRelation,
          pairProbe: RelationPairProbe(
            counterpartId: _action(9).id,
            candidateRole: RelationParticipantRole.related,
          ),
          session: IntentionSearchSession(),
        ),
        IntentionTypeChoice.intentions,
        'participant-picker',
        texts.intentionsOnly,
        [testSummary(title: 'Быть здоровым')],
      ),
    ]) {
      testWidgets(
        '$lang, $prefix: «${texts.reset}» снимает название и условия, сохраняя тип, порядок и ограничения',
        (tester) async {
          final sport = _tag(1, 'Спорт');
          final work = _tag(2, 'Работа');
          final h = await _open(tester, locale: locale, purpose: purpose);
          h.container.read(intentionCatalogViewModelProvider(purpose).notifier)
            ..changeType(type)
            ..changeOrder(IntentionCatalogOrder.titleDescending);
          final field = find.byKey(ValueKey('$prefix-filter'));
          await tester.enterText(field, 'бег');
          final conditions = h.conditions(purpose)
            ..cycle(sport, snapshotRevision: _revision)
            // Второй шаг круга исключает тег.
            ..cycle(work, snapshotRevision: _revision)
            ..cycle(work, snapshotRevision: _revision);
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
          expect(query.readinessFilter, filteredQuery.readinessFilter);
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

    for (final type in [
      IntentionTypeChoice.intentions,
      IntentionTypeChoice.actions,
    ]) {
      testWidgets(
        '$lang, ${type == IntentionTypeChoice.intentions ? 'Намерения' : 'Действия'}: пустой тип предлагает показать оба типа',
        (tester) async {
          final ru = locale.languageCode == 'ru';
          final purpose = SelectRelationParticipant(
            selectionContext:
                RelationParticipantSelectionContext.activeRelation,
            pairProbe: RelationPairProbe(
              counterpartId: _action(9).id,
              candidateRole: RelationParticipantRole.related,
            ),
            session: IntentionSearchSession(),
          );
          final items = type == IntentionTypeChoice.intentions
              ? _actions(2)
              : [testSummary(title: 'Быть здоровым')];
          final h = await _open(tester, locale: locale, purpose: purpose);
          h.container.read(intentionCatalogViewModelProvider(purpose).notifier)
            ..changeType(type)
            ..changeOrder(IntentionCatalogOrder.titleDescending);
          await tester.pump();
          h.repository.complete(
            h.repository.queries.length - 1,
            _firstPage(
              const [],
              typeCounts: IntentionTypeCounts(
                all: items.length,
                actions: type == IntentionTypeChoice.intentions
                    ? items.length
                    : 0,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            _header(
              type == IntentionTypeChoice.intentions
                  ? texts.intentionsOnly
                  : texts.actions,
              0,
            ),
            findsOneWidget,
          );
          expect(
            _inEmptyState(
              ru ? 'Намерений этого типа нет' : 'No intentions of this type',
            ),
            findsOneWidget,
          );
          expect(
            _inEmptyState(
              ru
                  ? 'Покажите оба типа, чтобы выбрать из доступных намерений.'
                  : 'Show both types to choose from the available intentions.',
            ),
            findsOneWidget,
          );
          expect(_inEmptyState(texts.reset), findsNothing);

          await tester.tap(_inEmptyState(texts.showBoth));
          await tester.pump();
          final query = h.repository.queries.last;
          expect(query.readinessFilter, IntentionReadinessFilter.all);
          expect(query.scope, IntentionScope.active);
          expect(query.pairProbe, purpose.pairProbe);
          expect(query.order, IntentionCatalogOrder.titleDescending);
          expect(query.cursor, isNull);
          h.repository.complete(
            h.repository.queries.length - 1,
            _firstPage(items),
          );
          await tester.pumpAndSettle();
          expect(_header(texts.intentions, items.length), findsOneWidget);
          expect(find.text(items.first.title), findsOneWidget);
          expect(find.byType(EmptyState), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'поле поиска, фильтр и заголовок исходного намерения остаются на месте при прокрутке',
    (tester) async {
      final h = await _open(
        tester,
        purpose: SelectDailyChoiceSource(session: IntentionSearchSession()),
      );
      h.repository.complete(0, _firstPage(_actions(20)));
      await tester.pumpAndSettle();
      final sourceField = find.byKey(
        const ValueKey('daily-choice-source-filter'),
      );
      final sourceList = find.byKey(
        const PageStorageKey<String>('daily-choice-source-list'),
      );
      final field = tester.getRect(sourceField);
      final button = tester.getRect(_filterButton);
      final header = tester.getRect(find.byType(CatalogHeader));
      expect(header.top, field.bottom + 4);
      expect(_header('Все', 20), findsOneWidget);

      await tester.drag(sourceList, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.getRect(sourceField), field);
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

      await tester.enterText(_actionField, 'а' * 256);
      await tester.pump();
      expect(
        _header(locale.languageCode == 'ru' ? 'Действия' : 'Actions', null),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _actionField, matching: find.text(error)),
        findsOneWidget,
      );
      expect(
        _header(locale.languageCode == 'ru' ? 'Действия' : 'Actions', null),
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
    await tester.showKeyboard(_actionField);
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    const aboveKeyboard = 844.0 - keyboard;
    final bar = tester.getRect(find.byType(TopBar));
    final field = tester.getRect(_actionField);
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
    expect(tester.getRect(_actionField), field);
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
      readiness: IntentionReadiness.ready,
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

Finder _title(String text) =>
    find.descendant(of: find.byType(TopBar), matching: find.text(text));

Finder _header(String title, int? count) => find.byWidgetPredicate(
  (widget) =>
      widget is CatalogHeader && widget.title == title && widget.count == count,
);

Finder _inEmptyState(String text) =>
    find.descendant(of: find.byType(EmptyState), matching: find.text(text));

Finder _row(int index) => find.byKey(
  ValueKey('daily-choice-action-${_action(index).id.toCanonicalString()}'),
);

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

IntentionSummary _action(int index) => testSummary(
  index: index,
  title: 'Действие $index',
  readiness: IntentionReadiness.ready,
);

/// Сводки действий в порядке выдачи: от новых к старым.
List<IntentionSummary> _actions(int count) => [
  for (var index = count; index >= 1; index--) _action(index),
];

Result<IntentionCatalogPage> _firstPage(
  List<IntentionSummary> items, {
  int? totalCount,
  IntentionTypeCounts? typeCounts,
}) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: items,
    totalCount: totalCount ?? items.length,
    counts: typeCounts == null
        ? const IntentionCountsTotalOnly()
        : IntentionCountsByType(typeCounts),
    nextCursor: (totalCount ?? items.length) > items.length
        ? const TestCatalogCursor()
        : null,
    revision: const TestCatalogRevision(1),
  ),
);

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

  IntentionTagConditionsViewModel conditions(IntentionPickerPurpose purpose) =>
      container.read(intentionTagConditionsViewModelProvider(purpose).notifier);
}

Future<_Harness> _open(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
  Brightness brightness = Brightness.light,
  IntentionPickerPurpose? purpose,
  List<Tag>? tags,
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
          purpose:
              purpose ??
              SelectDailyChoiceAction(session: IntentionSearchSession()),
          closeLabel: _closeLabel,
          emptyScopeMessage: _emptyScopeMessage,
          onClose: () => h.closes++,
          onPick: h.picks.add,
          onOpenDetails: h.openedDetails.add,
        ),
      ),
    ),
  );
  await tester.pump();
  return h;
}
