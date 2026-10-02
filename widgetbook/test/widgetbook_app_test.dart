import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable_widgetbook/favorite/home_row_use_cases.dart';
import 'package:doable_widgetbook/navigation/app_navigation_bar_use_cases.dart';
import 'package:doable_widgetbook/widgetbook_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('панель основной навигации показана с каждым выбранным пунктом '
      'в обеих локалях', (tester) async {
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

        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.selectedIndex, index);
        for (final name in localeNames) {
          expect(find.byTooltip(name), findsOneWidget);
        }
      }
    }
  });

  testWidgets('строка Главной показана в обеих локалях без звезды', (
    tester,
  ) async {
    final useCases = homeRowUseCases();
    expect(useCases.map((useCase) => useCase.name), [
      'Готово к действию',
      'Не готово к действию',
      'Длинное название',
    ]);

    final labels = {
      const Locale('ru'): ['Готово к действию', 'Активных связей: 3'],
      const Locale('en'): ['Ready for action', 'Active relations: 3'],
    };
    for (final MapEntry(key: locale, value: localeLabels) in labels.entries) {
      for (final useCase in useCases) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Builder(builder: useCase.builder)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HomeIntentionRow), findsOneWidget);
        expect(find.byIcon(Icons.star), findsNothing);
        expect(tester.takeException(), isNull);
        if (useCase == useCases.first) {
          expect(find.text('быть здоровым'), findsOneWidget);
          for (final label in localeLabels) {
            expect(find.text(label), findsOneWidget);
          }
        }
      }
    }
  });

  testWidgets('каталог показывает раздел Главной', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WidgetbookApp());
    await tester.pumpAndSettle();

    expect(find.text('Главная'), findsOneWidget);
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
