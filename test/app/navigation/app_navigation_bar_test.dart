import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';

const _russianNames = {
  AppDestination.home: 'Главная',
  AppDestination.dailyChoices: 'Дневные выборы',
  AppDestination.intentionGraph: 'Граф намерений',
};

const _englishNames = {
  AppDestination.home: 'Home',
  AppDestination.dailyChoices: 'Daily choices',
  AppDestination.intentionGraph: 'Intention graph',
};

const _outlinedIcons = {
  AppDestination.home: Icons.home_outlined,
  AppDestination.dailyChoices: Icons.calendar_month_outlined,
  AppDestination.intentionGraph: Icons.hub_outlined,
};

const _filledIcons = {
  AppDestination.home: Icons.home,
  AppDestination.dailyChoices: Icons.calendar_month,
  AppDestination.intentionGraph: Icons.hub,
};

final _locales = {
  const Locale('ru'): _russianNames,
  const Locale('en'): _englishNames,
};

void main() {
  for (final mode in QuickCreationMode.values) {
    final modeName = switch (mode) {
      QuickCreationMode.intention => 'Новое намерение',
      QuickCreationMode.relation => 'Новая связь',
      QuickCreationMode.dailyChoiceFromIntention =>
        'Дневной выбор от намерения',
      QuickCreationMode.dailyChoiceFromAction => 'Дневной выбор от действия',
    };
    testWidgets(
      'режим $modeName: создание и смена режима — отдельные действия',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var launches = 0;
        var menus = 0;
        final selections = <AppDestination>[];
        await tester.pumpWidget(
          _testApp(
            locale: const Locale('ru'),
            quickCreationMode: mode,
            onQuickCreate: () => launches++,
            onChangeQuickCreationMode: () => menus++,
            onSelected: selections.add,
          ),
        );
        final button = find.byType(QuickCreationButton);
        final node = tester.getSemantics(button);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isSelected, Tristate.none);
        expect(node.role, isNot(SemanticsRole.tab));
        expect(node.parent?.role, isNot(SemanticsRole.tabBar));
        expect(appNavigationDestinations(), findsNWidgets(3));
        await tester.tap(button);
        await tester.longPress(button);
        await tester.pumpAndSettle();
        expect(launches, 1);
        expect(menus, 1);
        expect(selections, isEmpty);
        expect(find.byIcon(Icons.home), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  test('пункты идут в порядке Главная, Дневные выборы, Граф намерений', () {
    expect(AppDestination.values, [
      AppDestination.home,
      AppDestination.dailyChoices,
      AppDestination.intentionGraph,
    ]);
  });

  for (final MapEntry(key: locale, value: names) in _locales.entries) {
    group('локаль ${locale.languageCode}', () {
      testWidgets('название пункта берётся из локализации', (tester) async {
        await tester.pumpWidget(_testApp(locale: locale));
        final localizations = AppLocalizations.of(
          tester.element(find.byType(AppNavigationBar)),
        );

        for (final destination in AppDestination.values) {
          expect(destination.title(localizations), names[destination]);
        }
      });

      testWidgets('показывает три пункта слева направо со значками дома, '
          'календаря и графа', (tester) async {
        await tester.pumpWidget(_testApp(locale: locale));

        expect(appNavigationDestinations(), findsNWidgets(3));
        final home = tester.getCenter(find.byIcon(Icons.home));
        final calendar = tester.getCenter(
          find.byIcon(Icons.calendar_month_outlined),
        );
        final graph = tester.getCenter(find.byIcon(Icons.hub_outlined));
        expect(home.dx, lessThan(calendar.dx));
        final quick = tester.getCenter(find.byType(QuickCreationButton));
        final slotWidth =
            tester.getSize(find.byType(AppNavigationBar)).width / 4;
        expect(calendar.dx - home.dx, moreOrLessEquals(slotWidth));
        expect(quick.dx - calendar.dx, moreOrLessEquals(slotWidth));
        expect(graph.dx - quick.dx, moreOrLessEquals(slotWidth));
        expect(find.byType(QuickCreationButton).hitTestable(), findsOneWidget);
        expect(find.byIcon(Icons.account_tree), findsNothing);
        expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
        expect(find.byIcon(Icons.schema), findsNothing);
        expect(find.byIcon(Icons.schema_outlined), findsNothing);
      });

      testWidgets('не показывает текстовых подписей пунктов', (tester) async {
        await tester.pumpWidget(_testApp(locale: locale));

        for (final name in names.values) {
          expect(find.text(name), findsNothing);
        }
      });

      for (final selected in AppDestination.values) {
        testWidgets('выбранный пункт ${selected.name} отличается залитым '
            'значком и индикатором', (tester) async {
          await tester.pumpWidget(_testApp(locale: locale, selected: selected));
          await tester.pumpAndSettle();

          for (final destination in AppDestination.values) {
            final isSelected = destination == selected;
            expect(
              find.byIcon(_filledIcons[destination]!),
              isSelected ? findsOneWidget : findsNothing,
            );
            expect(
              find.byIcon(_outlinedIcons[destination]!),
              isSelected ? findsNothing : findsOneWidget,
            );
            final indicator = tester.widget<NavigationIndicator>(
              find.descendant(
                of: appNavigationDestination(destination),
                matching: find.byType(NavigationIndicator),
              ),
            );
            expect(indicator.animation.value, isSelected ? 1 : 0);
          }
        });
      }

      testWidgets('долгое нажатие показывает подсказку с названием пункта', (
        tester,
      ) async {
        await tester.pumpWidget(_testApp(locale: locale));

        for (final destination in AppDestination.values) {
          final name = names[destination]!;
          expect(find.byTooltip(name), findsOneWidget);

          final gesture = await tester.startGesture(
            tester.getCenter(appNavigationDestination(destination)),
          );
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await gesture.up();
          await tester.pump();

          expect(
            find.descendant(
              of: find.byType(Overlay),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    widget.data == null &&
                    widget.textSpan?.toPlainText() == name,
              ),
            ),
            findsOneWidget,
            reason: name,
          );

          // Подсказка скрывается до проверки следующего пункта.
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      });

      testWidgets('экранный диктор получает название, роль, положение и '
          'признак выбранного пункта', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _testApp(locale: locale, selected: AppDestination.home),
        );
        await tester.pumpAndSettle();
        final material = MaterialLocalizations.of(
          tester.element(find.byType(AppNavigationBar)),
        );

        for (final destination in AppDestination.values) {
          final node = tester.getSemantics(
            appNavigationDestination(destination),
          );
          final position = material.tabLabel(
            tabIndex: destination.index + 1,
            tabCount: 3,
          );

          expect(node.label, '${names[destination]}\n$position');
          expect(node.role, SemanticsRole.tab);
          expect(node.parent?.role, SemanticsRole.tabBar);
          expect(node.flagsCollection.isButton, isTrue);
          expect(
            node.flagsCollection.isSelected,
            destination == AppDestination.home
                ? Tristate.isTrue
                : Tristate.isFalse,
          );
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
        }
        semantics.dispose();
      });

      testWidgets('при масштабе текста 2.5 значки не обрезаются, и каждый '
          'пункт выбирается нажатием', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final selections = <AppDestination>[];
        await tester.pumpWidget(
          _testApp(
            locale: locale,
            textScaler: const TextScaler.linear(2.5),
            onSelected: selections.add,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final barRect = tester.getRect(find.byType(AppNavigationBar));
        for (final destination in AppDestination.values) {
          final icon = destination == AppDestination.home
              ? _filledIcons[destination]!
              : _outlinedIcons[destination]!;
          final iconRect = tester.getRect(find.byIcon(icon));
          expect(iconRect.width, moreOrLessEquals(24));
          expect(iconRect.height, moreOrLessEquals(24));
          expect(
            barRect.contains(iconRect.topLeft) &&
                barRect.contains(iconRect.bottomRight),
            isTrue,
            reason: 'значок $destination выходит за панель',
          );

          await tester.tap(find.byIcon(icon));
        }
        expect(selections, AppDestination.values);
      });
    });
  }

  testWidgets('состав, порядок и значки не зависят от языка интерфейса', (
    tester,
  ) async {
    final layouts = <List<Offset>>[];
    for (final locale in _locales.keys) {
      await tester.pumpWidget(_testApp(locale: locale));
      await tester.pumpAndSettle();
      layouts.add([
        tester.getCenter(find.byIcon(Icons.home)),
        tester.getCenter(find.byIcon(Icons.calendar_month_outlined)),
        tester.getCenter(find.byIcon(Icons.hub_outlined)),
      ]);
    }

    expect(layouts.first, layouts.last);
  });

  testWidgets('нерусская системная локаль получает английские названия', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    for (final name in _englishNames.values) {
      expect(find.byTooltip(name), findsOneWidget);
    }
  });

  testWidgets('высота панели задана явно и не зависит от масштаба текста', (
    tester,
  ) async {
    for (final scale in [1.0, 2.5]) {
      await tester.pumpWidget(
        _testApp(
          locale: const Locale('ru'),
          textScaler: TextScaler.linear(scale),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(AppNavigationBar)).height,
        AppNavigationBar.height,
      );
    }
  });

  testWidgets('сообщает о выборе пункта и сама выбранный пункт не меняет', (
    tester,
  ) async {
    final selections = <AppDestination>[];
    await tester.pumpWidget(
      _testApp(locale: const Locale('ru'), onSelected: selections.add),
    );

    await tester.tap(find.byIcon(Icons.hub_outlined));
    await tester.pumpAndSettle();

    expect(selections, [AppDestination.intentionGraph]);
    // Выбранный пункт задаёт владелец панели: без его решения он прежний.
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.hub_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home));
    expect(selections, [AppDestination.intentionGraph, AppDestination.home]);
  });
}

Widget _testApp({
  Locale? locale,
  AppDestination selected = AppDestination.home,
  ValueChanged<AppDestination>? onSelected,
  TextScaler textScaler = TextScaler.noScaling,
  QuickCreationMode quickCreationMode = QuickCreationMode.intention,
  VoidCallback? onQuickCreate,
  VoidCallback? onChangeQuickCreationMode,
}) {
  return MaterialApp(
    locale: locale,
    localeListResolutionCallback: resolveAppLocale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: AppNavigationBar(
        selected: selected,
        quickCreationMode: quickCreationMode,
        onQuickCreate: onQuickCreate ?? () {},
        onChangeQuickCreationMode: onChangeQuickCreationMode ?? () {},
        onSelected: onSelected ?? (_) {},
      ),
    ),
  );
}
