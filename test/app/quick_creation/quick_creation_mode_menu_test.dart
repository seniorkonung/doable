import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_menu.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _titles = {
  'ru': [
    'Новое намерение',
    'Новая связь',
    'Дневной выбор от намерения',
    'Дневной выбор от действия',
  ],
  'en': [
    'New intention',
    'New relation',
    'Daily choice from an intention',
    'Daily choice from an action',
  ],
};
const _icons = [
  Icons.circle_outlined,
  Icons.link,
  Icons.arrow_downward,
  Icons.arrow_upward,
];

void main() {
  for (final language in _titles.keys) {
    final titles = _titles[language]!;
    for (final initial in QuickCreationMode.values) {
      testWidgets(
        '$language: четыре режима и выбор из «${titles[initial.index]}» '
        'без запуска создания и изменения исходной истории',
        (tester) async {
          final app = await _openApp(
            tester,
            language: language,
            initial: initial,
          );
          await _openMenu(tester);

          expect(find.byType(ListTile), findsNWidgets(4));
          expect(
            find.text(
              language == 'ru'
                  ? 'Режим быстрого создания'
                  : 'Quick creation mode',
            ),
            findsOneWidget,
          );
          for (var i = 0; i < titles.length; i++) {
            final row = find.ancestor(
              of: find.text(titles[i]),
              matching: find.byType(ListTile),
            );
            expect(
              find.descendant(of: row, matching: find.byIcon(_icons[i])),
              findsOneWidget,
            );
            expect(
              tester.getSemantics(row).flagsCollection.isSelected,
              i == initial.index ? Tristate.isTrue : Tristate.isFalse,
            );
            expect(
              find.descendant(of: row, matching: find.byIcon(Icons.check)),
              i == initial.index ? findsOneWidget : findsNothing,
            );
            if (i > 0) {
              expect(
                tester.getTopLeft(find.text(titles[i])).dy,
                greaterThan(tester.getTopLeft(find.text(titles[i - 1])).dy),
              );
            }
          }

          final next = QuickCreationMode.values[(initial.index + 1) % 4];
          await tester.tap(find.text(titles[next.index]));
          expect(app.mode, next);
          expect(app.store.writes.single.mode, next);
          expect(app.store.writes.single.completion.isCompleted, isFalse);
          await tester.pumpAndSettle();
          app.expectOrigin(tester);

          await _openMenu(tester);
          expect(
            tester
                .getSemantics(find.text(titles[next.index]))
                .flagsCollection
                .isSelected,
            Tristate.isTrue,
          );
          await tester.tap(find.text(titles[next.index]));
          await tester.pumpAndSettle();
          expect(app.mode, next);
          expect(app.store.writes.map((write) => write.mode), [next, next]);
          app.expectOrigin(tester);
        },
      );
    }

    testWidgets('$language: все названия целиком доступны при тексте 2.6 '
        'через прокрутку на узком экране', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.platformDispatcher.textScaleFactorTestValue = 2.6;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await _openApp(tester, language: language);

      for (var i = 0; i < titles.length; i++) {
        await _openMenu(tester);
        final title = find.text(titles[i]);
        final scrollable = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(title, 100, scrollable: scrollable);
        await tester.pumpAndSettle();
        final text = tester.renderObject<RenderParagraph>(title);
        expect(text.didExceedMaxLines, isFalse);
        final rect = tester.getRect(title);
        expect(rect.top, greaterThanOrEqualTo(24));
        expect(rect.bottom, lessThanOrEqualTo(568 - 34));
        expect(title.hitTestable(), findsOneWidget);
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(app.mode, QuickCreationMode.values[i]);
        app.expectOrigin(tester);
      }
    });
  }

  for (final byBack in [false, true]) {
    testWidgets('закрытие ${byBack ? 'назад' : 'фоном'} сохраняет режим, '
        'точную историю, выбранный пункт и ввод', (tester) async {
      final app = await _openApp(
        tester,
        initial: QuickCreationMode.dailyChoiceFromAction,
      );
      await _openMenu(tester);
      if (byBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(10, 10));
      }
      await tester.pumpAndSettle();
      expect(app.mode, QuickCreationMode.dailyChoiceFromAction);
      expect(app.store.writes, isEmpty);
      app.expectOrigin(tester);
    });
  }

  testWidgets('корневой барьер исключает страницу и внешнюю панель '
      'из взаимодействия, фокуса и семантики', (tester) async {
    final app = await _openApp(tester);
    expect(find.semantics.byLabel('Очистить ввод'), findsOneWidget);
    expect(find.semantics.byLabel(RegExp('Дневные выборы')), findsOneWidget);
    await _openMenu(tester);
    expect(app.rootObserver.routes.last, isA<ModalBottomSheetRoute<void>>());
    expect(app.nestedObserver.routes, app.nestedHistory);
    expect(find.semantics.byLabel('Очистить ввод'), findsNothing);
    expect(find.semantics.byLabel(RegExp('Дневные выборы')), findsNothing);

    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(app.inputFocus.hasFocus, isFalse);
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<BottomSheet>(),
        isNotNull,
      );
    }
    await tester.tap(find.text('Очистить ввод'), warnIfMissed: false);
    await tester.pumpAndSettle();
    app.expectOrigin(tester);

    await _openMenu(tester);
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.home_outlined)));
    await tester.pumpAndSettle();
    expect(app.selected.value, AppDestination.dailyChoices);
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    app.expectOrigin(tester);
    expect(find.semantics.byLabel('Очистить ввод'), findsOneWidget);
    expect(find.semantics.byLabel(RegExp('Дневные выборы')), findsOneWidget);
    await tester.tap(find.text('Очистить ввод'));
    expect(app.input.text, isEmpty);
  });

  for (final outcome in [
    const QuickCreationModeSaved(),
    const QuickCreationModeSaveFailed(DiagnosticsFailureCode.unavailable),
  ]) {
    testWidgets(
      'поздний ${outcome is QuickCreationModeSaved ? 'успех' : 'отказ'} '
      'А не меняет Б после повторного открытия меню',
      (tester) async {
        final app = await _openApp(tester);
        await _openMenu(tester);
        await tester.tap(find.text('Новая связь'));
        await tester.pumpAndSettle();
        expect(app.mode, QuickCreationMode.relation);
        await _openMenu(tester);
        await tester.tap(find.text('Дневной выбор от действия'));
        await tester.pumpAndSettle();
        expect(app.mode, QuickCreationMode.dailyChoiceFromAction);
        expect(app.store.writes.map((write) => write.mode), [
          QuickCreationMode.relation,
          QuickCreationMode.dailyChoiceFromAction,
        ]);

        await _openMenu(tester);
        app.store.writes.first.completion.complete(outcome);
        await tester.pumpAndSettle();
        expect(app.mode, QuickCreationMode.dailyChoiceFromAction);
        expect(
          tester
              .getSemantics(find.text('Дневной выбор от действия'))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        expect(find.byType(SnackBar), findsNothing);
        app.store.writes.last.completion.complete(outcome);
        await tester.pumpAndSettle();
        expect(app.mode, QuickCreationMode.dailyChoiceFromAction);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        app.expectOrigin(tester);
      },
    );
  }
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.text('Открыть меню'));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
}

