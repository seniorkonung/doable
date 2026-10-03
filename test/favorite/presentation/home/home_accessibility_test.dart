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
      final faults = _FavoriteReadFaults()..holdNextRead();
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
        final faults = _FavoriteReadFaults()..failNextRead(failure);
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
        final faults = _FavoriteReadFaults();
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
  _FavoriteReadFaults? faults,
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
  final observer = faults ?? _FavoriteReadFaults();
  final runtime = AppRuntime(
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openInMemoryLocalDatabase(setup: (database) => raw = database),
      observer,
    ),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    observer.releaseRead();
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
String _rowLabel(AppLocalizations l10n, _Row row) => [
  row.title,
  row.isReady ? l10n.catalogReady : l10n.catalogNotReady,
  l10n.intentionActiveRelationCount(row.relations),
].join('\n');

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

/// Управляет чтениями списка Главной на уровне хранилища: задерживает или
/// отказывает ближайшему из них. Остальные чтения и записи не затрагиваются,
/// а отказ классифицирует сам адаптер.
final class _FavoriteReadFaults extends LocalDatabaseConnectionObserver {
  Completer<void>? _nextHold;
  Completer<void>? _held;
  _Failure? _nextFailure;

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

  @override
  FutureOr<void> beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.any(
          (sql) => sql.contains('FROM favorite_intentions f'),
        )) {
      return null;
    }
    reads++;
    final failure = _nextFailure;
    if (failure != null) {
      _nextFailure = null;
      throw switch (failure) {
        _Failure.unavailable => sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
          message: 'Управляемая недоступность чтения списка Главной',
        ),
        _Failure.corruption => sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
          message: 'Управляемое повреждение чтения списка Главной',
        ),
        _Failure.unexpected => StateError(
          'Управляемый непредвиденный отказ чтения списка Главной',
        ),
      };
    }
    final hold = _nextHold;
    if (hold == null) return null;
    _nextHold = null;
    _held = hold;
    return hold.future;
  }
}
