import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

String uuid(int n) =>
    '018f0b5d-6b2e-7c80-8000-${n.toString().padLeft(12, '0')}';
IntentionId id(int n) =>
    (IntentionId.decode(uuid(n)) as IntentionIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late AppRouter router;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    await seedGraph(database, () async {
      for (final (n, title, archived) in [
        (1, 'Корень', false),
        (2, 'Другой', false),
        (3, 'Архив', true),
      ]) {
        await database
            .into(database.intentions)
            .insert(
              IntentionsCompanion.insert(
                id: uuid(n),
                title: title,
                isArchived: Value(archived),
                createdAt: n,
                updatedAt: n,
              ),
            );
      }
    });
    router = AppRouter();
  });

  tearDown(() async {
    router.dispose();
    await database.close();
  });

  Future<({Future<PathStartChoice?> result})> open(
    WidgetTester tester, {
    IntentionId? currentRoot,
    PathStartFlow flow = PathStartFlow.newAction,
  }) async {
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      DateTime.now,
      InMemoryDiagnosticsSink(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryQuickCreationModeOverride,
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          theme: doableTheme(Brightness.light),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final result = router.push<PathStartChoice>(
      PathStartPickerRoute(flow: flow, currentRoot: currentRoot),
    );
    await tester.pumpAndSettle();
    return (result: result);
  }

  testWidgets(
    'поиск исключает корень и архив, показывает назначение и возвращает выбор',
    (tester) async {
      final (:result) = await open(
        tester,
        currentRoot: id(1),
        flow: PathStartFlow.editPath,
      );
      expect(find.text('Корень'), findsNothing);
      expect(find.text('Архив'), findsNothing);
      expect(find.text('Другой'), findsOneWidget);
      expect(find.text('Выбор намерения'), findsOneWidget);
      expect(
        find.text('Изменение пути: с чего начинается путь'),
        findsOneWidget,
      );
      expect(find.byType(AppNavigationBar), findsNothing);
      await tester.tap(find.text('Изменение пути: с чего начинается путь'));
      await tester.pumpAndSettle();
      expect(find.text('Изменение пути'), findsOneWidget);
      expect(
        find.text('Намерение, с которого начинается путь'),
        findsOneWidget,
      );
      expect(find.text('Дальше вниз'), findsOneWidget);
      expect(find.text('Вы здесь'), findsOneWidget);
      await tester.tap(find.text('Вернуться к списку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Другой'));
      await tester.pumpAndSettle();
      expect(
        await result,
        isA<PathStartSelected>().having(
          (choice) => choice.intention,
          'intention',
          id(2),
        ),
      );
    },
  );

  testWidgets('закрытие поиска не выбирает намерение', (tester) async {
    final (:result) = await open(tester);
    expect(find.text('Новое действие: с чего начинается путь'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('path-start-picker-cancel')));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('системное назад закрывает поиск без выбора', (tester) async {
    final (:result) = await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('стрелка открывает полную страницу над поиском', (tester) async {
    await open(tester);
    await tester.tap(
      find.bySemanticsLabel('Открыть страницу намерения «Другой»'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppNavigationBar), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Выбор намерения'), findsOneWidget);
    expect(find.text('Другой'), findsOneWidget);
  });

  testWidgets('пустой охват объясняет отсутствие выбора', (tester) async {
    await seedGraph(database, () async {
      await (database.update(database.intentions)
            ..where((row) => row.id.equals(uuid(2))))
          .write(const IntentionsCompanion(isArchived: Value(true)));
    });
    await open(tester, currentRoot: id(1));
    expect(find.text('Выбрать не из чего'), findsOneWidget);
    expect(
      find.text('Нет доступных намерений для начала пути.'),
      findsOneWidget,
    );
    expect(find.text('Сбросить фильтры'), findsNothing);
  });

  testWidgets('плюс создаёт намерение и возвращает его началом пути', (
    tester,
  ) async {
    final (:result) = await open(tester);
    await tester.tap(find.bySemanticsLabel('Создать намерение'));
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('intention-editor-title'));
    expect(tester.widget<TextField>(title).controller!.text, isEmpty);
    expect(find.text('Сразу отмечается для новых связей'), findsNothing);
    await tester.enterText(title, 'Быть здоровым');
    await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('intention-editor-title')), findsNothing);
    expect(find.text('Выбор намерения'), findsNothing);
    final created = await result;
    final rows = await tester.runAsync(
      () => (database.select(
        database.intentions,
      )..where((row) => row.title.equals('Быть здоровым'))).get(),
    );
    expect(rows, hasLength(1));
    expect(
      created,
      isA<PathStartCreated>().having(
        (choice) => choice.intention,
        'intention',
        (IntentionId.decode(rows!.single.id) as IntentionIdDecodingSuccess).id,
      ),
    );
  });

  testWidgets('создание из строки учитывает даже исключённый корень', (
    tester,
  ) async {
    final (:result) = await open(tester, currentRoot: id(1));
    final filter = find.byKey(const ValueKey('path-start-picker-filter'));
    await tester.enterText(filter, 'КОРЕНЬ');
    await tester.pumpAndSettle();
    expect(find.text('Создать «КОРЕНЬ»'), findsNothing);
    await tester.enterText(filter, '  Высыпаться  ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать «Высыпаться»'));
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('intention-editor-title'));
    expect(tester.widget<TextField>(title).controller!.text, 'Высыпаться');
    await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(await result, isA<PathStartCreated>());
  });
}
