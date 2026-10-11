import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable_widgetbook/navigation/app_navigation_bar_use_cases.dart';
import 'package:doable_widgetbook/widgetbook_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';

void main() {
  testWidgets('каталог показывает раздел намерений в панели навигации', (
    tester,
  ) async {
    // Панель навигации видна только в настольной компоновке Widgetbook,
    // то есть при ширине окна от 840 логических пикселей.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WidgetbookApp());
    await tester.pumpAndSettle();

    expect(find.text('Намерения'), findsOneWidget);
  });

  testWidgets('панель каждого выбранного пункта показана под обычной страницей '
      'с текстом 2.5 на телефоне в обеих локалях', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final useCases = appNavigationBarUseCases();
    expect(useCases.map((useCase) => useCase.name), [
      'Выбрана Главная',
      'Выбраны Дневные выборы',
      'Выбран Граф намерений',
    ]);

    final names = {
      const Locale('ru'): ['Главная', 'Дневные выборы', 'Граф намерений'],
      const Locale('en'): ['Home', 'Daily choices', 'Intention graph'],
    };
    for (final MapEntry(key: locale, value: localeNames) in names.entries) {
      for (final (index, useCase) in useCases.indexed) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(builder: useCase.builder),
          ),
        );
        await tester.pumpAndSettle();

        final bar = find.byType(AppNavigationBar);
        expect(bar, findsOneWidget);
        final destinations = tester.semantics
            .simulatedAccessibilityTraversal()
            .where((node) => node.role == SemanticsRole.tab)
            .toList();
        expect(destinations, hasLength(3));
        for (final (destinationIndex, node) in destinations.indexed) {
          final position = MaterialLocalizations.of(tester.element(bar))
              .tabLabel(tabIndex: destinationIndex + 1, tabCount: 3);
          expect(node.label, '${localeNames[destinationIndex]}\n$position');
          expect(node.flagsCollection.isButton, isTrue);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(
            node.flagsCollection.isSelected,
            destinationIndex == index ? Tristate.isTrue : Tristate.isFalse,
          );
        }
        final appBar = find.byType(AppBar);
        expect(
          find.descendant(of: appBar, matching: find.text(localeNames[index])),
          findsOneWidget,
        );
        expect(MediaQuery.textScalerOf(tester.element(appBar)).scale(10), 25);
        final barRect = tester.getRect(bar);
        expect(barRect.bottom, 780);
        expect(barRect.height, AppNavigationBar.height);
        expect(
          tester.getBottomLeft(find.byType(SafeArea).first).dy,
          lessThanOrEqualTo(barRect.top),
        );
        for (final icon in tester.widgetList<Icon>(
          find.descendant(
            of: find.byType(AppNavigationBar),
            matching: find.byType(Icon),
          ),
        )) {
          final rect = tester.getRect(find.byWidget(icon));
          expect(barRect.contains(rect.topLeft), isTrue);
          expect(
            barRect.contains(rect.bottomRight - const Offset(0.1, 0.1)),
            isTrue,
          );
        }
        for (final name in localeNames) {
          expect(find.byTooltip(name), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    }
    semantics.dispose();
  });

  testWidgets('каталог позволяет увеличить текст до масштаба 2.5', (
    tester,
  ) async {
    await tester.pumpWidget(const WidgetbookApp());

    final addons = tester.widget<Widgetbook>(find.byType(Widgetbook)).addons;
    final textScale = addons!.whereType<TextScaleAddon>().single;
    expect(textScale.min, 1);
    expect(textScale.max, greaterThanOrEqualTo(2.5));
    expect(textScale.initialScale ?? 1, 1);
  });

  testWidgets('каталог показывает раздел навигации', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WidgetbookApp());
    await tester.pumpAndSettle();

    expect(find.text('Навигация'), findsOneWidget);
  });
}
