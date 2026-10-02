import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_search_layout.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog/catalog_reconciliation_test_support.dart';
import 'catalog/catalog_test_support.dart';
import 'details/details_test_support.dart';

/// Масштаб текста проверки доступности четырёх поисков.
const _textScaler = TextScaler.linear(2.5);

const _screen = Size(420, 900);

const _locales = [Locale('ru'), Locale('en')];

/// Название намерения, которое не помещается в одну строку.
const _longTitle = 'Долгая прогулка до дальнего парка вместе с соседями';

const _favoriteMarkKey = ValueKey('intention-details-favorite-mark');
const _failureKey = ValueKey('intention-details-favorite-mark-failure');
const _retryKey = ValueKey('intention-details-favorite-mark-retry');
const _operationMessageKey = ValueKey('graph-operation-message');

/// Страница поиска намерений и то, чем она отличается от остальных трёх.
final class _SearchPage {
  const _SearchPage({
    required this.name,
    required this.route,
    required this.listKey,
  });

  final String name;

  /// Маршрут поверх каталога; каталог открыт сразу и маршрута не требует.
  final PageRouteInfo? route;
  final String listKey;
}

final _pages = [
  const _SearchPage(
    name: 'каталог намерений',
    route: null,
    listKey: 'intention-catalog-list',
  ),
  const _SearchPage(
    name: 'поиск действия',
    route: DailyChoiceActionPickerRoute(),
    listKey: 'daily-choice-action-list',
  ),
  const _SearchPage(
    name: 'поиск исходного намерения',
    route: DailyChoiceSourcePickerRoute(),
    listKey: 'daily-choice-source-list',
  ),
  _SearchPage(
    name: 'поиск участника долговременной связи',
    route: RelationParticipantPickerRoute(
      excludedIntentionId: testSummary(index: 99).id,
      selectionContext: RelationParticipantSelectionContext.archivedRelation,
    ),
    listKey: 'participant-picker-list',
  ),
];

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final locale in _locales) {
    final otherLocale = _locales.firstWhere((other) => other != locale);

    testWidgets('страница намерения сообщает экранному диктору состояние, '
        'действие и результат отметки и не обрезает их при увеличенном '
        'тексте: ${locale.languageCode}', (tester) async {
      tester.view.physicalSize = _screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final l10n = await AppLocalizations.delegate.load(locale);
      final repository = ControlledDetailsRepository();
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      final intention = testDetailsIntention(index: 130, title: _longTitle);

      await tester.pumpWidget(_detailsApp(container, intention, locale));
      await tester.pump();
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Экранный диктор получает название, состояние и действие управления.
      final control = find.byKey(_favoriteMarkKey);
      _expectFavoriteMarkControl(
        tester,
        l10n,
        FavoriteMark.notFavorite,
        isEnabled: true,
      );
      _expectTappable(tester, control);
      _expectNotTruncated(
        tester,
        find.byKey(const ValueKey('intention-details-title')),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      // Успех объявляет живая область общей поверхности.
      await tester.tap(control);
      await tester.pump();
      expect(repository.commands.single, isA<MarkIntentionFavorite>());
      _expectFavoriteMarkControl(
        tester,
        l10n,
        FavoriteMark.notFavorite,
        isEnabled: false,
      );
      repository.completeCommand(
        0,
        testDetailsSavedResult(
          intention,
          before: intention,
          revision: const TestDetailsRevision(1),
          favoriteMark: FavoriteMark.favorite,
        ),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 2);
      repository.detailRequests[1].add(
        ResultSuccess(intention),
        revision: const TestDetailsRevision(1),
        favoriteMark: FavoriteMark.favorite,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final success = l10n.graphOperationMessage(
        l10n.graphOperationMarkFavorite,
        _longTitle,
        l10n.detailsFavoriteMarked,
      );
      final operationMessage = find.byKey(_operationMessageKey);
      expect(
        tester.getSemantics(operationMessage),
        isSemantics(isLiveRegion: true, label: success),
      );
      _expectNotTruncated(
        tester,
        find.descendant(of: operationMessage, matching: find.text(success)),
      );
      expect(find.byKey(_failureKey), findsNothing);
      _expectFavoriteMarkControl(
        tester,
        l10n,
        FavoriteMark.favorite,
        isEnabled: true,
      );
      _expectTappable(tester, control);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(operationMessage, findsNothing);

      // Отказ объявляет живая область страницы, а не общая поверхность.
      await tester.tap(control);
      await tester.pump();
      expect(repository.commands.last, isA<UnmarkIntentionFavorite>());
      repository.completeCommand(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _expectFavoriteMarkFailure(tester, l10n);
      expect(find.byType(SnackBar), findsNothing);
      _expectFavoriteMarkControl(
        tester,
        l10n,
        FavoriteMark.favorite,
        isEnabled: true,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      // Смена языка меняет только системные строки: название намерения,
      // подтверждённая отметка и показанный отказ остаются прежними.
      final otherL10n = await AppLocalizations.delegate.load(otherLocale);
      await tester.pumpWidget(_detailsApp(container, intention, otherLocale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repository.commands, hasLength(2));
      expect(repository.detailRequests, hasLength(2));
      // Название могло уйти за область просмотра: человек возвращается к
      // нему прокруткой.
      final title = find.byKey(const ValueKey('intention-details-title'));
      await tester.scrollUntilVisible(
        title,
        -150,
        scrollable: _detailsScrollable,
        maxScrolls: 200,
      );
      expect(tester.widget<Text>(title).data, _longTitle);
      _expectNotTruncated(tester, title);
      expect(find.text(otherL10n.detailsTitle), findsOneWidget);
      expect(find.text(l10n.detailsTitle), findsNothing);
      expect(find.text(l10n.detailsFavoriteMarkUnavailable), findsNothing);
      _expectFavoriteMarkControl(
        tester,
        otherL10n,
        FavoriteMark.favorite,
        isEnabled: true,
      );
      await _expectFavoriteMarkFailure(tester, otherL10n);

      // Повтор отправляет ту же операцию и остаётся доступным касанием.
      await tester.tap(find.byKey(_retryKey));
      await tester.pump();
      expect(repository.commands, hasLength(3));
      expect(repository.commands.last, isA<UnmarkIntentionFavorite>());
      repository.completeCommand(
        2,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    for (final page in _pages) {
      testWidgets('${page.name} объявляет отметку вместе с названием '
          'намерения без отдельного фокуса и не обрезает её при увеличенном '
          'тексте: ${locale.languageCode}', (tester) async {
        tester.view.physicalSize = _screen;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        final l10n = await AppLocalizations.delegate.load(locale);
        final repository = ControlledCatalogRepository();
        final container = reconciliationCatalogContainer(repository);
        final router = AppRouter();
        addTearDown(container.dispose);
        addTearDown(router.dispose);
        // Одноимённые намерения различаются только отметкой.
        final items = [
          testSummary(
            index: 4,
            title: _longTitle,
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
          ),
          testSummary(
            index: 3,
            title: _longTitle,
            readiness: IntentionReadiness.ready,
          ),
          testSummary(
            index: 2,
            title: 'Гулять',
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
          ),
        ];

        await tester.pumpWidget(_searchApp(container, router, locale));
        await tester.pump();
        if (page.route case final route?) {
          repository.complete(0, _firstPage(const []));
          await _pumpFrames(tester);
          unawaited(router.push<Object?>(route));
          await _pumpUntilQueries(tester, repository, 2);
        }
        repository.complete(repository.queries.length - 1, _firstPage(items));
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);
        final queries = repository.queries.length;

        await _expectSearchRows(tester, l10n, page, items);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // Смена языка меняет только системные строки: выдача не
        // перечитывается, а названия и отметки остаются прежними.
        final otherL10n = await AppLocalizations.delegate.load(otherLocale);
        await tester.pumpWidget(_searchApp(container, router, otherLocale));
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);
        expect(repository.queries, hasLength(queries));
        await _expectSearchRows(tester, otherL10n, page, items);

        // Поиск отметку не меняет: команд графа нет.
        expect(repository.commands, isEmpty);
        semantics.dispose();
      });
    }
  }
}

Widget _detailsApp(
  ProviderContainer container,
  Intention intention,
  Locale locale,
) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: _textScaler),
      child: GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
    ),
    home: IntentionDetailsPage(intentionId: intention.id),
  ),
);

Widget _searchApp(
  ProviderContainer container,
  AppRouter router,
  Locale locale,
) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: _textScaler),
      child: child!,
    ),
    routerConfig: router.config(),
  ),
);

