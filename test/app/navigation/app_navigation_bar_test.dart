import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
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
  AppDestination.home: DoableIconData.home,
  AppDestination.dailyChoices: DoableIconData.calendarDays,
  AppDestination.intentionGraph: DoableIconData.graph,
};

const _filledIcons = {
  AppDestination.home: DoableIconData.homeFilled,
  AppDestination.dailyChoices: DoableIconData.calendarDaysFilled,
  AppDestination.intentionGraph: DoableIconData.graphFilled,
};

final _locales = {
  const Locale('ru'): _russianNames,
  const Locale('en'): _englishNames,
};

void main() {
  // Режим меняет лишь название и значок кнопки, поэтому достаточно одного.
  testWidgets('создание и смена режима — отдельные действия', (tester) async {
    final semantics = tester.ensureSemantics();
    var launches = 0;
    var menus = 0;
    final selections = <AppDestination>[];
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        quickCreationMode: QuickCreationMode.relation,
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
    expect(_icon(DoableIconData.homeFilled), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  // Устройство панели не зависит от языка: достаточно одной локали.
  group('устройство панели', () {
    const locale = Locale('ru');

    testWidgets('показывает три пункта слева направо со значками дома, '
        'календаря и графа, а за ними — быстрое создание', (tester) async {
      await tester.pumpWidget(_testApp(locale: locale));

      expect(appNavigationDestinations(), findsNWidgets(3));
      final home = tester.getCenter(_icon(DoableIconData.homeFilled));
      final calendar = tester.getCenter(_icon(DoableIconData.calendarDays));
      final graph = tester.getCenter(_icon(DoableIconData.graph));
      final quick = tester.getCenter(find.byType(QuickCreationButton));
      expect(home.dx, lessThan(calendar.dx));
      expect(calendar.dx, lessThan(graph.dx));
      expect(graph.dx, lessThan(quick.dx));
      expect(find.byType(QuickCreationButton).hitTestable(), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      final colors = brightness == Brightness.light
          ? DoableColors.light
          : DoableColors.dark;
      for (final selected in AppDestination.values) {
        testWidgets('пункт ${selected.name} показывает исходные варианты '
            'и цвета значков в теме ${brightness.name}', (tester) async {
          await tester.pumpWidget(
            _testApp(
              locale: locale,
              selected: selected,
              brightness: brightness,
            ),
          );
          await tester.pumpAndSettle();

          for (final destination in AppDestination.values) {
            final isSelected = destination == selected;
            expect(
              _icon(_filledIcons[destination]!),
              isSelected ? findsOneWidget : findsNothing,
            );
            expect(
              _icon(_outlinedIcons[destination]!),
              isSelected ? findsNothing : findsOneWidget,
            );
            final icon = tester.widget<DoableIcon>(
              _icon(
                isSelected
                    ? _filledIcons[destination]!
                    : _outlinedIcons[destination]!,
              ),
            );
            expect(icon.color, isSelected ? colors.ink : colors.muted);
          }
        });
      }
    }

    testWidgets('значки не обрезаются, и каждый '
        'пункт выбирается нажатием', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final selections = <AppDestination>[];
      await tester.pumpWidget(
        _testApp(locale: locale, onSelected: selections.add),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final barRect = tester.getRect(find.byType(AppNavigationBar));
      for (final destination in AppDestination.values) {
        final icon = destination == AppDestination.home
            ? _filledIcons[destination]!
            : _outlinedIcons[destination]!;
        final iconRect = tester.getRect(_icon(icon));
        expect(iconRect.width, moreOrLessEquals(24));
        expect(iconRect.height, moreOrLessEquals(24));
        expect(
          barRect.contains(iconRect.topLeft) &&
              barRect.contains(iconRect.bottomRight),
          isTrue,
          reason: 'значок $destination выходит за панель',
        );

        await tester.tap(appNavigationDestination(destination));
      }
      expect(selections, AppDestination.values);
    });
  });

  for (final MapEntry(key: locale, value: names) in _locales.entries) {
    group('локаль ${locale.languageCode}', () {
      testWidgets('не показывает текстовых подписей пунктов', (tester) async {
        await tester.pumpWidget(_testApp(locale: locale));

        for (final name in names.values) {
          expect(find.text(name), findsNothing);
        }
      });

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
        tester.getCenter(_icon(DoableIconData.homeFilled)),
        tester.getCenter(_icon(DoableIconData.calendarDays)),
        tester.getCenter(_icon(DoableIconData.graph)),
      ]);
    }

    expect(layouts.first, layouts.last);
  });

  testWidgets('сообщает о выборе пункта и сама выбранный пункт не меняет', (
    tester,
  ) async {
    final selections = <AppDestination>[];
    await tester.pumpWidget(
      _testApp(locale: const Locale('ru'), onSelected: selections.add),
    );

    await tester.tap(appNavigationDestination(AppDestination.intentionGraph));
    await tester.pumpAndSettle();

    expect(selections, [AppDestination.intentionGraph]);
    // Выбранный пункт задаёт владелец панели: без его решения он прежний.
    expect(_icon(DoableIconData.homeFilled), findsOneWidget);
    expect(_icon(DoableIconData.graph), findsOneWidget);

    await tester.tap(appNavigationDestination(AppDestination.home));
    expect(selections, [AppDestination.intentionGraph, AppDestination.home]);
  });
}

Finder _icon(DoableIconData icon) => find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == icon,
);

Widget _testApp({
  Locale? locale,
  Brightness brightness = Brightness.light,
  AppDestination selected = AppDestination.home,
  ValueChanged<AppDestination>? onSelected,

  QuickCreationMode quickCreationMode = QuickCreationMode.intention,
  VoidCallback? onQuickCreate,
  VoidCallback? onChangeQuickCreationMode,
}) {
  return MaterialApp(
    locale: locale,
    theme: ThemeData(brightness: brightness),
    localeListResolutionCallback: resolveAppLocale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
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
