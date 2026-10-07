import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable_widgetbook/favorite/home_row_use_cases.dart';
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

        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.selectedIndex, index);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.bottomNavigationBar, isA<AppNavigationBar>());
        final appBar = find.byType(AppBar);
        expect(
          find.descendant(of: appBar, matching: find.text(localeNames[index])),
          findsOneWidget,
        );
        expect(MediaQuery.textScalerOf(tester.element(appBar)).scale(10), 25);
        final barRect = tester.getRect(find.byType(AppNavigationBar));
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
  });

  testWidgets('строка Главной показана в обеих локалях без звезды', (
    tester,
  ) async {
    final useCases = homeRowUseCases();
    expect(useCases.map((useCase) => useCase.name), [
      'Готово к действию',
      'Не готово к действию',
      'Длинное название',
      'Ручка доступна',
      'Ручка недоступна',
      'Новое место сохраняется',
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

  testWidgets('строка Главной показывает доступную и недоступную ручку и '
      'сохранение нового места в обеих локалях', (tester) async {
    final useCases = {
      for (final useCase in homeRowUseCases()) useCase.name: useCase,
    };
    final texts = {
      const Locale('ru'): (
        tooltip: 'Перетащите, чтобы переместить намерение',
        saving: 'Новое место сохраняется…',
      ),
      const Locale('en'): (
        tooltip: 'Drag to move the intention',
        saving: 'Saving the new position…',
      ),
    };
    for (final MapEntry(key: locale, value: text) in texts.entries) {
      for (final (name, movable, saving) in [
        ('Ручка доступна', true, false),
        ('Ручка недоступна', false, false),
        ('Новое место сохраняется', false, true),
      ]) {
        await _pumpUseCase(tester, useCases[name]!, locale);

        final row = find.byType(HomeIntentionRow);
        expect(row, findsOneWidget, reason: name);
        final handle = find.descendant(
          of: row,
          matching: find.byIcon(Icons.drag_handle),
        );
        final theme = Theme.of(tester.element(row));
        expect(
          tester.widget<Icon>(handle).color,
          movable ? isNull : theme.disabledColor,
          reason: name,
        );
        expect(
          find.byType(ReorderableDragStartListener),
          movable ? findsOneWidget : findsNothing,
          reason: name,
        );
        // Доступную ручку строка получает только в переставляемом списке.
        expect(
          find.ancestor(of: row, matching: find.byType(SliverReorderableList)),
          movable ? findsOneWidget : findsNothing,
          reason: name,
        );
        expect(
          find.byTooltip(text.tooltip),
          movable ? findsOneWidget : findsNothing,
          reason: name,
        );
        expect(
          find.descendant(of: row, matching: find.text(text.saving)),
          saving ? findsOneWidget : findsNothing,
          reason: name,
        );
        expect(find.byIcon(Icons.star), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('строки Главной при масштабе текста 2.5 на экране телефона '
      'показывают название и состояние сохранения целиком', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final locale in const [Locale('ru'), Locale('en')]) {
      for (final useCase in homeRowUseCases()) {
        await _pumpUseCase(tester, useCase, locale);

        expect(tester.takeException(), isNull, reason: useCase.name);
        final row = find.byType(HomeIntentionRow);
        final rowRect = tester.getRect(row);
        expect(rowRect.right, lessThanOrEqualTo(360), reason: useCase.name);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: row, matching: find.byType(RichText)),
        )) {
          expect(paragraph.didExceedMaxLines, isFalse, reason: useCase.name);
        }
        final handle = find.descendant(
          of: row,
          matching: find.byIcon(Icons.drag_handle),
        );
        expect(
          tester.getRect(handle).right,
          lessThanOrEqualTo(360),
          reason: useCase.name,
        );
      }
    }
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

/// Показывает пример [useCase] в приложении с языком [locale].
Future<void> _pumpUseCase(
  WidgetTester tester,
  WidgetbookUseCase useCase,
  Locale locale,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: useCase.builder)),
    ),
  );
  await tester.pumpAndSettle();
}