/// Управление отметкой сообщает название, подтверждённое состояние, действие
/// и доступность и целиком помещается на экране.
void _expectFavoriteMarkControl(
  WidgetTester tester,
  AppLocalizations l10n,
  FavoriteMark confirmed, {
  required bool isEnabled,
}) {
  final control = find.byKey(_favoriteMarkKey);
  final (icon, value, action) = switch (confirmed) {
    FavoriteMark.favorite => (
      Icons.star,
      l10n.detailsFavoriteMarkStateMarked,
      l10n.detailsUnmarkFavoriteAction,
    ),
    FavoriteMark.notFavorite => (
      Icons.star_border,
      l10n.detailsFavoriteMarkStateNotMarked,
      l10n.detailsMarkFavoriteAction,
    ),
  };
  expect(
    tester.getSemantics(control),
    isSemantics(
      label: l10n.detailsFavoriteMarkLabel,
      value: value,
      tooltip: action,
      isButton: true,
      hasEnabledState: true,
      isEnabled: isEnabled,
      hasTapAction: isEnabled,
    ),
  );
  expect(
    find.descendant(of: control, matching: find.byIcon(icon)),
    findsOneWidget,
  );
  _expectOnScreen(tester, control);
}

/// Прокрутка содержимого страницы намерения.
final _detailsScrollable = find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

