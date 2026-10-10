import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/quick_creation.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('пункт календаря открывает каталог дневных выборов', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _start(tester);

    await _select(tester, AppDestination.dailyChoices);

    expect(find.byType(DailyChoiceCatalogPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(_selected(tester), AppDestination.dailyChoices);
    await openQuickCreation(
      tester,
      QuickCreationMode.dailyChoiceFromAction,
      openedPage: find.byType(DailyChoiceActionPickerPage),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DailyChoiceCatalogPage), findsOneWidget);
    expect(_selected(tester), AppDestination.dailyChoices);
    semantics.dispose();
  });

  testWidgets('пункт графа открывает каталог намерений с охватом, поиском и '
      'созданием намерения', (tester) async {
    final semantics = tester.ensureSemantics();
    await _start(tester);

    await _select(tester, AppDestination.intentionGraph);

    expect(find.byType(IntentionCatalogPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(_selected(tester), AppDestination.intentionGraph);
    expect(find.text(l10n.catalogScopeLabel), findsOneWidget);
    expect(find.text(l10n.catalogFilterLabel), findsOneWidget);
    await openQuickCreation(
      tester,
      QuickCreationMode.intention,
      openedPage: find.byType(IntentionEditorPage),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(IntentionEditorPage), findsNothing);
    expect(find.byType(IntentionCatalogPage), findsOneWidget);
    expect(_selected(tester), AppDestination.intentionGraph);
    semantics.dispose();
  });

  testWidgets('шапка каталога намерений ведёт к каталогу тегов и не ведёт к '
      'каталогу дневных выборов', (tester) async {
    await _start(tester);
    await _select(tester, AppDestination.intentionGraph);

    final appBar = find.descendant(
      of: find.byType(IntentionCatalogPage),
      matching: find.byType(AppBar),
    );
    expect(
      find.descendant(
        of: appBar,
        matching: find.byTooltip(l10n.appDestinationDailyChoices),
      ),
      findsNothing,
    );
    final tags = find.descendant(
      of: appBar,
      matching: find.byTooltip(l10n.tagCatalogTitle),
    );
    expect(tags, findsOneWidget);

    await tester.tap(tags);
    await tester.pumpAndSettle();

    // Просмотр каталога тегов сохраняет постоянную навигацию.
    expect(find.byType(TagCatalogPage), findsOneWidget);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });

  testWidgets('переключение пунктов идёт без анимации перехода', (
    tester,
  ) async {
    await _start(tester);

    // Один кадр без продвижения времени: страница уже показана целиком, а
    // прежняя не остаётся под переходом.
    await tester.tap(appNavigationDestination(AppDestination.dailyChoices));
    await tester.pump();

    expect(find.byType(DailyChoiceCatalogPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('переход с пустой Главной открывает каталог намерений с '
      'выбранным пунктом «Граф намерений»', (tester) async {
    final semantics = tester.ensureSemantics();
    await _start(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Open intention graph'));
    await tester.pumpAndSettle();

    expect(find.byType(IntentionCatalogPage), findsOneWidget);
    expect(_selected(tester), AppDestination.intentionGraph);
    expect(find.byType(AppNavigationBar), findsOneWidget);
    semantics.dispose();
  });
}

/// Запускает приложение на пустом хранилище и ждёт корневую страницу.
Future<void> _start(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openInMemoryLocalDatabase(),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
  await tester.pumpAndSettle();
  await runtime.bootstrap();
}

/// Выбирает пункт панели по его назначению.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await tester.tap(appNavigationDestination(destination));
  await tester.pumpAndSettle();
}

/// Пункт, который панель объявляет выбранным.
AppDestination _selected(WidgetTester tester) =>
    AppDestination.values.singleWhere(
      (destination) =>
          tester
              .getSemantics(appNavigationDestination(destination))
              .flagsCollection
              .isSelected ==
          Tristate.isTrue,
    );
