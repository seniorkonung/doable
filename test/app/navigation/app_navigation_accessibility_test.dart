import 'dart:ui' show Tristate;

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

/// Узкий экран телефона: увеличенный текст занимает его целиком.
const _screen = Size(360, 780);

const _textScale = 2.5;

/// Названия пунктов задаёт спецификация основной навигации.
final _names = {
  const Locale('ru'): {
    AppDestination.home: 'Главная',
    AppDestination.dailyChoices: 'Дневные выборы',
    AppDestination.intentionGraph: 'Граф намерений',
  },
  const Locale('en'): {
    AppDestination.home: 'Home',
    AppDestination.dailyChoices: 'Daily choices',
    AppDestination.intentionGraph: 'Intention graph',
  },
};

void main() {
  for (final MapEntry(key: locale, value: names) in _names.entries) {
    final code = locale.languageCode;
    final otherLocale = _names.keys.firstWhere((other) => other != locale);

    testWidgets('экранный диктор получает название, роль пункта навигации, '
        'положение среди трёх пунктов и признак выбранного пункта на каждой '
        'корневой странице, а видимых подписей в панели нет: $code', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _start(tester, locale);

      _expectAnnounced(tester, names, selected: AppDestination.home);

      // Пункт выбирается действием экранного диктора, а не только касанием.
      for (final selected in [
        AppDestination.dailyChoices,
        AppDestination.intentionGraph,
        AppDestination.home,
      ]) {
        tester.semantics.tap(
          find.semantics.byLabel(_destinationLabel(tester, names, selected)),
        );
        await tester.pumpAndSettle();

        expect(_selected(tester), selected);
        _expectAnnounced(tester, names, selected: selected);
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('при масштабе текста 2.5 значки пунктов не обрезаются, каждый '
        'пункт выбирается касанием, а заголовок его корневой страницы виден: '
        '$code', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = _screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = _textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _start(tester, locale);

      // Системный размер текста доходит до корневых страниц.
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(HomePage)))
            .scale(10),
        10 * _textScale,
      );
      _expectWholeIcons(tester, selected: AppDestination.home);
      _expectVisibleTitle(tester, names, AppDestination.home);

      for (final selected in [
        AppDestination.dailyChoices,
        AppDestination.intentionGraph,
        AppDestination.home,
      ]) {
        await tester.tap(_icon(selected, isSelected: false));
        await tester.pumpAndSettle();

        expect(_selected(tester), selected);
        _expectWholeIcons(tester, selected: selected);
        _expectVisibleTitle(tester, names, selected);
        expect(tester.takeException(), isNull);
      }
      semantics.dispose();
    });

    testWidgets('смена языка интерфейса меняет только названия пунктов и '
        'заголовок: состав, порядок, значки и выбранный пункт прежние: '
        '$code → ${otherLocale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      await _start(tester, locale);
      await tester.tap(_icon(AppDestination.intentionGraph, isSelected: false));
      await tester.pumpAndSettle();
      final layout = _barLayout(tester);
      expect(layout.map((icon) => icon.$1), [
        Icons.home_outlined,
        Icons.calendar_month_outlined,
        Icons.hub,
      ]);
      _expectAnnounced(tester, names, selected: AppDestination.intentionGraph);

      tester.platformDispatcher.localesTestValue = [otherLocale];
      await tester.pumpAndSettle();

      final otherNames = _names[otherLocale]!;
      expect(_barLayout(tester), layout);
      expect(_selected(tester), AppDestination.intentionGraph);
      _expectAnnounced(
        tester,
        otherNames,
        selected: AppDestination.intentionGraph,
      );
      for (final destination in AppDestination.values) {
        expect(find.byTooltip(otherNames[destination]!), findsOneWidget);
        expect(find.byTooltip(names[destination]!), findsNothing);
      }
      expect(
        find.descendant(
          of: _appBar(AppDestination.intentionGraph),
          matching: find.text(names[AppDestination.intentionGraph]!),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

/// Запускает приложение на хранилище в памяти, ждёт Главную и засевает граф
/// намерениями, связями, тегами и дневным выбором.
Future<void> _start(WidgetTester tester, Locale locale) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  late sqlite.Database raw;
  final runtime = AppRuntime(
    connectionFactory: () =>
        openInMemoryLocalDatabase(setup: (database) => raw = database),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
  await tester.pumpAndSettle();
  await runtime.bootstrap();
  // Каталоги строятся при первом выборе пункта и читают уже засеянный граф.
  seedTagStorageFixture(raw);
  expect(find.byType(HomePage), findsOneWidget);
}

final _bar = find.byType(AppNavigationBar);

/// Пункт панели на своём месте слева направо.
Finder _destination(AppDestination destination) => find.descendant(
  of: _bar,
  matching: find.byType(NavigationDestination).at(destination.index),
);

/// Значок пункта: залитый у выбранного, контурный у остальных.
Finder _icon(AppDestination destination, {required bool isSelected}) =>
    find.descendant(
      of: _bar,
      matching: find.byIcon(
        isSelected ? destination.selectedIcon : destination.icon,
      ),
    );

AppDestination _selected(WidgetTester tester) =>
    tester.widget<AppNavigationBar>(_bar).selected;

/// Корневая страница пункта.
Type _rootPage(AppDestination destination) => switch (destination) {
  AppDestination.home => HomePage,
  AppDestination.dailyChoices => DailyChoiceCatalogPage,
  AppDestination.intentionGraph => IntentionCatalogPage,
};

/// Шапка корневой страницы пункта.
Finder _appBar(AppDestination destination) => find.descendant(
  of: find.byType(_rootPage(destination)),
  matching: find.byType(AppBar),
);

/// Название пункта вместе с его положением среди трёх пунктов — так пункт
/// объявляет экранный диктор.
String _destinationLabel(
  WidgetTester tester,
  Map<AppDestination, String> names,
  AppDestination destination,
) {
  final position = MaterialLocalizations.of(tester.element(_bar))
      .tabLabel(tabIndex: destination.index + 1, tabCount: 3);
  return '${names[destination]}\n$position';
}

/// Экранный диктор проходит три пункта по порядку с названием, ролью,
/// положением и признаком выбранного, а из корневых страниц слышит заголовок
/// только открытой. Подписи пунктов в дереве остаются, но не рисуются.
void _expectAnnounced(
  WidgetTester tester,
  Map<AppDestination, String> names, {
  required AppDestination selected,
}) {
  for (final destination in AppDestination.values) {
    final node = tester.getSemantics(_destination(destination));
    expect(node.label, _destinationLabel(tester, names, destination));
    expect(node.role, SemanticsRole.tab);
    expect(node.parent?.role, SemanticsRole.tabBar);
    expect(node.flagsCollection.isButton, isTrue);
    expect(
      node.flagsCollection.isSelected,
      destination == selected ? Tristate.isTrue : Tristate.isFalse,
      reason: '$destination',
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  }

  final traversal = tester.semantics.simulatedAccessibilityTraversal().toList();
  expect(
    [
      for (final node in traversal)
        if (node.role == SemanticsRole.tab) node.label,
    ],
    [
      for (final destination in AppDestination.values)
        _destinationLabel(tester, names, destination),
    ],
  );
  expect(
    [
      for (final node in traversal)
        if (node.flagsCollection.isHeader && names.containsValue(node.label))
          node.label,
    ],
    [names[selected]],
  );

  for (final label in tester.widgetList<Text>(
    find.descendant(of: _bar, matching: find.byType(Text)),
  )) {
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byWidget(label),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 0, reason: label.data);
  }
}

/// Значки пунктов показаны целиком внутри своих пунктов, а пункт остаётся
/// целью касания не меньше 48 × 48.
void _expectWholeIcons(
  WidgetTester tester, {
  required AppDestination selected,
}) {
  final screen = Offset.zero & _screen;
  final bar = tester.getRect(_bar);
  for (final destination in AppDestination.values) {
    final target = tester.getRect(_destination(destination));
    final icon = tester.getRect(
      _icon(destination, isSelected: destination == selected),
    );
    expect(icon.width, moreOrLessEquals(24), reason: '$destination');
    expect(icon.height, moreOrLessEquals(24), reason: '$destination');
    for (final container in [target, bar, screen]) {
      expect(
        container.contains(icon.topLeft) &&
            container.contains(icon.bottomRight - const Offset(0.1, 0.1)),
        isTrue,
        reason: 'значок $destination обрезан: $icon вне $container',
      );
    }
    expect(target.width, greaterThanOrEqualTo(48), reason: '$destination');
    expect(target.height, greaterThanOrEqualTo(48), reason: '$destination');
  }
}

/// Заголовок открытой корневой страницы — название её пункта: шапка
/// показывает его на экране без обрезки по высоте, а экранный диктор получает
/// его целиком.
///
/// Material ограничивает масштаб заголовка шапки и сокращает многоточием
/// заголовок, не помещающийся по ширине; квадратные глифы тестового шрифта
/// шире настоящих, поэтому полнота названия проверяется по его доступному
/// названию, а не по ширине строки.
void _expectVisibleTitle(
  WidgetTester tester,
  Map<AppDestination, String> names,
  AppDestination destination,
) {
  final name = names[destination]!;
  final appBar = _appBar(destination);
  final title = find.descendant(of: appBar, matching: find.text(name));
  expect(title, findsOneWidget);
  final rect = tester.getRect(title);
  expect(rect.isEmpty, isFalse);
  for (final container in [tester.getRect(appBar), Offset.zero & _screen]) {
    expect(
      container.contains(rect.topLeft) &&
          container.contains(rect.bottomRight - const Offset(0.1, 0.1)),
      isTrue,
      reason: 'заголовок $destination обрезан: $rect вне $container',
    );
  }
  expect(tester.getSemantics(title), isSemantics(label: name, isHeader: true));
}

/// Значки панели слева направо вместе с их положением.
List<(IconData?, Rect)> _barLayout(WidgetTester tester) {
  final icons = find.descendant(of: _bar, matching: find.byType(Icon));
  return [
    for (final element in icons.evaluate())
      (
        (element.widget as Icon).icon,
        tester.getRect(find.byWidget(element.widget)),
      ),
  ]..sort((a, b) => a.$2.left.compareTo(b.$2.left));
}
