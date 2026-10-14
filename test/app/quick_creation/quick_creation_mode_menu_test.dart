import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_menu.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
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
  // Выбранная строка определяется индексом режима, а названия — языком: берём
  // по одному режиму на язык.
  for (final (language, initial) in [
    ('ru', QuickCreationMode.intention),
    ('en', QuickCreationMode.dailyChoiceFromAction),
  ]) {
    final titles = _titles[language]!;
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

  // Самые длинные названия русские, поэтому достаточно русского языка.
  testWidgets('все названия целиком доступны '
      'через прокрутку на узком экране', (tester) async {
    const language = 'ru';
    final titles = _titles[language]!;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);

    addTearDown(tester.view.reset);

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
  late final ProviderContainer container;

  QuickCreationMode get mode =>
      container.read(quickCreationModeControllerProvider);

  Widget build(Locale locale) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
