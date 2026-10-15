import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_menu.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';

const _titles = {
  'ru': ['Новое намерение', 'Новая связь', 'Новый дневной выбор'],
  'en': ['New intention', 'New relation', 'New daily choice'],
};
const _hints = {
  'ru': [
    'То, что вы хотите сделать или изменить',
    'Чтобы …, нужно или можно …',
    'Действие для намерения в выбранный день',
  ],
  'en': [
    'Something you want to do or change',
    'To …, you need or can …',
    'An action for an intention on a chosen day',
  ],
};

void main() {
  // Выбранная строка определяется индексом режима, а названия — языком: берём
  // по одному режиму на язык.
  for (final (language, initial) in [
    ('ru', QuickCreationMode.intention),
    ('en', QuickCreationMode.dailyChoice),
  ]) {
    final titles = _titles[language]!;
    testWidgets('$language: три режима и выбор из «${titles[initial.index]}» '
        'без запуска создания и изменения исходной истории', (tester) async {
      final app = await _openApp(tester, language: language, initial: initial);
      await _openMenu(tester);

      expect(find.byType(OptionRow), findsNWidgets(3));
      expect(
        find.text(
          language == 'ru' ? 'Что создаёт кнопка' : 'What the button creates',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          language == 'ru'
              ? 'Нажатие на плюс создаст выбранное'
              : 'A tap on plus will create the selected item',
        ),
        findsOneWidget,
      );
      for (var i = 0; i < titles.length; i++) {
        final row = find.widgetWithText(OptionRow, titles[i]);
        final hint = _hints[language]![i];
        expect(
          find.descendant(of: row, matching: find.text(hint)),
          findsOneWidget,
        );
        final semantics = tester.getSemantics(row);
        expect(semantics.label, '${titles[i]}\n$hint');
        expect(semantics.flagsCollection.isButton, isTrue);
        expect(
          semantics.flagsCollection.isFocused,
          i == initial.index ? Tristate.isTrue : Tristate.isFalse,
        );
        expect(
          tester.getSemantics(row).flagsCollection.isSelected,
          i == initial.index ? Tristate.isTrue : Tristate.isFalse,
        );
        if (i > 0) {
          expect(
            tester.getTopLeft(find.text(titles[i])).dy,
            greaterThan(tester.getTopLeft(find.text(titles[i - 1])).dy),
          );
        }
      }

      final next = QuickCreationMode
          .values[(initial.index + 1) % QuickCreationMode.values.length];
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
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.mode, next);
      expect(app.store.writes.map((write) => write.mode), [next, next]);
      app.expectOrigin(tester);
    });
    testWidgets('$language: меню показывает значки режимов и галочку '
        'у «${titles[initial.index]}»', (tester) async {
      await _openApp(tester, language: language, initial: initial);
      await _openMenu(tester);
      const icons = [
        DoableIconData.intention,
        DoableIconData.relation,
        DoableIconData.calendar,
      ];
      for (final (index, title) in titles.indexed) {
        final row = find.widgetWithText(OptionRow, title);
        final leading = find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) => widget is DoableIcon && widget.icon == icons[index],
          ),
        );
        expect(leading, findsOneWidget);
        expect(tester.getSize(leading), const Size.square(22));
        final check = find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DoableIcon && widget.icon == DoableIconData.check,
          ),
        );
        expect(check, index == initial.index ? findsOneWidget : findsNothing);
        if (index == initial.index) {
          expect(tester.getSize(check), const Size.square(20));
        }
      }
    });
  }

  // Самые длинные названия русские, поэтому достаточно русского языка.
  testWidgets('все названия и пояснения целиком доступны '
      'через прокрутку на узком экране с увеличенным текстом', (tester) async {
    const language = 'ru';
    final titles = _titles[language]!;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);

    addTearDown(tester.view.reset);

    final app = await _openApp(tester, language: language, textScale: 2);

    for (var i = 0; i < titles.length; i++) {
      await _openMenu(tester);
      final title = find.text(titles[i]);
      final hint = find.text(_hints[language]![i]);
      final scrollable = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      for (final text in [title, hint]) {
        await tester.scrollUntilVisible(text, 100, scrollable: scrollable);
        await tester.pumpAndSettle();
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
        );
        final rect = tester.getRect(text);
        expect(rect.top, greaterThanOrEqualTo(24));
        expect(rect.top, lessThan(568 - 34));
        await Scrollable.ensureVisible(tester.element(text), alignment: 1);
        await tester.pumpAndSettle();
        expect(tester.getRect(text).bottom, lessThanOrEqualTo(568 - 34));
        expect(text.hitTestable(), findsOneWidget);
      }
      await Scrollable.ensureVisible(tester.element(title), alignment: 0.5);
      await tester.pumpAndSettle();
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
        initial: QuickCreationMode.dailyChoice,
      );
      await _openMenu(tester);
      if (byBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(10, 10));
      }
      await tester.pumpAndSettle();
      expect(app.mode, QuickCreationMode.dailyChoice);
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
    await tester.tapAt(
      tester.getCenter(appNavigationDestination(AppDestination.home)),
    );
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
  double textScale = 1,
}) async {
  final app = _TestApp(initial);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
  await tester.pumpWidget(app.build(Locale(language), textScale));
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

  Widget build(Locale locale, double textScale) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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
