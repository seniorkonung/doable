import 'dart:math' as math;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/navigation/app_shell_page.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_status_views.dart';
import 'package:doable/src/intention/presentation/catalog/intention_search_layout.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/shared/presentation/presentation_frame_evidence.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

/// Экран телефона: параметры поиска и выдача делят высоту, которую уменьшают
/// панель, нижний безопасный отступ и клавиатура.
const _screen = Size(400, 800);

/// Локали интерфейса, в которых проверяется каталог дневных выборов: подписи
/// кнопки создания дневного выбора и строк выдачи различаются длиной.
const _locales = [Locale('ru'), Locale('en')];

/// Размер порции каталога намерений и каталога дневных выборов.
const _intentionPageSize = 100;
const _dailyChoicePageSize = 50;

/// Связь «Намерение 001» → «Намерение 002» — путь каждого дневного выбора.
const _relation = 1001;
const _firstChoice = 2001;
const _firstPathStep = 4001;

/// Нижние вставки окна, как их сообщает платформа.
final class _Insets {
  const _Insets(this.name, {this.safeBottom = 0, this.keyboard = 0});

  final String name;

  /// Физический нижний безопасный отступ экрана.
  final double safeBottom;

  /// Высота экранной клавиатуры.
  final double keyboard;

  /// Текущий нижний безопасный отступ: клавиатура, закрывшая отступ экрана,
  /// обнуляет его.
  double get padding => math.max(0, safeBottom - keyboard);

  /// Высота, которую занимает панель вместе с нижним безопасным отступом.
  double get barExtent => AppNavigationBar.height + padding;

  /// Нижняя граница содержимого корневой страницы: верх панели либо
  /// клавиатуры, закрывшей панель.
  double get contentBottom => _screen.height - math.max(keyboard, barExtent);
}

const _plain = _Insets('без нижних вставок');
const _safeArea = _Insets('нижний безопасный отступ', safeBottom: 34);
const _keyboardOpen = _Insets(
  'открытая экранная клавиатура',
  safeBottom: 34,
  keyboard: 300,
);
const _insetVariants = [_plain, _safeArea, _keyboardOpen];

