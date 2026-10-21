import 'dart:ui' show Tristate;

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/temporary_graph_files.dart';

void main() {
  testWidgets('шестерёнка открывает «Настройки» поверх Главной с вкладкой '
      '«Год» и выбранным пунктом «Главная», а «назад» возвращает Главную с '
      'той же вкладкой', (tester) async {
    final semantics = tester.ensureSemantics();
    await _start(tester);
    await tester.tap(find.text('Год'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Настройки'));
    await _until(tester, find.byType(SettingsPage));
    await tester.pumpAndSettle();

    final page = find.byType(SettingsPage);
    expect(
      find.descendant(of: page, matching: find.text('Настройки')),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        MaterialLocalizations.of(tester.element(page)).backButtonTooltip,
      ),
      findsOneWidget,
    );
    expect(find.byType(HomePage), findsNothing);
    final bar = find.byType(AppNavigationBar);
    expect(bar, findsOneWidget);
    expect(tester.widget<AppNavigationBar>(bar).selected, AppDestination.home);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(page, findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Год')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  for (final (language, settings) in [
    ('ru', 'Настройки'),
    ('en', 'Settings'),
  ]) {
    testWidgets('$language: шестерёнка Главной доступна под названием '
        '«$settings» и открывает страницу с этим заголовком, а на каталогах '
        'её нет', (tester) async {
      final semantics = tester.ensureSemantics();
      await _start(tester, language: language);
      // Название кнопки со значком экранный диктор читает из подсказки.
      final announced = find.semantics.byPredicate(
        (node) => node.tooltip == settings,
        describeMatch: (_) => 'переход к настройкам для экранного диктора',
      );

      expect(announced, findsOneWidget);
      expect(
        tester.getSemantics(find.byTooltip(settings)),
        isSemantics(tooltip: settings, isButton: true, isEnabled: true),
      );
      await tester.tap(find.byTooltip(settings));
      await _until(tester, find.byType(SettingsPage));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.text(settings),
        ),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      for (final (destination, catalog) in [
        (AppDestination.dailyChoices, DailyChoiceCatalogPage),
        (AppDestination.intentionGraph, IntentionCatalogPage),
      ]) {
        await tester.tap(appNavigationDestination(destination));
        await _until(tester, find.byType(catalog));
        await tester.pumpAndSettle();
        expect(find.byTooltip(settings), findsNothing, reason: '$catalog');
        expect(announced, findsNothing, reason: '$catalog');
      }
      semantics.dispose();
    });
  }

  testWidgets('в новой установке строка «Экспорт данных» недоступна, а после '
      'первого подтверждённого намерения доступна', (tester) async {
    final semantics = tester.ensureSemantics();
    final ready = await _start(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await _until(tester, find.text('Пока нечего экспортировать'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Экспорт данных')),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );

    final created = await tester.runAsync(
      () => ready.container
          .read(personalGraphRepositoryProvider)
          .execute(
            CreateIntention.withInitialState(
              title: 'Бегать',
              description: null,
              readiness: IntentionReadiness.notReady,
              tagIds: const {},
            ),
          ),
    );
    expect(created, isA<GraphCommandSucceeded>());
    await _until(tester, find.text('Сохранить копию всего в файл'));
    await tester.pumpAndSettle();

    expect(find.text('Пока нечего экспортировать'), findsNothing);
    expect(
      tester.getSemantics(find.text('Экспорт данных')),
      isSemantics(hasEnabledState: true, isEnabled: true),
    );
    semantics.dispose();
  });
}

/// Запускает приложение новой установки на языке [language] с файлами графа
/// во временном каталоге и ждёт загруженную Главную.
Future<AppRuntimeReady> _start(
  WidgetTester tester, {
  String language = 'ru',
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [Locale(language)];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  final files = TemporaryGraphFiles();
  final runtime = AppRuntime(
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: InMemoryDiagnosticsSink(),
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    graphFilesFactory: files.create,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.shutdown);
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return ready;
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Чередует реальное ожидание хранилища с кадрами, пока не выполнится [done].
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}
