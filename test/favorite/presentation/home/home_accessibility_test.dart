import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/favorite_storage_fixture.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

/// Узкий экран телефона: увеличенный текст занимает его целиком.
const _screen = Size(360, 780);

const _textScale = 2.5;

const _locales = [Locale('ru'), Locale('en')];

// Названия намерений — данные человека: они одинаковы в обеих локалях.

/// Название, которое не помещается в одну строку.
const _longTitle = 'Долгая прогулка до дальнего парка вместе с соседями';

/// «Долгая прогулка…», готово к действию, две активные связи.
const _long = 1;

/// «Гулять», не готово к действию, без связей.
const _walk = 2;

/// «Гулять», готово к действию, одна активная связь — тёзка [_walk].
const _otherWalk = 3;

/// «Читать» и «Спать» — участники связей без отметки.
const _read = 4;
const _sleep = 5;

/// Порядок избранных не совпадает ни с порядком создания, ни с названиями.
const _favorites = [_otherWalk, _long, _walk];

/// Строка Главной, которую ожидает человек.
typedef _Row = ({int number, String title, bool isReady, int relations});

const List<_Row> _rows = [
  (number: _otherWalk, title: 'Гулять', isReady: true, relations: 1),
  (number: _long, title: _longTitle, isReady: true, relations: 2),
  (number: _walk, title: 'Гулять', isReady: false, relations: 0),
];

/// Вид отказа чтения списка Главной.
enum _Failure {
  unavailable('недоступность'),
  corruption('повреждение'),
  unexpected('непредвиденный отказ');

  const _Failure(this.description);

  final String description;
}