Future<_TestApp> _openApp(
  WidgetTester tester, {
  String language = 'ru',
  QuickCreationMode initial = QuickCreationMode.intention,
}) async {
  final app = _TestApp(initial);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
  await tester.pumpWidget(app.build(Locale(language)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Открыть страницу'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Несохранённое название');
  app.rootHistory = List.of(app.rootObserver.routes);
  app.nestedHistory = List.of(app.nestedObserver.routes);
  return app;
}

/// Меню вызывается из вложенной истории; панель находится вне её навигатора.
final class _TestApp {
  _TestApp(QuickCreationMode initial) {
    container = ProviderContainer(
      overrides: [
        quickCreationModeControllerProvider.overrideWith(
          () => QuickCreationModeController(initialMode: initial, store: store),
        ),
      ],
    );
  }

  final store = _ControlledModeStore();
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final selected = ValueNotifier(AppDestination.dailyChoices);
  final rootObserver = _HistoryObserver();
  final nestedObserver = _HistoryObserver();
  late final ProviderContainer container;
  late List<Route<dynamic>> rootHistory;
  late List<Route<dynamic>> nestedHistory;

  QuickCreationMode get mode =>
      container.read(quickCreationModeControllerProvider);

  Widget build(Locale locale) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [rootObserver],
      home: Scaffold(
        bottomNavigationBar: ValueListenableBuilder(
          valueListenable: selected,
          builder: (_, destination, _) => AppNavigationBar(
            selected: destination,
            quickCreationMode: QuickCreationMode.intention,
            onQuickCreate: () {},
            onChangeQuickCreationMode: () {},
            onSelected: (value) => selected.value = value,
          ),
        ),
        body: Navigator(
          observers: [nestedObserver],
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context)
                    .push<void>(MaterialPageRoute<void>(builder: _originPage)),
                child: const Text('Открыть страницу'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _originPage(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      child: Column(
        children: [
          TextField(controller: input, focusNode: inputFocus),
          TextButton(
            onPressed: input.clear,
            child: const Text('Очистить ввод'),
          ),
          TextButton(
            onPressed: () => showQuickCreationModeMenu(context),
            child: const Text('Открыть меню'),
          ),
        ],
      ),
    ),
  );

  void expectOrigin(WidgetTester tester) {
    expect(find.byType(BottomSheet), findsNothing);
    expect(rootObserver.routes, rootHistory);
    expect(nestedObserver.routes, nestedHistory);
    expect(selected.value, AppDestination.dailyChoices);
    expect(input.text, 'Несохранённое название');
    expect(find.text('Открыть меню'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  void dispose() {
    container.dispose();
    input.dispose();
    inputFocus.dispose();
    selected.dispose();
  }
}

final class _HistoryObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    routes[routes.indexOf(oldRoute!)] = newRoute!;
  }
}

final class _ControlledModeStore implements QuickCreationModeStore {
  final writes =
      <
        ({
          QuickCreationMode mode,
          Completer<QuickCreationModeSaveResult> completion,
        })
      >[];

  @override
  Future<QuickCreationMode> read() async => QuickCreationMode.intention;

  @override
  Future<QuickCreationModeSaveResult> save(QuickCreationMode mode) {
    final completion = Completer<QuickCreationModeSaveResult>();
    writes.add((mode: mode, completion: completion));
    return completion.future;
  }
}
