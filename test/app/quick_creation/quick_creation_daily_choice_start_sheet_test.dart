import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';

const _russianOptions = [
  ('От намерения', 'Сначала намерение, затем действие для него'),
  ('От действия', 'Сначала действие, затем намерение, которому оно служит'),
];

void main() {
  testWidgets('варианты показывают исходные составные значки начала '
      'и шевроны продолжения', (tester) async {
    await _openApp(tester);
    await _openSheet(tester);

    for (final (name, icon) in [
      ('От намерения', DoableIconData.fromIntention),
      ('От действия', DoableIconData.fromAction),
    ]) {
      final row = find.widgetWithText(OptionRow, name);
      expect(
        tester
            .widgetList<DoableIcon>(
              find.descendant(of: row, matching: find.byType(DoableIcon)),
            )
            .map((widget) => widget.icon),
        [icon, DoableIconData.chevronRight],
      );
    }
  });

  for (final (language, title, subtitle, options, chosen, direction) in [
    (
      'ru',
      'Новый дневной выбор',
      'С чего начать',
      _russianOptions,
      0,
      ChoicePathDraftDirection.topDown,
    ),
    (
      'en',
      'New daily choice',
      'Choose where to start',
      [
        ('From an intention', 'Pick an intention, then an action for it'),
        ('From an action', 'Pick an action, then the intention it serves'),
      ],
      1,
      ChoicePathDraftDirection.bottomUp,
    ),
  ]) {
    testWidgets('$language: варианты объявляются кнопками в заданном порядке '
        'и возвращают направление без запуска поиска', (tester) async {
      final app = await _openApp(tester, language: language);
      await _openSheet(tester);

      expect(find.text(title), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);
      for (final (name, hint) in options) {
        expect(find.text(name).hitTestable(), findsOneWidget);
        expect(find.text(hint), findsOneWidget);
        expect(
          tester.getSemantics(find.text(name)),
          matchesSemantics(
            label: '$name\n$hint',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
        );
      }
      expect(
        tester.getTopLeft(find.text(options.first.$1)).dy,
        lessThan(tester.getTopLeft(find.text(options.last.$1)).dy),
      );

      await tester.tap(find.text(options[chosen].$1));
      await tester.pumpAndSettle();
      expect(await app.result, direction);
      app.expectOrigin(tester);
      await tester.tap(find.text('К предыдущей странице'));
      await tester.pumpAndSettle();
      expect(find.text('Открыть страницу'), findsOneWidget);
    });
  }

  for (final dismissal in ['фоном', 'свайпом', 'назад']) {
    testWidgets('закрытие $dismissal возвращает отмену и сохраняет страницу, '
        'ввод и выбранный пункт', (tester) async {
      final app = await _openApp(tester);
      await _openSheet(tester);

      switch (dismissal) {
        case 'фоном':
          await tester.tapAt(const Offset(10, 10));
        case 'свайпом':
          await tester.fling(
            find.text('Новый дневной выбор'),
            const Offset(0, 400),
            1200,
          );
        case 'назад':
          await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(await app.result, isNull);
      app.expectOrigin(tester);
    });
  }

  testWidgets('корневой лист изолирует страницу и внешнюю панель '
      'от нажатий, клавиатуры и экранного диктора', (tester) async {
    final app = await _openApp(tester);
    final clearPosition = tester.getCenter(find.text('Очистить ввод'));
    final homePosition = tester.getCenter(
      appNavigationDestination(AppDestination.home),
    );
    await _openSheet(tester);

    expect(find.semantics.byLabel('Очистить ввод'), findsNothing);
    expect(find.semantics.byLabel(RegExp('Дневные выборы')), findsNothing);
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(app.inputFocus.hasFocus, isFalse);
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<BottomSheet>(),
        isNotNull,
      );
    }

    await tester.tapAt(clearPosition);
    await tester.pumpAndSettle();
    app.expectOrigin(tester);

    await _openSheet(tester);
    await tester.tapAt(homePosition);
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

  testWidgets('оба варианта доступны с увеличенным текстом и системными '
      'отступами на узком экране', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.reset);
    final app = await _openApp(tester, textScale: 2);

    for (final (index, (name, hint)) in _russianOptions.indexed) {
      await _openSheet(tester);
      final scrollable = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      for (final text in [name, hint]) {
        final finder = find.text(text);
        await tester.scrollUntilVisible(finder, 100, scrollable: scrollable);
        await tester.pumpAndSettle();
        expect(
          tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
          isFalse,
        );
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(24));
        expect(rect.top, lessThan(568 - 34));
        // Длинное пояснение может быть выше области прокрутки: доступны
        // начало и конец текста, а вся строка остаётся кнопкой.
        await Scrollable.ensureVisible(tester.element(finder), alignment: 1);
        await tester.pumpAndSettle();
        expect(tester.getRect(finder).bottom, lessThanOrEqualTo(568 - 34));
        expect(finder.hitTestable(), findsOneWidget);
      }
      await tester.tap(find.text(hint));
      await tester.pumpAndSettle();
      expect(await app.result, ChoicePathDraftDirection.values[index]);
      app.expectOrigin(tester);
    }
  });
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Открыть лист'));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
}

Future<_TestApp> _openApp(
  WidgetTester tester, {
  String language = 'ru',
  double textScale = 1,
}) async {
  final app = _TestApp();
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

/// Вложенная страница с вводом и панель вне её навигатора, без данных графа.
final class _TestApp {
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final selected = ValueNotifier(AppDestination.dailyChoices);
  late Future<ChoicePathDraftDirection?> result;

  Widget build(Locale locale, double textScale) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: doableTheme(Brightness.light),
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
            onPressed: () {
              result = showQuickCreationDailyChoiceStartSheet(context);
            },
            child: const Text('Открыть лист'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('К предыдущей странице'),
          ),
        ],
      ),
    ),
  );

  void expectOrigin(WidgetTester tester) {
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Открыть лист'), findsOneWidget);
    expect(find.text('Несохранённое название'), findsOneWidget);
    expect(selected.value, AppDestination.dailyChoices);
    expect(tester.takeException(), isNull);
  }

  void dispose() {
    input.dispose();
    inputFocus.dispose();
    selected.dispose();
  }
}