void main() {
  for (final locale in _locales) {
    final code = locale.languageCode;
    final otherLocale = _locales.firstWhere((other) => other != locale);

    testWidgets('экранный диктор получает строки Главной в порядке списка с '
        'названием, готовностью к действию и числом активных связей без '
        'снятия отметки, а действие строки открывает её намерение: $code', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await _start(tester, locale);
      final l10n = app.l10n;
      await _until(tester, _row(_rows.last.number));
      final marks = storedFavoriteMarks(app.raw);

      final traversal = tester.semantics
          .simulatedAccessibilityTraversal()
          .toList();
      final labels = [for (final row in _rows) _rowLabel(l10n, row)];
      expect([
        for (final node in traversal)
          if (labels.contains(node.label)) node.label,
      ], labels);
      for (final row in _rows) {
        _expectRowAnnounced(tester, l10n, row);
      }

      // Действие экранного диктора на второй из тёзок открывает именно её.
      tester.semantics.tap(find.semantics.byLabel(_rowLabel(l10n, _rows[2])));
      await _until(tester, find.byType(IntentionDetailsPage));
      expect(
        app.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        _intentionId(_walk),
      );
      expect(storedFavoriteMarks(app.raw), marks);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('при масштабе текста 2.5 название намерения в каждой строке '
        'Главной показано целиком, а строка доступна касанием и экранному '
        'диктору: $code', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _start(tester, locale, largeText: true);
      final l10n = app.l10n;
      await _until(tester, _row(_rows.first.number));

      for (final row in _rows) {
        // Строка с увеличенным текстом может быть выше области просмотра:
        // человек прокручивает список до названия намерения.
        final finder = _row(row.number);
        final title = find.descendant(
          of: finder,
          matching: find.text(row.title),
        );
        await tester.scrollUntilVisible(
          title,
          100,
          scrollable: _homeScrollable,
          maxScrolls: 100,
        );
        await tester.pumpAndSettle();
        _expectNotTruncated(tester, title);
        final viewport = tester.getRect(_homeScrollable);
        final titleRect = tester.getRect(title);
        expect(titleRect.top, greaterThanOrEqualTo(viewport.top));
        expect(titleRect.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(
          viewport.bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(AppNavigationBar)).top),
        );
        _expectTappable(tester, finder);
        _expectRowAnnounced(tester, l10n, row);
      }
      await _expectGuidelines(tester);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('смена языка интерфейса меняет только системные строки '
        'Главной: названия намерений, отметки и порядок списка прежние: '
        '$code → ${otherLocale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _start(tester, locale);
      await _until(tester, _row(_rows.last.number));
      final marks = storedFavoriteMarks(app.raw);
      _expectRows(tester, app.l10n);

      tester.platformDispatcher.localesTestValue = [otherLocale];
      await tester.pumpAndSettle();

      final otherL10n = lookupAppLocalizations(otherLocale);
      _expectRows(tester, otherL10n);
      expect(
        find.descendant(
          of: find.byType(HomePage),
          matching: find.text(otherL10n.homeFavoritesHeading),
        ),
        findsOneWidget,
      );
      expect(find.text(app.l10n.homeFavoritesHeading), findsNothing);
      expect(storedFavoriteMarks(app.raw), marks);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('загрузка объявляется живой областью и при масштабе текста 2.5 '
        'показана целиком: $code', (tester) async {
      final semantics = tester.ensureSemantics();
      final faults = _FavoriteStorageFaults()..holdNextRead();
      final app = await _start(tester, locale, largeText: true, faults: faults);
      final l10n = app.l10n;

      // Чтение дошло до хранилища и задержано: Главная ждёт его результата.
      await _waitFor(tester, () => faults.isHolding);
      expect(find.text(l10n.homeLoading), findsOneWidget);
      _expectLiveRegion(tester, l10n.homeLoading);
      _expectNotTruncated(tester, find.text(l10n.homeLoading));
      for (final text in [
        l10n.homeEmptyNoFavorites,
        l10n.homeEmptyAllArchived,
        l10n.homeUnavailable,
      ]) {
        expect(find.text(text), findsNothing);
      }

      faults.releaseRead();
      await _until(tester, _row(_rows.first.number));
      expect(find.text(l10n.homeLoading), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    for (final (reason, favorites, archived) in [
      ('избранных намерений нет', const <int>[], const <int>{}),
      ('все избранные намерения в архиве', const [_walk], const {_walk}),
    ]) {
      testWidgets('пустое состояние «$reason» объявляется живой областью, а '
          'объяснение и переход к графу намерений при масштабе текста 2.5 '
          'показаны целиком и доступны: $code', (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await _start(
          tester,
          locale,
          largeText: true,
          favorites: favorites,
          archived: archived,
        );
        final l10n = app.l10n;
        final message = favorites.isEmpty
            ? l10n.homeEmptyNoFavorites
            : l10n.homeEmptyAllArchived;

        await _until(tester, find.text(message));
        _expectLiveRegion(tester, message);
        _expectNotTruncated(tester, find.text(message));
        final open = find.widgetWithText(
          FilledButton,
          l10n.homeOpenIntentionGraph,
        );
        await _expectAction(tester, open, l10n.homeOpenIntentionGraph);
        await _expectGuidelines(tester);

        await tester.tap(open);
        await _until(tester, find.byType(IntentionCatalogPage));
        expect(
          tester
              .widget<AppNavigationBar>(find.byType(AppNavigationBar))
              .selected,
          AppDestination.intentionGraph,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }

    for (final failure in _Failure.values) {
      final retry = failure == _Failure.unavailable;

      testWidgets('отказ первоначального получения «${failure.description}» '
          'объявляется живой областью, а причина${retry ? ' и повтор' : ''} '
          'при масштабе текста 2.5 показаны целиком и доступны: $code', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final faults = _FavoriteStorageFaults()..failNextRead(failure);
        final app = await _start(
          tester,
          locale,
          largeText: true,
          faults: faults,
        );
        final l10n = app.l10n;
        final message = switch (failure) {
          _Failure.unavailable => l10n.homeUnavailable,
          _Failure.corruption => l10n.homeCorruption,
          _Failure.unexpected => l10n.homeUnexpected,
        };

        await _until(tester, find.text(message));
        _expectLiveRegion(tester, message);
        _expectNotTruncated(tester, find.text(message));
        for (final text in [
          l10n.homeEmptyNoFavorites,
          l10n.homeEmptyAllArchived,
          l10n.homeOpenIntentionGraph,
        ]) {
          expect(find.text(text), findsNothing);
        }
        final retryButton = find.widgetWithText(FilledButton, l10n.commonRetry);
        if (!retry) {
          expect(retryButton, findsNothing);
          await _expectGuidelines(tester);
          expect(tester.takeException(), isNull);
          semantics.dispose();
          return;
        }

        await _expectAction(tester, retryButton, l10n.commonRetry);
        await _expectGuidelines(tester);
        await tester.tap(retryButton);
        await _until(tester, _row(_rows.first.number));
        expect(find.text(message), findsNothing);
        expect(faults.reads, 2);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });

      testWidgets('пометка «не обновлён» после отказа обновления '
          '«${failure.description}» объявляется живой областью, а причина'
          '${retry ? ' и повтор' : ''} при масштабе текста 2.5 показаны '
          'целиком и доступны: $code', (tester) async {
        final semantics = tester.ensureSemantics();
        final faults = _FavoriteStorageFaults();
        final app = await _start(
          tester,
          locale,
          largeText: true,
          faults: faults,
        );
        final l10n = app.l10n;
        final message = switch (failure) {
          _Failure.unavailable => l10n.homeRefreshUnavailable,
          _Failure.corruption => l10n.homeRefreshCorruption,
          _Failure.unexpected => l10n.homeRefreshUnexpected,
        };
        await _until(tester, _row(_rows.first.number));

        // Подтверждённая отметка «Читать» требует обновления списка.
        faults.failNextRead(failure);
        unawaited(
          (app.runtime.commandCoordinator.acceptExisting(
            MarkIntentionFavorite(_intentionId(_read)),
            presentationTitle: 'Читать',
          ) as IntentionCommandAccepted).future,
        );
        await _until(tester, find.text(message));
        // Сообщение об успешной отметке уходит с общей поверхности и
        // перестаёт закрывать список.
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);

        _expectLiveRegion(tester, message);
        _expectNotTruncated(tester, find.text(message));
        _expectOnScreen(tester, find.text(message));
        // Прежний подтверждённый список остаётся доступным под пометкой:
        // человек прокручивает его, а пометка остаётся на месте.
        final markRect = tester.getRect(find.text(message));
        await tester.scrollUntilVisible(
          _row(_rows.first.number),
          100,
          scrollable: _homeScrollable,
          maxScrolls: 100,
        );
        await tester.pumpAndSettle();
        _expectTappable(tester, _row(_rows.first.number));
        expect(tester.getRect(find.text(message)), markRect);
        final retryButton = find.widgetWithText(FilledButton, l10n.commonRetry);
        if (!retry) {
          expect(retryButton, findsNothing);
          expect(tester.takeException(), isNull);
          semantics.dispose();
          return;
        }

        await _expectAction(tester, retryButton, l10n.commonRetry);
        await tester.tap(retryButton);
        await _waitFor(tester, () => find.text(message).evaluate().isEmpty);
        await tester.scrollUntilVisible(
          _row(_read),
          100,
          scrollable: _homeScrollable,
          maxScrolls: 100,
        );
        expect(faults.reads, 3);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }

    testWidgets('экранный диктор перемещает строки Главной системными '
        'действиями без перетаскивания, а новое место объявляется живой '
        'областью только после подтверждения записи: $code', (tester) async {
      final semantics = tester.ensureSemantics();
      final faults = _FavoriteStorageFaults();
      final app = await _start(tester, locale, faults: faults);
      final l10n = app.l10n;
      await _until(tester, _row(_rows.last.number));
      final actions = _systemActions(tester);

      // Невозможных действий у крайних строк нет.
      expect(_moveActions(l10n, _rows[0]), {
        actions.reorderItemDown,
        actions.reorderItemToEnd,
      });
      expect(_moveActions(l10n, _rows[1]), {
        actions.reorderItemToStart,
        actions.reorderItemUp,
        actions.reorderItemDown,
        actions.reorderItemToEnd,
      });
      expect(_moveActions(l10n, _rows[2]), {
        actions.reorderItemToStart,
        actions.reorderItemUp,
      });

      // Первая «Гулять» — на одно место ниже; хранилище задерживает запись.
      faults.holdNextPlaceWrite();
      tester.semantics.customAction(
        _rowNode(l10n, _rows[0]),
        CustomSemanticsAction(label: actions.reorderItemDown),
      );
      await _waitFor(tester, () => faults.isHoldingPlaceWrite);

      _expectTraversal(tester, [
        _rowLabel(l10n, _rows[1]),
        _rowLabel(l10n, _rows[0], saving: true),
        _rowLabel(l10n, _rows[2]),
      ]);
      expect(
        find.semantics.byAction(SemanticsAction.customAction),
        findsNothing,
      );
      expect(_announcements(l10n), findsNothing);
      expect(_storedOrder(app), [_otherWalk, _long, _walk]);

      faults.releasePlaceWrite();
      await _waitFor(tester, () => _announcements(l10n).evaluate().isNotEmpty);

      final first = _announcements(l10n).evaluate().single;
      expect(first.label, l10n.homeReorderMoved('Гулять', 2, 3));
      expect(first.flagsCollection.isLiveRegion, isTrue);
      expect(_storedOrder(app), [_long, _otherWalk, _walk]);
      _expectTraversal(tester, [
        for (final row in [_rows[1], _rows[0], _rows[2]]) _rowLabel(l10n, row),
      ]);
      // Успех предъявляется новым порядком, без сообщения на экране.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(first.label), findsNothing);

      // Вторая «Гулять» — на одно место выше: то же место и тот же текст
      // объявляются заново.
      tester.semantics.customAction(
        _rowNode(l10n, _rows[2]),
        CustomSemanticsAction(label: actions.reorderItemUp),
      );
      await _waitFor(
        tester,
        () =>
            _announcements(l10n).evaluate().any((node) => node.id != first.id),
      );

      expect(
        _announcements(l10n).evaluate().single.label,
        l10n.homeReorderMoved('Гулять', 2, 3),
      );
      expect(_storedOrder(app), [_long, _walk, _otherWalk]);
      _expectTraversal(tester, [
        for (final row in [_rows[1], _rows[2], _rows[0]]) _rowLabel(l10n, row),
      ]);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('при масштабе текста 2.5 ручки, длинное название и состояние '
        'сохранения строк Главной показаны целиком и доступны: $code', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final faults = _FavoriteStorageFaults();
      final app = await _start(tester, locale, largeText: true, faults: faults);
      final l10n = app.l10n;
      await _until(tester, _row(_rows.first.number));

      for (final row in _rows) {
        final handle = find.descendant(
          of: _row(row.number),
          matching: find.byTooltip(l10n.homeReorderHandleTooltip),
        );
        await tester.scrollUntilVisible(
          handle,
          100,
          scrollable: _homeScrollable,
          maxScrolls: 100,
        );
        await tester.pumpAndSettle();
        _expectInHomeList(tester, handle);
        _expectTappable(tester, handle);
        expect(tester.getSize(handle).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(handle).height, greaterThanOrEqualTo(48));
      }

      // Строка с длинным названием — на одно место ниже; запись задержана.
      faults.holdNextPlaceWrite();
      tester.semantics.customAction(
        _rowNode(l10n, _rows[1]),
        CustomSemanticsAction(label: _systemActions(tester).reorderItemDown),
      );
      await _waitFor(tester, () => faults.isHoldingPlaceWrite);

      for (final text in [l10n.homeReorderSaving, _longTitle]) {
        final finder = find.descendant(
          of: _row(_long),
          matching: find.text(text),
        );
        await tester.scrollUntilVisible(
          finder,
          100,
          scrollable: _homeScrollable,
          maxScrolls: 100,
        );
        await tester.pumpAndSettle();
        _expectNotTruncated(tester, finder);
        _expectInHomeList(tester, finder);
      }
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      await _expectGuidelines(tester);

      faults.releasePlaceWrite();
      await _waitFor(
        tester,
        () => find.text(l10n.homeReorderSaving).evaluate().isEmpty,
      );
      expect(_storedOrder(app), [_otherWalk, _walk, _long]);
      expect(_displayedOrder(app), [_otherWalk, _walk, _long]);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('отказ перестановки возвращает подтверждённый порядок, а его '
        'единственное сообщение объявляется живой областью и при масштабе '
        'текста 2.5 показано целиком над панелью: $code', (tester) async {
      final semantics = tester.ensureSemantics();
      final faults = _FavoriteStorageFaults()
        ..failNextPlaceWrite(_Failure.unavailable);
      final app = await _start(tester, locale, largeText: true, faults: faults);
      final l10n = app.l10n;
      final message = l10n.favoriteOrderUnavailable;
      await _until(tester, _row(_rows.first.number));

      tester.semantics.customAction(
        _rowNode(l10n, _rows[0]),
        CustomSemanticsAction(label: _systemActions(tester).reorderItemDown),
      );
      await _until(tester, find.text(message));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      _expectLiveRegion(tester, message);
      _expectNotTruncated(tester, find.text(message));
      _expectOnScreen(tester, find.text(message));
      expect(_storedOrder(app), [_otherWalk, _long, _walk]);
      expect(_displayedOrder(app), [_otherWalk, _long, _walk]);
      expect(find.text(l10n.homeReorderSaving), findsNothing);
      expect(_announcements(l10n), findsNothing);

      // Предъявленное сообщение уходит и не повторяется.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('смена языка после перестановки человеком переводит названия '
        'действий перемещения, но не меняет названия намерений и порядок: '
        '$code → ${otherLocale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _start(tester, locale);
      await _until(tester, _row(_rows.last.number));
      tester.semantics.customAction(
        _rowNode(app.l10n, _rows[2]),
        CustomSemanticsAction(label: _systemActions(tester).reorderItemToStart),
      );
      await _waitFor(
        tester,
        () => _announcements(app.l10n).evaluate().isNotEmpty,
      );
      final order = [_walk, _otherWalk, _long];
      expect(_storedOrder(app), order);

      tester.platformDispatcher.localesTestValue = [otherLocale];
      await tester.pumpAndSettle();

      final otherL10n = lookupAppLocalizations(otherLocale);
      final otherActions = _systemActions(tester);
      final shown = [_rows[2], _rows[0], _rows[1]];
      _expectTraversal(tester, [
        for (final row in shown) _rowLabel(otherL10n, row),
      ]);
      expect(_moveActions(otherL10n, shown.first), {
        otherActions.reorderItemDown,
        otherActions.reorderItemToEnd,
      });
      expect(_moveActions(otherL10n, shown.last), {
        otherActions.reorderItemToStart,
        otherActions.reorderItemUp,
      });
      for (final row in shown) {
        expect(
          find.descendant(of: _row(row.number), matching: find.text(row.title)),
          findsOneWidget,
        );
      }
      expect(_storedOrder(app), order);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

final class _App {
  _App(this.runtime, this.raw, this.container, this.l10n);

  final AppRuntime runtime;
  final sqlite.Database raw;
  final ProviderContainer container;
  final AppLocalizations l10n;

  AppRouter get router => container.read(appRouterProvider);
}

/// Запускает приложение на хранилище в памяти с графом [_seedGraph] и ждёт
/// Главную. [faults] управляет чтениями списка Главной.
Future<_App> _start(
  WidgetTester tester,
  Locale locale, {
  bool largeText = false,
  List<int> favorites = _favorites,
  Set<int> archived = const {},
  _FavoriteStorageFaults? faults,
}) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (largeText) {
    tester.platformDispatcher.textScaleFactorTestValue = _textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  late sqlite.Database raw;
  final observer = faults ?? _FavoriteStorageFaults();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openInMemoryLocalDatabase(setup: (database) => raw = database),
      observer,
    ),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    observer
      ..releaseRead()
      ..releasePlaceWrite();
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  _seedGraph(raw, favorites: favorites, archived: archived);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  return _App(runtime, raw, ready.container, lookupAppLocalizations(locale));
}

/// Пять намерений и три активные связи; [favorites] отмечены в этом порядке,
/// [archived] архивированы.
void _seedGraph(
  sqlite.Database database, {
  required List<int> favorites,
  required Set<int> archived,
}) {
  for (final (number, title, isReady) in [
    (_long, _longTitle, true),
    (_walk, 'Гулять', false),
    (_otherWalk, 'Гулять', true),
    (_read, 'Читать', true),
    (_sleep, 'Спать', true),
  ]) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        title,
        isReady ? 1 : 0,
        archived.contains(number) ? 1 : 0,
        number,
        number,
      ],
    );
  }
  for (final (number, source, related, type) in [
    (101, _long, _read, 'need'),
    (102, _long, _sleep, 'can'),
    (103, _otherWalk, _read, 'need'),
  ]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, '
      'related_intention_id, type, priority, is_archived) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(source),
        tagFixtureId(related),
        type,
        2,
        0,
      ],
    );
  }
  for (final (index, intention) in favorites.indexed) {
    storeFavoriteMark(
      database,
      intentionId: tagFixtureId(intention),
      position: index + 1,
    );
  }
}

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

/// Строка Главной намерения [number].
Finder _row(int number) => find.byKey(ValueKey(_intentionId(number)));

/// Прокрутка списка избранных намерений, а не места пометки над ним.
final _homeScrollable = find.descendant(
  of: find.byKey(const PageStorageKey<String>('home-favorite-intentions')),
  matching: find.byType(Scrollable),
);

/// Название, готовность и число активных связей строки — так строку
/// объявляет экранный диктор.
String _rowLabel(AppLocalizations l10n, _Row row, {bool saving = false}) => [
  row.title,
  row.isReady ? l10n.catalogReady : l10n.catalogNotReady,
  if (saving) l10n.homeReorderSaving,
  l10n.intentionActiveRelationCount(row.relations),
].join('\n');

/// Узел строки Главной, которым её объявляет экранный диктор.
SemanticsFinder _rowNode(AppLocalizations l10n, _Row row) =>
    find.semantics.byLabel(_rowLabel(l10n, row));

/// Системные названия действий перемещения на текущем языке интерфейса.
WidgetsLocalizations _systemActions(WidgetTester tester) =>
    WidgetsLocalizations.of(tester.element(find.byType(HomePage)));

/// Названия действий перемещения, которые узел строки предлагает экранному
/// диктору.
Set<String> _moveActions(AppLocalizations l10n, _Row row) => {
  for (final id
      in _rowNode(
            l10n,
            row,
          ).evaluate().single.getSemanticsData().customSemanticsActionIds ??
          const <int>[])
    CustomSemanticsAction.getAction(id)!.label!,
};

/// Узлы с объявлением нового места любого показанного намерения.
SemanticsFinder _announcements(AppLocalizations l10n) {
  final announcements = {
    for (final row in _rows)
      for (var position = 1; position <= _rows.length; position++)
        l10n.homeReorderMoved(row.title, position, _rows.length),
  };
  return find.semantics.byPredicate(
    (node) => announcements.contains(node.label),
  );
}

/// Экранный диктор проходит строки Главной [labels] в этом порядке.
void _expectTraversal(WidgetTester tester, List<String> labels) {
  expect([
    for (final node in tester.semantics.simulatedAccessibilityTraversal())
      if (labels.contains(node.label)) node.label,
  ], labels);
}

/// Номера избранных намерений в сохранённом порядке.
List<int> _storedOrder(_App app) => [
  for (final (id, _) in storedFavoriteMarks(app.raw))
    [
      _long,
      _walk,
      _otherWalk,
      _read,
      _sleep,
    ].firstWhere((number) => tagFixtureId(number) == id),
];

/// Номера строк в порядке, который показывает Главная.
List<int> _displayedOrder(_App app) => [
  for (final row
      in (app.container.read(homeViewModelProvider) as HomeList).displayedItems)
    [
      _long,
      _walk,
      _otherWalk,
    ].firstWhere((number) => _intentionId(number) == row.id),
];

/// Элемент целиком в видимой части списка Главной над панелью.
void _expectInHomeList(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final viewport = tester.getRect(_homeScrollable);
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(viewport.top));
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(_screen.width));
  expect(
    viewport.bottom,
    lessThanOrEqualTo(tester.getRect(find.byType(AppNavigationBar)).top),
  );
}

/// Строка объявляется одним узлом с названием, готовностью и числом
/// активных связей и открывает намерение: снятия отметки и отдельных
/// элементов с действиями в строке нет.
void _expectRowAnnounced(WidgetTester tester, AppLocalizations l10n, _Row row) {
  final finder = _row(row.number);
  final node = tester.getSemantics(
    find.descendant(of: finder, matching: find.byType(IntentionSummaryView)),
  );
  expect(node.label, _rowLabel(l10n, row));
  final data = node.getSemanticsData();
  expect(data.hasAction(SemanticsAction.tap), isTrue);
  for (final action in [SemanticsAction.longPress, SemanticsAction.dismiss]) {
    expect(data.hasAction(action), isFalse, reason: '$action');
  }
  expect(
    find.descendant(of: finder, matching: find.byType(IconButton)),
    findsNothing,
  );
  expect(
    find.descendant(of: finder, matching: find.byIcon(Icons.star)),
    findsNothing,
  );
}

/// Главная показывает строки в порядке списка с названиями без изменения и
/// системными строками языка [l10n].
void _expectRows(WidgetTester tester, AppLocalizations l10n) {
  final traversal = tester.semantics.simulatedAccessibilityTraversal();
  final labels = [for (final row in _rows) _rowLabel(l10n, row)];
  expect([
    for (final node in traversal)
      if (labels.contains(node.label)) node.label,
  ], labels);
  for (final row in _rows) {
    expect(
      find.descendant(of: _row(row.number), matching: find.text(row.title)),
      findsOneWidget,
    );
  }
}

/// Текст [message] объявляется живой областью целиком.
void _expectLiveRegion(WidgetTester tester, String message) {
  final node = tester.getSemantics(find.text(message));
  expect(node.flagsCollection.isLiveRegion, isTrue);
  expect(node.label, message);
}

/// Кнопка [button] с подписью [label] доводится до видимости, показана
/// целиком, достижима касанием и объявляется кнопкой с действием.
Future<void> _expectAction(
  WidgetTester tester,
  Finder button,
  String label,
) async {
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  _expectOnScreen(tester, button);
  _expectTappable(tester, button);
  _expectNotTruncated(
    tester,
    find.descendant(of: button, matching: find.text(label)),
  );
  expect(
    tester.getSemantics(button),
    isSemantics(
      label: label,
      isButton: true,
      isEnabled: true,
      hasTapAction: true,
    ),
  );
}

Future<void> _expectGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Элемент целиком на экране и над панелью.
void _expectOnScreen(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(_screen.width));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(
    rect.bottom,
    lessThanOrEqualTo(tester.getRect(find.byType(AppNavigationBar)).top),
  );
}

/// Касание по видимой части элемента приходится на него.
///
/// Точка касания ищется на вертикальной оси элемента, начиная с его центра:
/// строка у края области просмотра видна и доступна только частью.
void _expectTappable(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final box = tester.renderObject<RenderBox>(finder);
  final rect = box.localToGlobal(Offset.zero) & box.size;
  bool hits(double dy) =>
      dy >= 0 &&
      dy < _screen.height &&
      tester
          .hitTestOnBinding(Offset(rect.center.dx, dy))
          .path
          .any((entry) => identical(entry.target, box));
  var tappable = hits(rect.center.dy);
  for (var dy = rect.top + 4; !tappable && dy < rect.bottom; dy += 8) {
    tappable = hits(dy);
  }
  expect(tappable, isTrue, reason: 'Касание не достигает элемента: $finder');
}

/// Текст показан целиком: переносится, а не обрезается.
void _expectNotTruncated(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNull);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  expect(paragraph.maxLines, isNull);
  expect(paragraph.didExceedMaxLines, isFalse);
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Продвигает кадры и реальное время хранилища, пока не выполнится [done].
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

/// Управляет на уровне хранилища чтениями списка Главной и записью мест
/// перестановки: задерживает или отказывает ближайшему из них. Остальные
/// чтения и записи не затрагиваются, а отказ классифицирует сам адаптер.
final class _FavoriteStorageFaults extends LocalDatabaseConnectionObserver {
  Completer<void>? _nextHold;
  Completer<void>? _held;
  _Failure? _nextFailure;
  Completer<void>? _nextWriteHold;
  Completer<void>? _heldWrite;
  _Failure? _nextWriteFailure;

  /// Число чтений списка Главной, дошедших до хранилища.
  var reads = 0;

  void holdNextRead() => _nextHold = Completer<void>();

  /// Задержанное чтение дошло до хранилища и ждёт [releaseRead].
  bool get isHolding => _held != null;

  void releaseRead() {
    final held = _held;
    _held = null;
    if (held != null && !held.isCompleted) held.complete();
  }

  void failNextRead(_Failure failure) => _nextFailure = failure;

  void holdNextPlaceWrite() => _nextWriteHold = Completer<void>();

  /// Задержанная запись мест дошла до хранилища и ждёт [releasePlaceWrite].
  bool get isHoldingPlaceWrite => _heldWrite != null;

  void releasePlaceWrite() {
    final held = _heldWrite;
    _heldWrite = null;
    if (held != null && !held.isCompleted) held.complete();
  }

  void failNextPlaceWrite(_Failure failure) => _nextWriteFailure = failure;

  @override
  FutureOr<void> beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select &&
        statement.statements.any(
          (sql) => sql.startsWith('UPDATE favorite_intentions'),
        )) {
      return _intercept(
        failure: _nextWriteFailure,
        clearFailure: () => _nextWriteFailure = null,
        hold: _nextWriteHold,
        holdTaken: (hold) {
          _nextWriteHold = null;
          _heldWrite = hold;
        },
      );
    }
    // Чтение порядка внутри перестановки названий намерений не читает.
    if (statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.any(
          (sql) =>
              sql.contains('FROM favorite_intentions f') &&
              sql.contains('i.title'),
        )) {
      return null;
    }
    reads++;
    return _intercept(
      failure: _nextFailure,
      clearFailure: () => _nextFailure = null,
      hold: _nextHold,
      holdTaken: (hold) {
        _nextHold = null;
        _held = hold;
      },
    );
  }

  FutureOr<void> _intercept({
    required _Failure? failure,
    required void Function() clearFailure,
    required Completer<void>? hold,
    required void Function(Completer<void> hold) holdTaken,
  }) {
    if (failure != null) {
      clearFailure();
      throw switch (failure) {
        _Failure.unavailable => sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
          message: 'Управляемая недоступность хранилища избранного',
        ),
        _Failure.corruption => sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
          message: 'Управляемое повреждение хранилища избранного',
        ),
        _Failure.unexpected => StateError(
          'Управляемый непредвиденный отказ хранилища избранного',
        ),
      };
    }
    if (hold == null) return null;
    holdTaken(hold);
    return hold.future;
  }
}