/// Отказ отметки объявлен живой областью полосы под шапкой, показан целиком
/// без прокрутки и предлагает доступный повтор, а содержимое страницы под
/// полосой остаётся прокручиваемым и доступным.
Future<void> _expectFavoriteMarkFailure(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  final message = l10n.detailsFavoriteMarkUnavailable;
  final failure = find.byKey(_failureKey);
  final retry = find.byKey(_retryKey);

  void expectBanner() {
    final contentTop = tester.getRect(_detailsScrollable).top;
    expect(
      tester.getSemantics(failure),
      isSemantics(isLiveRegion: true, label: message),
    );
    _expectNotTruncated(
      tester,
      find.descendant(of: failure, matching: find.text(message)),
    );
    _expectOnScreen(tester, failure);
    expect(tester.getRect(failure).bottom, lessThanOrEqualTo(contentTop));

    _expectTappable(tester, retry);
    _expectOnScreen(tester, retry);
    expect(tester.getRect(retry).bottom, lessThanOrEqualTo(contentTop));
    expect(
      tester.getSemantics(retry),
      isSemantics(
        label: l10n.commonRetry,
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    _expectNotTruncated(
      tester,
      find.descendant(of: retry, matching: find.text(l10n.commonRetry)),
    );
  }

  expectBanner();

  // Содержимое под полосой прокручивается до области действий и обратно,
  // а полоса остаётся на месте.
  final bannerRect = tester.getRect(failure);
  final position = tester.state<ScrollableState>(_detailsScrollable).position;
  final edit = find.byKey(const ValueKey('intention-details-edit'));
  await tester.scrollUntilVisible(
    edit,
    150,
    scrollable: _detailsScrollable,
    maxScrolls: 200,
  );
  await tester.pumpAndSettle();
  expect(position.pixels, greaterThan(0));
  _expectTappable(tester, edit);
  expect(tester.getRect(failure), bannerRect);
  expectBanner();
}

/// Каждая строка выдачи объявляет отметку вместе с названием одним узлом,
/// а звезда и название показаны целиком.
Future<void> _expectSearchRows(
  WidgetTester tester,
  AppLocalizations l10n,
  _SearchPage page,
  List<IntentionSummary> items,
) async {
  final list = find.byKey(PageStorageKey<String>(page.listKey));
  final mark = l10n.intentionSummaryFavoriteMark;
  for (final summary in items) {
    final row = find.byWidgetPredicate(
      (widget) =>
          widget is IntentionSummaryView &&
          widget.title == summary.title &&
          widget.confirmedFavoriteMark == summary.favoriteMark,
    );
    await _reach(tester, row, within: list);
    _expectTappable(tester, row);
    _expectNotTruncated(
      tester,
      find.descendant(of: row, matching: find.text(summary.title)),
    );

    final rowNode = tester.getSemantics(row);
    expect(rowNode, isSemantics(hasTapAction: true));
    expect(rowNode.label, contains(summary.title));
    final star = find.descendant(of: row, matching: find.byIcon(Icons.star));
    switch (summary.favoriteMark) {
      case FavoriteMark.favorite:
        expect(rowNode.label, contains(mark));
        // Звезда — часть узла строки, а не отдельный фокус или действие.
        expect(tester.getSemantics(star).id, rowNode.id);
        final rowRect = tester.getRect(row);
        final starRect = tester.getRect(star);
        // Звезда растёт вместе с текстом и не заслоняет название.
        expect(starRect.width, _textScaler.scale(24));
        expect(starRect.height, greaterThan(24));
        expect(
          tester
              .getRect(
                find.descendant(of: row, matching: find.text(summary.title)),
              )
              .overlaps(starRect),
          isFalse,
        );
        expect(rowRect.contains(starRect.topLeft), isTrue);
        expect(rowRect.contains(starRect.bottomRight), isTrue);
        expect(starRect.left, greaterThanOrEqualTo(0));
        expect(starRect.right, lessThanOrEqualTo(_screen.width));
      case FavoriteMark.notFavorite:
        expect(rowNode.label, isNot(contains(mark)));
        expect(star, findsNothing);
    }
    expect(
      find.descendant(of: row, matching: find.byType(IconButton)),
      findsNothing,
    );
  }
  expect(find.bySemanticsLabel(mark), findsNothing);
}

/// Общая прокрутка параметров поиска и выдачи страницы поиска.
final _pageScrollable = find
    .descendant(
      of: find.byType(IntentionSearchLayout),
      matching: find.byType(Scrollable),
    )
    .first;

/// Доводит лениво создаваемую строку выдачи до видимой области жестами:
/// прокруткой страницы до списка [within] и самого списка в обе стороны.
Future<void> _reach(
  WidgetTester tester,
  Finder finder, {
  required Finder within,
}) async {
  if (within.evaluate().isEmpty) {
    // Список скрыт за параметрами поиска: сначала прокручивается страница.
    await tester.scrollUntilVisible(
      within,
      150,
      scrollable: _pageScrollable,
      maxScrolls: 200,
    );
  }
  final scrollable = find
      .descendant(of: within, matching: find.byType(Scrollable))
      .first;
  for (final delta in const [-150.0, 150.0]) {
    for (
      var attempt = 0;
      attempt < 100 && finder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(scrollable, Offset(0, delta), warnIfMissed: false);
      await tester.pump();
    }
  }
  expect(finder, findsOneWidget);
  await _pumpFrames(tester);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _pumpFrames(tester);
}

/// Элемент не выходит за горизонтальные границы экрана.
void _expectOnScreen(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(_screen.width));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(_screen.height));
}

/// Касание по видимой части элемента приходится на него.
///
/// Точка касания ищется на вертикальной оси элемента, начиная с его центра:
/// строка выше области просмотра видна и доступна только частью.
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
  expect(paragraph.didExceedMaxLines, isFalse);
}

Result<IntentionCatalogFirstPage> _firstPage(List<IntentionSummary> items) =>
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: items,
        totalCount: items.length,
        nextCursor: null,
        revision: const TestCatalogRevision(0),
      ),
    );

/// Прокачивает кадры и переходы маршрутов без ожидания бесконечных
/// индикаторов загрузки.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<void> _pumpUntilQueries(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (repository.queries.length >= count) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Не дождались $count запросов каталога.');
}