void main() {
  group('нижние вставки области вкладок', () {
    for (final destination in AppDestination.values) {
      testWidgets('«${_names[destination]}»: содержимое получает вставки без '
          'высоты панели, а панель остаётся в раскладке под клавиатурой', (
        tester,
      ) async {
        await _start(tester);
        await _select(tester, destination);
        final page = find.byType(_rootPages[destination]!);
        final pageElement = tester.element(page);

        for (final insets in _insetVariants) {
          _apply(tester, insets);
          // Один кадр: высота панели задана явно, поэтому раскладке не нужен
          // второй кадр с измеренной панелью.
          await tester.pump();

          final data = MediaQuery.of(tester.element(page));
          expect(data.padding.bottom, 0, reason: insets.name);
          expect(
            data.viewInsets.bottom,
            math.max<double>(0, insets.keyboard - insets.barExtent),
            reason: insets.name,
          );
          // Панель стоит у нижнего края и не поднимается над клавиатурой.
          final bar = tester.getRect(find.byType(AppNavigationBar));
          expect(bar.bottom, _screen.height, reason: insets.name);
          expect(bar.height, insets.barExtent, reason: insets.name);
          expect(tester.getRect(page).bottom, bar.top, reason: insets.name);
          // Изменение вставок не пересоздаёт корневую страницу.
          expect(tester.element(page), same(pageElement), reason: insets.name);
          expect(tester.takeException(), isNull, reason: insets.name);
        }
      });
    }
  });

  group('содержимое каталогов над панелью', () {
    for (final insets in _insetVariants) {
      testWidgets('каталог намерений, ${insets.name}: последняя строка выдачи, '
          'загруженной до конца, полностью видна над панелью и не закрыта '
          'созданием намерения', (tester) async {
        const count = 40;
        await _start(tester, intentions: count, insets: insets);
        await _select(tester, AppDestination.intentionGraph);
        await _until(tester, find.text('Total intentions: $count'));

        final create = find.byKey(const ValueKey('catalog-create-intention'));
        if (insets.keyboard > 0) {
          // Поле фильтра в фокусе остаётся над клавиатурой и сужает выдачу.
          await tester.enterText(_titleFilter, 'Намерение 00');
          await _until(tester, find.text('Total intentions: 9'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: _titleFilter,
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode
                .hasFocus,
            isTrue,
          );
          expect(_titleFilter.hitTestable(), findsOneWidget);
          _expectFullyVisible(tester, _titleFilter, insets);
          _expectMainAction(tester, create, insets);
          expect(
            tester.getRect(_titleFilter).overlaps(tester.getRect(create)),
            isFalse,
          );
        }

        await _scrollToEnd(tester, find.byType(IntentionCatalogPage));

        // Порядок по умолчанию — от новых к старым: первое намерение стоит
        // последним.
        final lastRow = _catalogRow(_intentionTitle(1));
        _expectFullyVisible(tester, lastRow, insets);
        _expectMainAction(tester, create, insets);
        expect(
          tester.getRect(lastRow).overlaps(tester.getRect(create)),
          isFalse,
        );
        expect(lastRow.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('каталог намерений, ${insets.name}: один флинг от начала '
          'выдачи, загруженной до конца, доводит до конца список и страницу, '
          'и последняя строка полностью видна над панелью и не закрыта '
          'созданием намерения, а обратный флинг возвращает поле фильтра '
          'названия', (tester) async {
        // Двадцать строк одним флингом проходятся с запасом.
        const count = 20;
        await _start(tester, intentions: count, insets: insets);
        await _select(tester, AppDestination.intentionGraph);
        await _until(tester, find.text('Total intentions: $count'));
        final create = find.byKey(const ValueKey('catalog-create-intention'));
        if (insets.keyboard > 0) {
          // Клавиатуру открывает поле фильтра в фокусе.
          await tester.enterText(_titleFilter, 'Намерение 00');
          await _until(tester, find.text('Total intentions: 9'));
          await tester.pumpAndSettle();
        }
        expect(_catalogListScroll(tester).pixels, 0);
        expect(_catalogPageScroll(tester).pixels, 0);

        await _flingCatalog(tester, const Offset(0, -300));

        final list = _catalogListScroll(tester);
        final page = _catalogPageScroll(tester);
        expect(list.pixels, moreOrLessEquals(list.maxScrollExtent));
        expect(page.pixels, moreOrLessEquals(page.maxScrollExtent));
        expect(page.maxScrollExtent, greaterThan(0));
        // Порядок по умолчанию — от новых к старым: первое намерение стоит
        // последним.
        final lastRow = _catalogRow(_intentionTitle(1));
        _expectFullyVisible(tester, lastRow, insets);
        _expectMainAction(tester, create, insets);
        expect(
          tester.getRect(lastRow).overlaps(tester.getRect(create)),
          isFalse,
        );
        expect(lastRow.hitTestable(), findsOneWidget);

        await _flingCatalog(tester, const Offset(0, 300));

        expect(
          _catalogListScroll(tester).pixels,
          moreOrLessEquals(_catalogListScroll(tester).minScrollExtent),
        );
        expect(
          _catalogPageScroll(tester).pixels,
          moreOrLessEquals(_catalogPageScroll(tester).minScrollExtent),
        );
        _expectFullyVisible(tester, _titleFilter, insets);
        expect(_titleFilter.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final insets in [_safeArea, _keyboardOpen]) {
      testWidgets('каталог намерений, ${insets.name}: отказ продолжения выдачи '
          'и повтор видны над панелью, а повтор догружает выдачу до конца', (
        tester,
      ) async {
        const count = _intentionPageSize + 30;
        final faults = _ReadFaults();
        await _start(
          tester,
          intentions: count,
          insets: insets,
          observer: faults,
        );
        await _select(tester, AppDestination.intentionGraph);
        await _until(tester, find.text('Total intentions: $count'));
        final page = find.byType(IntentionCatalogPage);
        final create = find.byKey(const ValueKey('catalog-create-intention'));
        if (insets.keyboard > 0) {
          // Клавиатуру открывает поле фильтра в фокусе, а выдача остаётся
          // больше одной порции.
          await _focusTitleFilter(tester, insets);
          expect(find.text('Total intentions: $count'), findsOneWidget);
        }

        faults.isFailing = true;
        await _scrollToEnd(tester, page);

        final continuation = find.byType(
          IntentionCatalogContinuationStatusView,
        );
        final failure = find.descendant(
          of: continuation,
          matching: find.text('More intentions couldn’t be loaded.'),
        );
        final retry = find.descendant(
          of: continuation,
          matching: find.byType(FilledButton),
        );
        // Отступы состояния нажатий не принимают: полную видимость проверяют
        // его сообщение и повтор, а отсутствие пересечения с кнопкой — всё
        // состояние.
        _expectFullyVisible(tester, failure, insets);
        _expectFullyVisible(tester, retry, insets);
        _expectMainAction(tester, create, insets);
        expect(
          tester.getRect(continuation).overlaps(tester.getRect(create)),
          isFalse,
        );
        expect(retry.hitTestable(), findsOneWidget);

        faults.isFailing = false;
        await tester.tap(retry);
        await _settle(tester);
        await _scrollToEnd(tester, page);

        expect(continuation, findsNothing);
        final lastRow = _catalogRow(_intentionTitle(1));
        _expectFullyVisible(tester, lastRow, insets);
        _expectMainAction(tester, create, insets);
        expect(
          tester.getRect(lastRow).overlaps(tester.getRect(create)),
          isFalse,
        );
        expect(lastRow.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final locale in _locales) {
      for (final insets in _insetVariants) {
        testWidgets('каталог дневных выборов, ${locale.languageCode}, '
            '${insets.name}: продолжение выдачи и последняя строка видны над '
            'панелью и не закрыты созданием дневного выбора', (tester) async {
          const count = _dailyChoicePageSize + 5;
          final l10n = lookupAppLocalizations(locale);
          await _start(
            tester,
            dailyChoices: count,
            insets: insets,
            locale: locale,
          );
          await _select(tester, AppDestination.dailyChoices);
          await _until(
            tester,
            find.text(l10n.dailyChoiceCatalogTotalCount(count)),
          );
          final page = find.byType(DailyChoiceCatalogPage);

          if (insets.keyboard > 0) {
            await _focusDateFilter(tester, insets);
          }

          await _scrollToEnd(tester, page);

          final loadMore = find.byKey(const ValueKey('daily-choice-load-more'));
          _expectFullyVisible(tester, loadMore, insets);
          _expectMainAction(tester, _createDailyChoice, insets);
          expect(
            tester
                .getRect(loadMore)
                .overlaps(tester.getRect(_createDailyChoice)),
            isFalse,
          );
          expect(loadMore.hitTestable(), findsOneWidget);

          await tester.tap(loadMore);
          // Нажатие догружает выдачу до конца, а не открывает поиск действия.
          await _waitFor(
            tester,
            () => _continuation(page, l10n).evaluate().isEmpty,
          );
          await tester.pumpAndSettle();
          expect(find.byType(DailyChoiceActionPickerPage), findsNothing);
          await _scrollToEnd(tester, page);

          final lastRow = _dailyChoiceRow(count);
          _expectFullyVisible(tester, lastRow, insets);
          _expectMainAction(tester, _createDailyChoice, insets);
          expect(
            tester
                .getRect(lastRow)
                .overlaps(tester.getRect(_createDailyChoice)),
            isFalse,
          );
          expect(lastRow.hitTestable(), findsOneWidget);

          await tester.tap(lastRow);
          await _until(tester, find.byType(DailyChoiceDetailsPage));
          await tester.pumpAndSettle();
          // Порядок — от поздних дат к ранним: первый дневной выбор стоит
          // последним.
          expect(
            tester
                .widget<DailyChoiceDetailsPage>(
                  find.byType(DailyChoiceDetailsPage),
                )
                .choiceId,
            _dailyChoiceId(_firstChoice),
          );
          expect(tester.takeException(), isNull);
        });
      }

      for (final insets in [_safeArea, _keyboardOpen]) {
        testWidgets('каталог дневных выборов, ${locale.languageCode}, '
            '${insets.name}: отказ продолжения выдачи и повтор видны над '
            'панелью и не закрыты созданием дневного выбора, а повтор '
            'догружает выдачу', (tester) async {
          const count = _dailyChoicePageSize + 5;
          final l10n = lookupAppLocalizations(locale);
          final faults = _ReadFaults();
          await _start(
            tester,
            dailyChoices: count,
            insets: insets,
            locale: locale,
            observer: faults,
          );
          await _select(tester, AppDestination.dailyChoices);
          await _until(
            tester,
            find.text(l10n.dailyChoiceCatalogTotalCount(count)),
          );
          final page = find.byType(DailyChoiceCatalogPage);
          if (insets.keyboard > 0) {
            await _focusDateFilter(tester, insets);
          }
          await _scrollToEnd(tester, page);

          faults.isFailing = true;
          await tester.tap(
            find.byKey(const ValueKey('daily-choice-load-more')),
          );
          final failure = find.descendant(
            of: page,
            matching: find.text(l10n.dailyChoiceCatalogUnavailable),
          );
          await _until(tester, failure);
          await tester.pumpAndSettle();
          await _scrollToEnd(tester, page);

          final retry = find.descendant(
            of: page,
            matching: find.widgetWithText(TextButton, l10n.commonRetry),
          );
          _expectFullyVisible(tester, failure, insets);
          _expectFullyVisible(tester, retry, insets);
          _expectMainAction(tester, _createDailyChoice, insets);
          expect(
            tester
                .getRect(failure)
                .overlaps(tester.getRect(_createDailyChoice)),
            isFalse,
          );
          expect(
            tester.getRect(retry).overlaps(tester.getRect(_createDailyChoice)),
            isFalse,
          );
          expect(retry.hitTestable(), findsOneWidget);

          faults.isFailing = false;
          await tester.tap(retry);
          // Повтор догружает выдачу до конца, а не открывает поиск действия.
          await _waitFor(
            tester,
            () => _continuation(page, l10n).evaluate().isEmpty,
          );
          await tester.pumpAndSettle();
          expect(find.byType(DailyChoiceActionPickerPage), findsNothing);
          await _scrollToEnd(tester, page);

          final lastRow = _dailyChoiceRow(count);
          _expectFullyVisible(tester, lastRow, insets);
          _expectMainAction(tester, _createDailyChoice, insets);
          expect(
            tester
                .getRect(lastRow)
                .overlaps(tester.getRect(_createDailyChoice)),
            isFalse,
          );
          expect(lastRow.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('сообщения общей поверхности над панелью', () {
    for (final destination in AppDestination.values) {
      testWidgets('«${_names[destination]}»: сообщение о результате операции '
          'видно над панелью, а основное действие страницы поднимается над '
          'ним и остаётся доступным', (tester) async {
        final app = await _start(tester, insets: _safeArea);
        await _select(tester, destination);

        _acceptMark(app, intention: 2);
        await _until(tester, _messageOf(2));
        await tester.pumpAndSettle();

        // Сообщение показывает Scaffold корневой страницы: оно стоит прямо
        // над панелью и не заходит под неё.
        final bar = tester.getRect(find.byType(AppNavigationBar));
        final message = tester.getRect(find.byType(SnackBar));
        expect(message.bottom, bar.top);
        expect(message.bottom, _safeArea.contentBottom);
        expect(_messageOf(2).hitTestable(), findsOneWidget);
        // Панель при видимом сообщении остаётся на месте и принимает нажатия.
        expect(bar.bottom, _screen.height);
        expect(
          find.byType(NavigationDestination).hitTestable(),
          findsExactly(3),
        );

        final action = _mainActions[destination];
        if (action != null) {
          final button = find.byKey(action.key);
          expect(tester.getRect(button).bottom, lessThanOrEqualTo(message.top));
          expect(button.hitTestable(), findsOneWidget);
          await tester.tap(button);
          await _until(tester, find.byType(action.opens));
          await tester.pumpAndSettle();
          expect(find.byType(action.opens), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('при трёх построенных вкладках сообщение предъявляется один '
        'раз, а следующее ждёт его закрытия', (tester) async {
      final app = await _start(tester, insets: _safeArea);
      await _buildEveryTab(tester);

      _acceptMark(app, intention: 2);
      _acceptMark(app, intention: 3);
      await _until(tester, _messageOf(2));
      await tester.pumpAndSettle();

      // Сообщение строит Scaffold каждой корневой страницы, но видно оно
      // только на выбранной.
      expect(_builtMessages, findsExactly(3));
      expect(_messages, findsOneWidget);
      expect(_messageOf(2), findsOneWidget);
      expect(_messageOf(3), findsNothing);

      // Смена пункта не предъявляет сообщение заново и не пропускает очередь.
      await _select(tester, AppDestination.home);
      expect(_messages, findsOneWidget);
      expect(_messageOf(2), findsOneWidget);
      expect(_messageOf(3), findsNothing);

      await _closeMessage(tester);
      await _until(tester, _messageOf(3));
      await tester.pumpAndSettle();
      expect(_messages, findsOneWidget);
      expect(_messageOf(2), findsNothing);

      await _closeMessage(tester);
      for (final destination in AppDestination.values) {
        await _select(tester, destination);
        expect(_builtMessages, findsNothing, reason: destination.name);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('сообщение общей поверхности в невыбранной корневой странице '
        'не подтверждает предъявление', (tester) async {
      await _start(tester, insets: _safeArea);
      await _buildEveryTab(tester);
      await _select(tester, AppDestination.dailyChoices);
      final presented = <AppDestination>[];

      // Общая поверхность — ScaffoldMessenger приложения: сообщение строится
      // в Scaffold каждой построенной корневой страницы.
      ScaffoldMessenger.of(tester.element(find.byType(AppShellPage)))
          .showSnackBar(SnackBar(content: _RootPageEvidence(presented.add)));
      await tester.pumpAndSettle();

      expect(
        find.byType(_RootPageEvidence, skipOffstage: false),
        findsExactly(3),
      );
      expect(find.byType(_RootPageEvidence), findsOneWidget);
      expect(presented, [AppDestination.dailyChoices]);

      // Скрытая страница подтверждает сообщение, только став выбранной.
      await _select(tester, AppDestination.home);
      expect(presented, [AppDestination.dailyChoices, AppDestination.home]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('переход на другую страницу и возврат при видимом сообщении и '
        'трёх построенных вкладках проходят без отказа утверждения', (
      tester,
    ) async {
      final app = await _start(tester, insets: _safeArea);
      await _buildEveryTab(tester);
      await _select(tester, AppDestination.intentionGraph);
      _acceptMark(app, intention: 2);
      await _until(tester, _messageOf(2));
      await tester.pumpAndSettle();
      expect(_builtMessages, findsExactly(3));

      await tester.tap(find.byKey(const ValueKey('catalog-create-intention')));
      await _until(tester, find.byType(IntentionEditorPage));
      await tester.pumpAndSettle();

      expect(find.byType(AppNavigationBar), findsNothing);
      expect(_messageOf(2), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(IntentionCatalogPage), findsOneWidget);
      expect(find.byType(AppNavigationBar), findsOneWidget);
      expect(_messageOf(2), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

const _names = {
  AppDestination.home: 'Главная',
  AppDestination.dailyChoices: 'Дневные выборы',
  AppDestination.intentionGraph: 'Граф намерений',
};

/// Корневая страница каждого пункта.
const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: DailyChoiceCatalogPage,
  AppDestination.intentionGraph: IntentionCatalogPage,
};

/// Основное действие корневой страницы и страница, которую оно открывает.
/// У Главной основного действия нет.
const _mainActions = <AppDestination, ({Key key, Type opens})>{
  AppDestination.dailyChoices: (
    key: ValueKey('daily-choice-create-from-action'),
    opens: DailyChoiceActionPickerPage,
  ),
  AppDestination.intentionGraph: (
    key: ValueKey('catalog-create-intention'),
    opens: IntentionEditorPage,
  ),
};

final _titleFilter = find.byKey(const ValueKey('catalog-filter-field'));

final _dateFilter = find.byKey(const ValueKey('daily-choice-date-filter'));

final _createDailyChoice = find.byKey(
  const ValueKey('daily-choice-create-from-action'),
);

/// Строка выдачи каталога дневных выборов с номером [number].
Finder _dailyChoiceRow(int number) =>
    find.byKey(ValueKey('daily-choice-row-$number'));

/// Состояние продолжения выдачи каталога дневных выборов на странице [page]:
/// получение следующей порции, её загрузка либо отказ получения.
Finder _continuation(Finder page, AppLocalizations l10n) {
  final messages = {
    l10n.dailyChoiceCatalogLoadingMore,
    l10n.dailyChoiceCatalogUnavailable,
  };
  return find.descendant(
    of: page,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget.key == const ValueKey('daily-choice-load-more') ||
          widget is Text && messages.contains(widget.data),
    ),
  );
}

/// Дневной выбор, засеянный под номером [number].
DailyChoiceId _dailyChoiceId(int number) => (DailyChoiceId.decode(
  tagFixtureId(number),
) as DailyChoiceIdDecodingSuccess).id;

const _messageKey = ValueKey('graph-operation-message');

/// Видимые сообщения общей поверхности.
final _messages = find.byKey(_messageKey);

/// Сообщения общей поверхности в дереве, включая невыбранные вкладки.
final _builtMessages = find.byKey(_messageKey, skipOffstage: false);

/// Видимое сообщение о результате операции намерения с номером [intention].
Finder _messageOf(int intention) => find.descendant(
  of: _messages,
  matching: find.textContaining(_intentionTitle(intention)),
);

String _intentionTitle(int number) =>
    'Намерение ${number.toString().padLeft(3, '0')}';

/// Строка выдачи каталога намерений с названием [title].
Finder _catalogRow(String title) => find.descendant(
  of: find.byType(IntentionCatalogPage),
  matching: find.widgetWithText(IntentionSummaryView, title),
);

/// Свидетельство кадра сообщения, построенного в Scaffold корневой страницы:
/// называет пункт страницы, в которой сообщение подтверждено.
final class _RootPageEvidence extends StatelessWidget {
  const _RootPageEvidence(this.onPresented);

  final ValueChanged<AppDestination> onPresented;

  @override
  Widget build(BuildContext context) {
    late final AppDestination destination;
    context.visitAncestorElements((ancestor) {
      for (final MapEntry(key: candidate, value: page) in _rootPages.entries) {
        if (ancestor.widget.runtimeType == page) {
          destination = candidate;
          return false;
        }
      }
      return true;
    });
    return PresentationFrameEvidence<AppDestination>(
      subject: destination,
      requiresCurrentRoute: false,
      onPresented: onPresented,
      child: const Text('Проверочное сообщение'),
    );
  }
}

/// Управляемая недоступность хранилища: пока [isFailing], каждое обращение
/// завершается отказом занятости.
final class _ReadFaults extends LocalDatabaseConnectionObserver {
  var isFailing = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (!isFailing) return;
    throw sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'Управляемый отказ чтения',
    );
  }
}

/// Запущенное приложение.
final class _App {
  _App(this.coordinator);

  final GraphCommandCoordinator coordinator;
}

/// Сообщает окну нижние вставки [insets].
void _apply(WidgetTester tester, _Insets insets) {
  tester.view.padding = FakeViewPadding(bottom: insets.padding);
  tester.view.viewPadding = FakeViewPadding(bottom: insets.safeBottom);
  tester.view.viewInsets = FakeViewPadding(bottom: insets.keyboard);
}

/// Запускает приложение на засеянном хранилище и ждёт Главную со списком.
Future<_App> _start(
  WidgetTester tester, {
  int intentions = 40,
  int dailyChoices = 2,
  _Insets insets = _plain,
  Locale locale = const Locale('en'),
  LocalDatabaseConnectionObserver? observer,
}) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _apply(tester, insets);
  late sqlite.Database raw;
  final runtime = AppRuntime(
    connectionFactory: () {
      final connection = openInMemoryLocalDatabase(
        setup: (database) => raw = database,
      );
      return switch (observer) {
        null => connection,
        final observer => observeConfiguredLocalDatabaseConnection(
          connection,
          observer,
        ),
      };
    },
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  await tester.runAsync(runtime.bootstrap);
  _seed(raw, intentions: intentions, dailyChoices: dailyChoices);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomeIntentionRow));
  await tester.pumpAndSettle();
  return _App(runtime.commandCoordinator);
}

/// Намерения, одна отметка избранного, связь и дневные выборы по ней на
/// разные даты: каждая корневая страница получает содержимое.
void _seed(
  sqlite.Database database, {
  required int intentions,
  required int dailyChoices,
}) {
  for (var number = 1; number <= intentions; number++) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), _intentionTitle(number), 1, 0, number, number],
    );
  }
  database.execute(
    'INSERT INTO long_term_relations (id, source_intention_id, '
    'related_intention_id, type, priority, is_archived) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [tagFixtureId(_relation), tagFixtureId(1), tagFixtureId(2), 'need', 2, 0],
  );
  final firstDate = DateTime.utc(2026);
  for (var index = 0; index < dailyChoices; index++) {
    final date = firstDate.add(Duration(days: index));
    database.execute(
      'INSERT INTO daily_choices (id, source_intention_id, '
      'selected_intention_id, choice_date, is_completed) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        tagFixtureId(_firstChoice + index),
        tagFixtureId(1),
        tagFixtureId(2),
        date.toIso8601String().substring(0, 10),
        0,
      ],
    );
    database.execute(
      'INSERT INTO daily_choice_path_steps (id, daily_choice_id, '
      'long_term_relation_id) VALUES (?, ?, ?)',
      [
        tagFixtureId(_firstPathStep + index),
        tagFixtureId(_firstChoice + index),
        tagFixtureId(_relation),
      ],
    );
  }
  storeFavoriteMark(database, intentionId: tagFixtureId(1), position: 1);
}

/// Принимает отметку избранного: её успех предъявляет общая поверхность на
/// той странице, которая открыта в момент результата.
void _acceptMark(_App app, {required int intention}) {
  final id = (IntentionId.decode(
    tagFixtureId(intention),
  ) as IntentionIdDecodingSuccess).id;
  expect(
    app.coordinator.acceptExisting(
      MarkIntentionFavorite(id),
      presentationTitle: _intentionTitle(intention),
    ),
    isA<IntentionCommandAccepted>(),
  );
}

/// Ждёт закрытия видимого сообщения по истечении его времени показа.
Future<void> _closeMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// Строит вкладку каждого пункта: вкладка появляется при первом выборе.
Future<void> _buildEveryTab(WidgetTester tester) async {
  for (final destination in AppDestination.values) {
    await _select(tester, destination);
  }
  for (final page in _rootPages.values) {
    expect(find.byType(page, skipOffstage: false), findsOneWidget);
  }
}

/// Элемент [finder] виден целиком.
///
/// Элемент лежит в видимой части корневой страницы — под её шапкой и над
/// панелью либо клавиатурой. Элемент внутри прокрутки, кроме того, лежит в
/// видимой части каждой объемлющей его прокрутки, не обрезанной её краями, а
/// нажатия у его верхнего и нижнего края попадают в него.
void _expectFullyVisible(WidgetTester tester, Finder finder, _Insets insets) {
  expect(finder, findsOneWidget);
  final element = finder.evaluate().single;
  final rect = tester.getRect(finder);
  // Видимая часть корневой страницы, суженная видимой частью каждой
  // объемлющей прокрутки.
  var visibleTop = tester.getRect(find.byType(AppBar)).bottom;
  var visibleBottom = insets.contentBottom;
  var inScroll = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is Scrollable) {
      inScroll = true;
      final viewport = ancestor.renderObject! as RenderBox;
      final viewportTop = viewport.localToGlobal(Offset.zero).dy;
      visibleTop = math.max(visibleTop, viewportTop);
      visibleBottom = math.min(
        visibleBottom,
        viewportTop + viewport.size.height,
      );
    }
    return true;
  });
  // Прокрутка до края даёт координаты с ошибкой округления.
  expect(
    rect.top,
    greaterThanOrEqualTo(visibleTop - precisionErrorTolerance),
    reason: '$finder: верхний край видимой части',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(visibleBottom + precisionErrorTolerance),
    reason: '$finder: нижний край видимой части',
  );
  if (!inScroll) return;
  // Нажатие ровно на границе элементу не принадлежит, поэтому точки
  // отступают от краёв внутрь.
  for (final y in [rect.top + 1, rect.bottom - 1]) {
    final hit = tester.hitTestOnBinding(Offset(rect.center.dx, y));
    expect(
      [for (final entry in hit.path) entry.target],
      contains(element.renderObject),
      reason: '$finder: нажатие на высоте $y',
    );
  }
}

/// Ставит фокус в поле фильтра названия каталога намерений, не меняя поиск:
/// поле видно над клавиатурой и не закрыто созданием намерения.
Future<void> _focusTitleFilter(WidgetTester tester, _Insets insets) async {
  final create = find.byKey(const ValueKey('catalog-create-intention'));
  await tester.showKeyboard(_titleFilter);
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<EditableText>(
          find.descendant(
            of: _titleFilter,
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus,
    isTrue,
  );
  expect(_titleFilter.hitTestable(), findsOneWidget);
  _expectFullyVisible(tester, _titleFilter, insets);
  _expectMainAction(tester, create, insets);
  expect(
    tester.getRect(_titleFilter).overlaps(tester.getRect(create)),
    isFalse,
  );
}

/// Ставит фокус в поле фильтра даты каталога дневных выборов: поле видно над
/// клавиатурой и не закрыто созданием дневного выбора.
Future<void> _focusDateFilter(WidgetTester tester, _Insets insets) async {
  await tester.showKeyboard(_dateFilter);
  await tester.pump();
  expect(
    tester
        .widget<EditableText>(
          find.descendant(of: _dateFilter, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus,
    isTrue,
  );
  expect(_dateFilter.hitTestable(), findsOneWidget);
  _expectFullyVisible(tester, _dateFilter, insets);
  _expectMainAction(tester, _createDailyChoice, insets);
  expect(
    tester.getRect(_dateFilter).overlaps(tester.getRect(_createDailyChoice)),
    isFalse,
  );
}

/// Основное действие корневой страницы стоит в своём углу над панелью либо
/// клавиатурой: содержимое заканчивается на их верхней границе, без зазора,
/// и действие принимает нажатия.
void _expectMainAction(WidgetTester tester, Finder action, _Insets insets) {
  _expectFullyVisible(tester, action, insets);
  expect(
    tester.getRect(action).bottom,
    moreOrLessEquals(insets.contentBottom - kFloatingActionButtonMargin),
  );
  expect(action.hitTestable(), findsOneWidget);
}

/// Прокручивает корневую страницу [page] жестами до конца её выдачи.
///
/// Жест начинается у левого верхнего края видимой части прокрутки выдачи —
/// в точке, не закрытой основным действием страницы. Прокрутка выдачи —
/// самая вложенная прокрутка страницы: собственный список выдачи каталога
/// намерений либо прокрутка, которую выдача каталога дневных выборов делит с
/// фильтрами. Когда список дошёл до своего края, тот же жест продолжает
/// прокрутку всей страницы.
Future<void> _scrollToEnd(WidgetTester tester, Finder page) async {
  final list = find
      .descendant(
        of: page,
        matching: find.byWidgetPredicate((widget) => widget is ScrollView),
      )
      .last;
  final appBar = find.descendant(of: page, matching: find.byType(AppBar));
  for (var attempt = 0; attempt < 120; attempt++) {
    final before = _scrollOffsets(tester, page);
    final top = math.max(
      tester.getRect(list).top,
      tester.getRect(appBar).bottom,
    );
    await tester.dragFrom(
      Offset(tester.getRect(list).left + 24, top + 24),
      const Offset(0, -200),
    );
    await _settle(tester);
    if (listEquals(before, _scrollOffsets(tester, page))) return;
  }
  fail('Список не дошёл до конца: $page');
}

/// Позиции всех прокручиваемых областей корневой страницы [page].
List<double> _scrollOffsets(WidgetTester tester, Finder page) => [
  for (final scrollable in tester.stateList<ScrollableState>(
    find.descendant(of: page, matching: find.byType(Scrollable)),
  ))
    scrollable.position.pixels,
];

/// Флинг на [offset] по списку выдачи каталога намерений со скоростью, которой
/// с запасом хватает на список и страницу.
///
/// Жест начинается у левого верхнего края видимой части списка, как в
/// [_scrollToEnd]. Кадры идут с частотой экрана: в кадре, где список
/// упирается в край, он уходит за край лишь на малую долю пути, и дальше
/// страницу ведёт только переданная ей инерция флинга.
Future<void> _flingCatalog(WidgetTester tester, Offset offset) async {
  final list = tester.getRect(_catalogList);
  final top = math.max(list.top, tester.getRect(find.byType(AppBar)).bottom);
  await tester.flingFrom(Offset(list.left + 24, top + 24), offset, 6000);
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
}

/// Собственный список выдачи каталога намерений.
final _catalogList = find.byKey(
  const PageStorageKey<String>('intention-catalog-list'),
);

/// Прокрутка списка выдачи каталога намерений.
ScrollPosition _catalogListScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _catalogList, matching: find.byType(Scrollable)),
    )
    .position;

/// Общая прокрутка параметров поиска и выдачи каталога намерений.
ScrollPosition _catalogPageScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(IntentionSearchLayout),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppNavigationBar),
      matching: find.byType(NavigationDestination).at(destination.index),
    ),
  );
  await _until(tester, find.byType(_rootPages[destination]!));
  await tester.pumpAndSettle();
}

/// Даёт хранилищу завершить начатые обращения и дожидается покоя кадров.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}
