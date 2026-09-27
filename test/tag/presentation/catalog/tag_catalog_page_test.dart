import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tag;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart'
    hide TagCatalogPage;
import 'package:doable/src/tag/application/tag_catalog.dart'
    as data
    show TagCatalogPage;
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

void main() {
  for (final (relation, recipient) in [
    (false, 'намерения'),
    (true, 'долговременной связи'),
  ]) {
    for (final assigned in [false, true]) {
      for (final tagReadFirst in [false, true]) {
        testWidgets(
          'экран повторяет проверку пары $recipient после ${tagReadFirst ? 'раннего' : 'позднего'} чтения тега: ${assigned ? 'назначен' : 'свободен'}',
          (tester) async {
            final repository = _CatalogRepository();
            addTearDown(repository.dispose);
            final target = relation
                ? LongTermRelationTagTarget(
                    (LongTermRelationId.decode(
                      _id(200),
                    ) as LongTermRelationIdDecodingSuccess).id,
                  )
                : IntentionTagTarget(
                    (IntentionId.decode(
                      _id(100),
                    ) as IntentionIdDecodingSuccess).id,
                  );
            await _pumpCatalog(tester, repository, target: target);
            repository.complete(
              TagCatalogPageSuccess(
                data.TagCatalogPage.selection(
                  target: target,
                  rows: [
                    TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
                  ],
                  pageSize: TagCatalogQuery.defaultPageSize,
                  nextCursor: _Cursor(),
                  revision: const _Revision(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final container = ProviderScope.containerOf(
              tester.element(find.byType(TagCatalogPage)),
            );
            container
                .read(
                  tagCatalogViewModelProvider(
                    mode: TagCatalogSelectionMode(target),
                  ).notifier,
                )
                .selectTag(_tag(52, 'Вне порции').id);
            if (tagReadFirst) {
              repository.tagRead(_tag(52, 'Вне порции'));
            }
            repository.statusReads.single.complete(
              const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
            );
            await tester.pump();
            await tester.pump();
            if (!tagReadFirst) {
              repository.tagRead(_tag(52, 'Вне порции'));
              await tester.pumpAndSettle();
            }
            final assign = find.byKey(const ValueKey('tag-catalog-assign'));
            expect(assign, findsOneWidget);
            expect(tester.widget<FilledButton>(assign).onPressed, isNull);
            expect(
              find.text('Could not load assignments. Try again.'),
              findsOneWidget,
            );
            await tester.tap(find.text('Try again'));
            await tester.pump();
            expect(repository.statusReads, hasLength(2));
            expect(tester.widget<FilledButton>(assign).onPressed, isNull);
            repository.statusReads.last.complete(
              TagAssignmentStatusSuccess(
                GraphSnapshot(value: assigned, revision: const _Revision()),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.text('Could not load assignments. Try again.'),
              findsNothing,
            );
            if (assigned) {
              expect(assign, findsNothing);
              expect(repository._commands, isEmpty);
            } else {
              expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
            }
          },
        );
      }
    }
  }

  for (final (relation, recipient) in [
    (false, 'намерения'),
    (true, 'долговременной связи'),
  ]) {
    for (final assigned in [false, true]) {
      testWidgets(
        'редактор подтверждает вне порции ${assigned ? 'назначенный' : 'свободный'} тег для $recipient',
        (tester) async {
          late sqlite.Database raw;
          final database = AppDatabase(
            openInMemoryLocalDatabase(setup: (db) => raw = db),
          );
          await database.open();
          addTearDown(database.close);
          for (final number in [100, 101]) {
            raw.execute(
              'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
              [_id(number), 'Намерение $number', 0, 0, number, number],
            );
          }
          raw.execute(
            'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
            [_id(200), _id(100), _id(101), 'need', 2, 0],
          );
          for (var number = 1; number <= 52; number++) {
            raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
              _id(number),
              number == 52 ? 'Дом' : 'Тег $number',
            ]);
          }
          if (assigned) {
            raw.execute(
              'INSERT INTO tag_assignments (tag_id, ${relation ? 'long_term_relation_id' : 'intention_id'}) VALUES (?, ?)',
              [_id(52), _id(relation ? 200 : 100)],
            );
          }
          final repository = DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 27),
            InMemoryDiagnosticsSink(),
          );
          final router = AppRouter();
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                personalGraphRepositoryProvider.overrideWithValue(repository),
              ],
              child: MaterialApp.router(
                locale: const Locale('ru'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router.config(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final target = relation
              ? LongTermRelationTagTarget(
                  (LongTermRelationId.decode(
                    _id(200),
                  ) as LongTermRelationIdDecodingSuccess).id,
                )
              : IntentionTagTarget(
                  (IntentionId.decode(
                    _id(100),
                  ) as IntentionIdDecodingSuccess).id,
                );
          router.push<Object?>(TagCatalogRoute(target: target));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('tag-catalog-load-more')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('tag-editor-name')),
            'дом',
          );
          await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
          for (
            var attempt = 0;
            attempt < 30 &&
                find
                    .byKey(const ValueKey('tag-editor-use-existing'))
                    .evaluate()
                    .isEmpty;
            attempt++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(
            find.byKey(const ValueKey('tag-editor-use-existing')),
          );
          await _waitForEditorToClose(tester);
          expect(
            find.byKey(const ValueKey('tag-catalog-load-more')),
            findsOneWidget,
          );
          final assign = find.byKey(const ValueKey('tag-catalog-assign'));
          if (assigned) {
            expect(assign, findsNothing);
          } else {
            expect(assign, findsOneWidget);
            expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
            await tester.tap(assign);
            await tester.pumpAndSettle();
            expect(
              raw
                  .select(
                    'SELECT tag_id FROM tag_assignments WHERE ${relation ? 'long_term_relation_id' : 'intention_id'} = ?',
                    [_id(relation ? 200 : 100)],
                  )
                  .map((row) => row['tag_id']),
              [_id(52)],
            );
          }
        },
      );
    }
  }

  testWidgets(
    'выбор назначает свободный тег архивному получателю только по нажатию',
    (tester) async {
      late sqlite.Database raw;
      final database = AppDatabase(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
      );
      await database.open();
      addTearDown(database.close);
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [_id(100), 'Архивное намерение', 0, 1, 100, 100],
      );
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [_id(101), 'Другое намерение', 0, 0, 101, 101],
      );
      raw.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [_id(200), _id(100), _id(101), 'need', 2, 1],
      );
      for (var number = 1; number <= 52; number++) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          _id(number),
          'Тег $number',
        ]);
      }
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [_id(1), _id(100)],
      );
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 25),
        InMemoryDiagnosticsSink(),
      );
      final router = AppRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = IntentionTagTarget(
        (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id,
      );
      final result = router.push<Object?>(TagCatalogRoute(target: target));
      await tester.pumpAndSettle();

      expect(find.text('Выбор тега'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagCatalogPage)),
      );
      final catalog = container.read(
        tagCatalogViewModelProvider(mode: TagCatalogSelectionMode(target)),
      );
      expect(catalog, isA<TagCatalogLoaded>());
      expect(
        (catalog as TagCatalogLoaded).selectionRows.first.isAssigned,
        isTrue,
      );
      expect(find.text('Назначен'), findsOneWidget);
      expect(find.text('Доступен для назначения'), findsWidgets);
      expect(find.byTooltip('Удалить тег'), findsNothing);
      expect(raw.select('SELECT * FROM tag_assignments'), hasLength(1));
      await tester.tap(find.byKey(const ValueKey('tag-catalog-load-more')));
      await tester.pumpAndSettle();
      final lastRow = find.byKey(ValueKey('tag-catalog-row-${_id(52)}'));
      await tester.scrollUntilVisible(
        lastRow,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('tag-catalog-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(lastRow);
      await tester.pumpAndSettle();
      expect(raw.select('SELECT * FROM tag_assignments'), hasLength(1));
      await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
      await tester.pumpAndSettle();
      expect(
        raw
            .select(
              'SELECT tag_id FROM tag_assignments WHERE intention_id = ? ORDER BY tag_id',
              [_id(100)],
            )
            .map((row) => row['tag_id']),
        [_id(1), _id(52)],
      );
      expect(find.byKey(const ValueKey('tag-catalog-assign')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Тег 52'),
        -300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('tag-catalog-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Тег 52'),
            matching: find.byType(ListTile),
          ),
          matching: find.text('Назначен'),
        ),
        findsOneWidget,
      );
      expect(
        container
            .read(
              tagCatalogViewModelProvider(mode: TagCatalogSelectionMode(target))
                  .notifier,
            )
            .assignSelected(),
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('tag-catalog-load-more')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        lastRow,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('tag-catalog-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.descendant(of: lastRow, matching: find.text('Назначен')),
        findsOneWidget,
      );
      router.pop();
      expect(await result, isNull);
      await tester.pumpAndSettle();

      final relationTarget = LongTermRelationTagTarget(
        (LongTermRelationId.decode(
          _id(200),
        ) as LongTermRelationIdDecodingSuccess).id,
      );
      final relationResult = router.push<Object?>(
        TagCatalogRoute(target: relationTarget),
      );
      await tester.pumpAndSettle();
      expect(
        router.current.argsAs<TagCatalogRouteArgs>().target,
        relationTarget,
      );
      await tester.tap(find.byKey(ValueKey('tag-catalog-row-${_id(2)}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-catalog-load-more')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        lastRow,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('tag-catalog-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(lastRow);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-catalog-assign')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-catalog-assign')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Тег 52'),
        -300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('tag-catalog-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Тег 52'),
            matching: find.byType(ListTile),
          ),
          matching: find.text('Назначен'),
        ),
        findsOneWidget,
      );
      final relationContainer = ProviderScope.containerOf(
        tester.element(find.byType(TagCatalogPage)),
      );
      expect(
        relationContainer
            .read(
              tagCatalogViewModelProvider(
                mode: TagCatalogSelectionMode(relationTarget),
              ).notifier,
            )
            .assignSelected(),
        isNull,
      );
      expect(
        raw
            .select(
              'SELECT tag_id FROM tag_assignments WHERE long_term_relation_id = ?',
              [_id(200)],
            )
            .map((row) => row['tag_id']),
        containsAll([_id(2), _id(52)]),
      );
      router.pop();
      expect(await relationResult, isNull);
    },
  );

  testWidgets('выбор вне первой порции следует внешним изменениям тега', (
    tester,
  ) async {
    late sqlite.Database raw;
    final database = AppDatabase(
      openInMemoryLocalDatabase(setup: (db) => raw = db),
    );
    await database.open();
    addTearDown(database.close);
    for (var number = 1; number <= 51; number++) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        _id(number),
        'Тег $number',
      ]);
    }
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [_id(52), 'Дом']);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    final router = AppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'дом',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    for (
      var attempt = 0;
      attempt < 30 &&
          find
              .byKey(const ValueKey('tag-editor-use-existing'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('tag-editor-use-existing')));
    await _waitForEditorToClose(tester);
    expect(find.text('Дом'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsOneWidget);

    final coordinator = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('tag-catalog-create'))),
    ).read(graphCommandCoordinatorProvider.notifier);
    final tagId = (TagId.decode(_id(52)) as TagIdDecodingSuccess).id;
    final rename = coordinator.acceptTagRename(
      RenameTag(tagId: tagId, name: TagName.fromInput('Быт')),
    ) as TagCommandAccepted;
    await rename.future;
    await tester.pumpAndSettle();
    expect(find.text('Быт'), findsOneWidget);
    expect(find.text('Дом'), findsNothing);
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsOneWidget);

    final deletion =
        coordinator.acceptTagDelete(DeleteTag(tagId)) as TagCommandAccepted;
    await deletion.future;
    await tester.pumpAndSettle();
    expect(find.text('Быт'), findsNothing);
    expect(find.byKey(ValueKey('tag-catalog-delete-${_id(52)}')), findsNothing);
    expect(raw.select('SELECT id FROM tags WHERE id = ?', [_id(52)]), isEmpty);
  });

  testWidgets('конфликт сохраняет ввод и выбирает существующий тег по id', (
    tester,
  ) async {
    late sqlite.Database raw;
    final database = AppDatabase(
      openInMemoryLocalDatabase(setup: (db) => raw = db),
    );
    await database.open();
    addTearDown(database.close);
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [_id(1), 'Дом']);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    final router = AppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'дом',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    for (
      var attempt = 0;
      attempt < 30 &&
          find
              .byKey(const ValueKey('tag-editor-use-existing'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('already exists'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
          .controller!
          .text,
      'дом',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-use-existing')));
    await _waitForEditorToClose(tester);
    expect(find.text('Дом'), findsOneWidget);
    expect(find.byTooltip('Rename tag'), findsOneWidget);
    expect(raw.select('SELECT id FROM tags'), hasLength(1));
    expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);
  });

  testWidgets('новый тег из выбора сохраняется до явного назначения связи', (
    tester,
  ) async {
    late sqlite.Database raw;
    final database = AppDatabase(
      openInMemoryLocalDatabase(setup: (db) => raw = db),
    );
    await database.open();
    addTearDown(database.close);
    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [_id(100), 'Первое', 0, 0, 100, 100],
    );
    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [_id(101), 'Второе', 0, 0, 101, 101],
    );
    raw.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [_id(200), _id(100), _id(101), 'need', 2, 1],
    );
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    final router = AppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final target = LongTermRelationTagTarget(
      (LongTermRelationId.decode(
        _id(200),
      ) as LongTermRelationIdDecodingSuccess).id,
    );
    final result = router.push<Object?>(TagCatalogRoute(target: target));
    await tester.pumpAndSettle();
    expect(find.text('Тегов пока нет.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Отмена',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
    await tester.pumpAndSettle();
    expect(router.current.argsAs<TagCatalogRouteArgs>().target, target);
    expect(raw.select('SELECT * FROM tags'), isEmpty);

    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Дом',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    await _waitForEditorToClose(tester);
    final tagId = raw.select('SELECT id FROM tags').single['id'] as String;
    expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);
    expect(find.text('Дом'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-catalog-assign')), findsOneWidget);
    expect(router.current.argsAs<TagCatalogRouteArgs>().target, target);

    router.pop();
    expect(await result, isNull);
    await tester.pumpAndSettle();
    expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);
    router.push<Object?>(TagCatalogRoute(target: target));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('tag-catalog-row-$tagId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
    await tester.pumpAndSettle();
    expect(
      raw.select(
        'SELECT tag_id FROM tag_assignments WHERE long_term_relation_id = ?',
        [_id(200)],
      ).single['tag_id'],
      tagId,
    );
  });

  testWidgets(
    'конфликт выбирает исходный тег, а исчезнувшего получателя не заменяет',
    (tester) async {
      late sqlite.Database raw;
      final database = AppDatabase(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
      );
      await database.open();
      addTearDown(database.close);
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [_id(100), 'Одинаковое имя', 0, 0, 100, 100],
      );
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [_id(1), 'Дом']);
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 25),
        InMemoryDiagnosticsSink(),
      );
      final router = AppRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = IntentionTagTarget(
        (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id,
      );
      router.push<Object?>(TagCatalogRoute(target: target));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'дом',
      );
      await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
      for (
        var attempt = 0;
        attempt < 30 &&
            find
                .byKey(const ValueKey('tag-editor-use-existing'))
                .evaluate()
                .isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
            .controller!
            .text,
        'дом',
      );
      await tester.tap(find.byKey(const ValueKey('tag-editor-use-existing')));
      await _waitForEditorToClose(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagCatalogPage)),
      );
      final catalog = container.read(
        tagCatalogViewModelProvider(mode: TagCatalogSelectionMode(target)),
      ) as TagCatalogLoaded;
      expect(catalog.selection.id?.toCanonicalString(), _id(1));
      expect(find.byKey(const ValueKey('tag-catalog-assign')), findsOneWidget);
      expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);

      raw.execute('DELETE FROM intentions WHERE id = ?', [_id(100)]);
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [_id(101), 'Одинаковое имя', 0, 0, 101, 101],
      );
      await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
      await tester.pumpAndSettle();
      expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);
      expect(router.current.argsAs<TagCatalogRouteArgs>().target, target);
    },
  );

  testWidgets('создание, переименование и отмена сохраняют каталог', (
    tester,
  ) async {
    late sqlite.Database raw;
    final database = AppDatabase(
      openInMemoryLocalDatabase(setup: (db) => raw = db),
    );
    await database.open();
    addTearDown(database.close);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    final router = AppRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      '  Дом  ',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    await _waitForEditorToClose(tester);
    expect(find.text('Дом'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Работа',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    await _waitForEditorToClose(tester);

    await tester.tap(find.byTooltip('Переименовать тег').first);
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Быт',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    await _waitForEditorToClose(tester);
    expect(find.text('Быт'), findsOneWidget);
    expect(find.text('Работа'), findsOneWidget);

    await tester.tap(find.byTooltip('Переименовать тег').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Отменённое имя',
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Быт'), findsOneWidget);
    expect(find.text('Отменённое имя'), findsNothing);
    expect(find.text('Работа'), findsOneWidget);
    expect(
      raw
          .select('SELECT name FROM tags ORDER BY creation_sequence')
          .map((row) => row['name']),
      ['Быт', 'Работа'],
    );
    expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);
  });

  testWidgets('переход открывает реальный каталог и все его порции', (
    tester,
  ) async {
    late sqlite.Database raw;
    final database = AppDatabase(
      openInMemoryLocalDatabase(setup: (db) => raw = db),
    );
    await database.open();
    addTearDown(database.close);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    final router = AppRouter();
    addTearDown(router.dispose);
    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [_id(100), 'Архивное намерение', 0, 1, 100, 100],
    );
    for (var number = 1; number <= 52; number++) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        _id(number),
        'Тег $number',
      ]);
    }
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [_id(52), _id(100)],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
    await tester.pumpAndSettle();

    expect(find.byType(TagCatalogPage), findsOneWidget);
    expect(find.text('Тег 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-catalog-load-more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Тег 52'),
      500,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('tag-catalog-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Тег 52'), findsOneWidget);
    expect(find.text('Все теги показаны.'), findsOneWidget);
  });

  testWidgets('начальная ошибка доступна для повтора на английском', (
    tester,
  ) async {
    final repository = _CatalogRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TagCatalogPage(),
        ),
      ),
    );
    expect(find.text('Loading tags…'), findsOneWidget);
    repository.complete(
      const TagCatalogPageError(TagCatalogUnavailableFailure()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tags couldn’t be loaded. Try again.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(repository.calls, 2);
  });

  testWidgets(
    'выбор показывает занятость и отказ на английском при крупном тексте',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _CatalogRepository();
      addTearDown(repository.dispose);
      final target = IntentionTagTarget(
        (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.5)),
              child: child!,
            ),
            home: TagCatalogPage(target: target),
          ),
        ),
      );
      repository.complete(
        TagCatalogPageSuccess(
          data.TagCatalogPage.selection(
            target: target,
            rows: [TagSelectionRow(tag: _tag(1, 'Home'), isAssigned: false)],
            pageSize: TagCatalogQuery.defaultPageSize,
            nextCursor: null,
            revision: const _Revision(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('tag-catalog-row-${_id(1)}')));
      repository.tagRead(_tag(1, 'Home'));
      await tester.pumpAndSettle();
      final assign = find.byKey(const ValueKey('tag-catalog-assign'));
      expect(find.text('Available to assign'), findsOneWidget);
      expect(assign, findsOneWidget);
      await tester.tap(assign);
      await tester.pump();
      expect(find.text('Assigning tag…'), findsOneWidget);
      expect(tester.widget<FilledButton>(assign).onPressed, isNull);
      repository.failCommand(const TagUnavailableFailure());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not complete the tag assignment operation. Try again.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('пустой каталог отличается от загрузки и отказа', (tester) async {
    final repository = _CatalogRepository();
    await _pumpCatalog(tester, repository);
    expect(find.text('Loading tags…'), findsOneWidget);
    repository.complete(_page([]));
    await tester.pumpAndSettle();
    expect(find.text('No tags yet.'), findsOneWidget);
    expect(find.text('Show more tags'), findsNothing);
  });

  testWidgets('отсутствие из наблюдения убирает строку и действия до пакета', (
    tester,
  ) async {
    final repository = _CatalogRepository();
    addTearDown(repository.dispose);
    await _pumpCatalog(tester, repository);
    repository.complete(_page([_tag(1, 'Дом'), _tag(2, 'Работа')]));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagCatalogPage)),
    );
    container
        .read(tagCatalogViewModelProvider().notifier)
        .selectTag(_tag(1, 'Дом').id);
    repository.tagRead(_tag(1, 'Дом'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('tag-catalog-row-${_id(1)}')), findsOneWidget);

    repository.tagRead(null, revision: 2);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(ValueKey('tag-catalog-row-${_id(1)}')), findsNothing);
    expect(find.byKey(ValueKey('tag-catalog-delete-${_id(1)}')), findsNothing);
    expect(find.byTooltip('Rename tag'), findsNothing);
    expect(find.text('Refreshing tags…'), findsOneWidget);

    repository.complete(_page([_tag(1, 'Дом'), _tag(2, 'Работа')]));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(ValueKey('tag-catalog-row-${_id(1)}')), findsNothing);
    expect(find.byKey(ValueKey('tag-catalog-delete-${_id(1)}')), findsNothing);
    expect(find.byTooltip('Rename tag'), findsNothing);
    expect(repository.queries, hasLength(3));

    repository.complete(_page([_tag(2, 'Работа')], revision: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('tag-catalog-row-${_id(1)}')), findsNothing);
    expect(find.byKey(ValueKey('tag-catalog-row-${_id(2)}')), findsOneWidget);
    expect(find.byTooltip('Rename tag'), findsOneWidget);
  });

  testWidgets('пакет после страницы обновляет выбранное имя вне порции', (
    tester,
  ) async {
    final repository = _CatalogRepository();
    addTearDown(repository.dispose);
    await _pumpCatalog(tester, repository);
    repository.complete(_page([_tag(1, 'Дом')], revision: 2));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagCatalogPage)),
    );
    container
        .read(tagCatalogViewModelProvider().notifier)
        .selectTag(_tag(52, 'Старое имя').id);
    repository.tagRead(_tag(52, 'Старое имя'));
    await tester.pumpAndSettle();
    expect(find.text('Старое имя'), findsOneWidget);

    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final accepted = coordinator.acceptTagRename(
      RenameTag(
        tagId: _tag(52, 'Старое имя').id,
        name: TagName.fromInput('Новое имя'),
      ),
    ) as TagCommandAccepted;
    repository.completeCommand(
      TagRenamed(
        TagRenamedChange(
          revision: const _Revision(2),
          before: _tag(52, 'Старое имя'),
          after: _tag(52, 'Новое имя'),
        ),
      ),
    );
    await accepted.future;
    repository.tagRead(_tag(52, 'Старое имя'));
    await tester.pumpAndSettle();

    expect(find.text('Новое имя'), findsOneWidget);
    expect(find.text('Старое имя'), findsNothing);
    expect(
      find.byKey(ValueKey('tag-catalog-delete-${_id(52)}')),
      findsOneWidget,
    );
    expect(repository.queries, hasLength(1));
  });

  testWidgets('пакет после страницы убирает удалённый выбор и действия', (
    tester,
  ) async {
    final repository = _CatalogRepository();
    addTearDown(repository.dispose);
    await _pumpCatalog(tester, repository);
    repository.complete(_page([_tag(1, 'Дом')], revision: 2));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagCatalogPage)),
    );
    container
        .read(tagCatalogViewModelProvider().notifier)
        .selectTag(_tag(52, 'Старое имя').id);
    repository.tagRead(_tag(52, 'Старое имя'));
    await tester.pumpAndSettle();
    expect(find.text('Старое имя'), findsOneWidget);

    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final accepted = coordinator.acceptTagDelete(
      DeleteTag(_tag(52, 'Старое имя').id),
    ) as TagCommandAccepted;
    repository.completeCommand(
      TagDeleted(
        TagDeletedChange(
          revision: const _Revision(2),
          tagId: _tag(52, 'Старое имя').id,
        ),
      ),
    );
    await accepted.future;
    repository.tagRead(_tag(52, 'Старое имя'));
    await tester.pumpAndSettle();

    expect(find.text('Старое имя'), findsNothing);
    expect(find.byKey(ValueKey('tag-catalog-delete-${_id(52)}')), findsNothing);
    expect(find.byTooltip('Rename tag'), findsOneWidget);
    expect(repository.queries, hasLength(1));
  });

  testWidgets(
    'подгрузка, повтор и длинное название доступны при крупном тексте',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _CatalogRepository();
      await _pumpCatalog(tester, repository, largeText: true);
      final cursor = _Cursor();
      final longName = '${'Тег ' * 39}Тег';
      repository.complete(_page([_tag(1, longName)], cursor: cursor));
      await tester.pumpAndSettle();
      expect(find.text(longName), findsOneWidget);
      expect(find.text('Show more tags'), findsOneWidget);

      await tester.tap(find.text('Show more tags'));
      await tester.pump();
      expect(find.text('Loading more tags…'), findsOneWidget);
      expect(repository.queries.last.cursor, same(cursor));
      repository.complete(
        const TagCatalogPageError(TagCatalogUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text('More tags couldn’t be loaded.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(repository.queries.last.cursor, same(cursor));
      repository.complete(_page([_tag(2, 'Other')]));
      await tester.pumpAndSettle();
      expect(find.text('All tags are shown.'), findsOneWidget);
      expect(find.text('Show more tags'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _waitForEditorToClose(WidgetTester tester) async {
  for (
    var attempt = 0;
    attempt < 30 &&
        find.byKey(const ValueKey('tag-editor-name')).evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
  expect(find.byKey(const ValueKey('tag-editor-name')), findsNothing);
}

Future<void> _pumpCatalog(
  WidgetTester tester,
  _CatalogRepository repository, {
  bool largeText = false,
  TagTarget? target,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(largeText ? 2.5 : 1)),
          child: child!,
        ),
        home: TagCatalogPage(target: target),
      ),
    ),
  );
}

TagCatalogPageSuccess _page(
  List<Tag> tags, {
  TagCatalogCursor? cursor,
  int revision = 1,
}) => TagCatalogPageSuccess(
  data.TagCatalogPage(
    items: tags,
    pageSize: TagCatalogQuery.defaultPageSize,
    nextCursor: cursor,
    revision: _Revision(revision),
  ),
);

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(_id(number)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);

final class _Revision implements GraphRevision {
  const _Revision([this.number = 1]);

  final int number;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(number: final value) when number < value =>
      GraphRevisionOrder.older,
    _Revision(number: final value) when number > value =>
      GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

final class _Cursor implements TagCatalogCursor {}

final class _CatalogRepository extends Fake implements PersonalGraphRepository {
  final _pending = <Completer<TagCatalogPageResult>>[];
  final _commands = <Completer<TagCommandResult>>[];
  final _tagReads = StreamController<TagReadResult>.broadcast();
  final statusReads = <Completer<TagAssignmentStatusResult>>[];
  final queries = <TagCatalogQuery>[];
  int get calls => _pending.length;

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId id,
    TagTarget target,
  ) {
    final read = Completer<TagAssignmentStatusResult>();
    statusReads.add(read);
    return read.future;
  }

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) {
    queries.add(query);
    final request = Completer<TagCatalogPageResult>();
    _pending.add(request);
    return request.future;
  }

  void complete(TagCatalogPageResult result) => _pending.last.complete(result);

  @override
  Stream<TagReadResult> watchTag(TagId id) => _tagReads.stream;

  void tagRead(Tag? tag, {int revision = 1}) => _tagReads.add(
    TagReadSuccess(GraphSnapshot(value: tag, revision: _Revision(revision))),
  );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final pending = Completer<TagCommandResult>();
    _commands.add(pending);
    return await pending.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void completeCommand(TagCommandSuccess success) => _commands.last.complete(
    TagCommandSucceeded(
      ConfirmedGraphResult(revision: const _Revision(2), value: success),
    ),
  );

  void failCommand(TagCommandFailure failure) =>
      _commands.last.complete(TagCommandFailed(failure));

  Future<void> dispose() => _tagReads.close();
}
