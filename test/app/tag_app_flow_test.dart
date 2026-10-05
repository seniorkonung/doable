import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Не появился элемент: $finder');
}

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _saveName(WidgetTester tester, String name) async {
  await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
  await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), name);
  await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
  for (var attempt = 0; attempt < 100; attempt++) {
    if (find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Форма не закрылась после сохранения');
}

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'каталог: вход, создание, переименование, отмена удаления, удаление и повтор имени — ${locale.languageCode}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.platformDispatcher.localesTestValue = [locale];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

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
        await openIntentionGraph(tester, waitFor: _until);
        await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
        await _until(tester, find.byKey(const ValueKey('tag-catalog-create')));

        await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
        await _saveName(tester, '  Straße  ');
        await _until(tester, find.text('Straße'));
        final firstId = raw.select('SELECT id FROM tags').single['id'];
        expect(raw.select('SELECT name FROM tags').single['name'], 'Straße');

        await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
        await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
        await tester.enterText(
          find.byKey(const ValueKey('tag-editor-name')),
          'STRASSE',
        );
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        await _until(
          tester,
          find.byKey(const ValueKey('tag-editor-use-existing')),
        );
        expect(raw.select('SELECT id FROM tags'), hasLength(1));
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
              .controller!
              .text,
          'STRASSE',
        );
        await _tap(tester, find.byKey(const ValueKey('tag-editor-cancel')));
        await _until(tester, find.text('Straße'));

        await _tap(tester, find.byIcon(Icons.edit_outlined));
        await _saveName(tester, 'Быт 🏠');
        await _until(tester, find.text('Быт 🏠'));
        expect(find.text('Straße'), findsNothing);
        expect(raw.select('SELECT id FROM tags').single['id'], firstId);

        final delete = find.byKey(ValueKey('tag-catalog-delete-$firstId'));
        await _tap(tester, delete);
        await _until(tester, find.byKey(const ValueKey('tag-delete-scope')));
        expect(find.textContaining('Быт 🏠'), findsWidgets);
        await _tap(tester, find.byKey(const ValueKey('tag-delete-cancel')));
        expect(raw.select('SELECT id FROM tags').single['id'], firstId);
        await _tap(tester, delete);
        await _tap(tester, find.byKey(const ValueKey('tag-delete-confirm')));
        for (
          var attempt = 0;
          attempt < 100 && raw.select('SELECT id FROM tags').isNotEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(raw.select('SELECT id FROM tags'), isEmpty);
        await tester.pumpAndSettle();
        expect(find.text('Быт 🏠'), findsNothing);
        expect(delete, findsNothing);

        await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
        await _saveName(tester, 'Быт 🏠');
        await _until(tester, find.text('Быт 🏠'));
        expect(raw.select('SELECT id FROM tags'), hasLength(1));
        expect(raw.select('SELECT id FROM tags').single['id'], isNot(firstId));
        tester.binding.platformDispatcher.localesTestValue = [
          locale.languageCode == 'ru' ? const Locale('en') : const Locale('ru'),
        ];
        await tester.pumpAndSettle();
        expect(find.text('Быт 🏠'), findsOneWidget);
        expect(raw.select('SELECT name FROM tags').single['name'], 'Быт 🏠');
        expect(
          find.text(locale.languageCode == 'ru' ? 'Tags' : 'Теги'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'общий выбор открывается существующим маршрутом с контекстом живой сессии, переживает настоящий редактор и не меняет прежние места вызова каталога и назначения',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = [const Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

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
      final ready =
          (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
      seedTagStorageFixture(raw);
      final intentionsBefore = raw.select(
        'SELECT * FROM intentions ORDER BY id',
      );
      final assignmentsBefore = raw.select(
        'SELECT tag_id, intention_id FROM tag_assignments ORDER BY rowid',
      );
      final router = ready.container.read(appRouterProvider);
      // Владелец удерживает сессию, пока над каталогом открыты выбор и
      // редактор тега.
      final session = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final owner = ready.container.listen(session, (_, _) {});
      addTearDown(owner.close);
      final editor = ready.container.read(session.notifier)
        ..changeTitle('Купить хлеб')
        ..markFavorite();
      final tagSet = editor.draftTagSet;
      final draftContext = TagDraftContext(tagSet);
      final homeId = tagFixtureId(firstTagNumber);
      final workId = tagFixtureId(lastTagNumber);
      final homeRow = find.byKey(ValueKey('tag-catalog-row-$homeId'));
      final workRow = find.byKey(ValueKey('tag-catalog-row-$workId'));
      final search = find.byKey(const ValueKey('tag-catalog-search'));
      final add = find.byKey(const ValueKey('tag-catalog-add-to-draft'));
      final openTags = find.byKey(const ValueKey('catalog-open-tags'));
      String searchText() => tester.widget<TextField>(search).controller!.text;
      Finder rowStatus(Finder row, String status) =>
          find.descendant(of: row, matching: find.text(status));
      List<String> draftTagIds() => [
        for (final id in tagSet.current.tagIds) id.toCanonicalString(),
      ];

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _until);
      await _until(tester, find.text('Намерение 1'));

      // Каталог из каталога намерений остаётся просмотром.
      await _tap(tester, openTags);
      await _until(tester, homeRow);
      expect(
        router.current.argsAs<TagCatalogRouteArgs>().selectionContext,
        const TagBrowseContext(),
      );
      expect(find.text('Теги'), findsOneWidget);
      expect(add, findsNothing);
      await _tap(tester, find.byType(BackButton));
      await _until(tester, openTags);

      // Выбор для черновика открывается тем же маршрутом над каталогом.
      unawaited(
        router.push<void>(TagCatalogRoute(selectionContext: draftContext)),
      );
      await _until(tester, homeRow);
      await tester.pumpAndSettle();
      expect(find.byType(TagCatalogPage), findsOneWidget);
      expect(find.text('Выбор тега'), findsOneWidget);
      await tester.enterText(search, 'дом');
      await tester.pump();
      expect(workRow, findsNothing);
      await _tap(tester, homeRow);
      await _tap(tester, add);
      expect(draftTagIds(), [homeId]);

      // Настоящий редактор сохраняет самостоятельный тег, не включая его.
      await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
      await _saveName(tester, 'Домашнее');
      final created =
          raw.select("SELECT id FROM tags WHERE name = 'Домашнее'").single['id']
              as String;
      final createdRow = find.byKey(ValueKey('tag-catalog-row-$created'));
      await _until(tester, createdRow);
      await tester.pumpAndSettle();
      expect(router.current.name, TagCatalogRoute.name);
      expect(searchText(), 'дом');
      expect(rowStatus(createdRow, 'Можно добавить'), findsOneWidget);
      expect(draftTagIds(), [homeId]);

      // Отмена редактора не создаёт тег и не меняет набор.
      await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
      await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'Домовой',
      );
      await _tap(tester, find.byKey(const ValueKey('tag-editor-cancel')));
      await _until(tester, createdRow);
      await tester.pumpAndSettle();
      expect(router.current.name, TagCatalogRoute.name);
      expect(searchText(), 'дом');
      expect(raw.select("SELECT id FROM tags WHERE name = 'Домовой'"), isEmpty);
      expect(draftTagIds(), [homeId]);

      await _tap(tester, createdRow);
      await _tap(tester, add);
      expect(draftTagIds(), [homeId, created]);

      // Закрытие выбора возвращает каталог намерений, а сессия остаётся у
      // владельца.
      await _tap(tester, find.byType(BackButton));
      await _until(tester, openTags);
      await tester.pumpAndSettle();
      expect(find.byType(TagCatalogPage), findsNothing);
      final kept = ready.container.read(session);
      expect(kept.draft.title, 'Купить хлеб');
      expect(kept.draft.favoriteMark, FavoriteMark.favorite);
      expect(kept.draftAvailability, IntentionDraftAvailability.editable);
      expect(draftTagIds(), [homeId, created]);

      // Повторное открытие начинает новый поиск над тем же набором.
      unawaited(
        router.push<void>(TagCatalogRoute(selectionContext: draftContext)),
      );
      await _until(tester, createdRow);
      await tester.pumpAndSettle();
      expect(searchText(), isEmpty);
      expect(rowStatus(homeRow, 'В черновике'), findsOneWidget);
      expect(rowStatus(createdRow, 'В черновике'), findsOneWidget);
      expect(rowStatus(workRow, 'Можно добавить'), findsOneWidget);
      await _tap(tester, find.byType(BackButton));
      await _until(tester, openTags);
      expect(
        raw.select('SELECT * FROM intentions ORDER BY id'),
        intentionsBefore,
      );
      expect(
        raw.select(
          'SELECT tag_id, intention_id FROM tag_assignments ORDER BY rowid',
        ),
        assignmentsBefore,
      );
      expect(raw.select('SELECT * FROM favorite_intentions'), isEmpty);

      // Назначение из подробностей намерения остаётся постоянной записью.
      final recipient = (IntentionId.decode(
        tagFixtureId(3),
      ) as IntentionIdDecodingSuccess).id;
      unawaited(router.push(IntentionDetailsRoute(intentionId: recipient)));
      await _tap(tester, find.byKey(const ValueKey('tag-assignments-choose')));
      await _until(tester, homeRow);
      await tester.pumpAndSettle();
      expect(
        router.current.argsAs<TagCatalogRouteArgs>().selectionContext,
        TagAssignmentContext(recipient),
      );
      expect(add, findsNothing);
      await _tap(tester, homeRow);
      await _tap(tester, find.byKey(const ValueKey('tag-catalog-assign')));
      await _waitFor(
        tester,
        () => raw.select(
          'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
          [homeId, tagFixtureId(3)],
        ).isNotEmpty,
      );
      expect(draftTagIds(), [homeId, created]);

      // Окончательное завершение сессии закрывает переданный контекст.
      final decision =
          editor.requestClose() as IntentionCreationCloseNeedsConfirmation;
      expect(
        editor.resolveClose(
          decision.confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.closed,
      );
      expect(tagSet.current.availability, IntentionDraftAvailability.closed);
      expect(draftTagIds(), [homeId, created]);
      expect(
        raw.select('SELECT * FROM intentions ORDER BY id'),
        intentionsBefore,
      );
      expect(raw.select('SELECT * FROM favorite_intentions'), isEmpty);
      expect(
        raw
            .select('SELECT name FROM tags ORDER BY creation_sequence')
            .map((row) => row['name']),
        ['Дом', 'Работа', 'Домашнее'],
      );
      expect(tester.takeException(), isNull);
    },
  );
}
