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
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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
  for (final (second, recipient) in [
    (false, 'первого намерения'),
    (true, 'другого намерения'),
  ]) {
    for (final assigned in [false, true]) {
      testWidgets(
        'экран сохраняет повтор после исчерпания устаревших проверок $recipient: ${assigned ? 'назначен' : 'свободен'}',
        (tester) async {
          final repository = _CatalogRepository();
          addTearDown(repository.dispose);
          final intentionId = second
              ? (IntentionId.decode(_id(101)) as IntentionIdDecodingSuccess).id
              : (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
          await _pumpCatalog(tester, repository, intentionId: intentionId);
          repository.complete(
            TagCatalogSuccess(
              TagCatalogSnapshot.selection(
                intentionId: intentionId,
                rows: [
                  TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
                ],

                revision: const _Revision(2),
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
                  mode: TagCatalogSelectionMode(intentionId),
                ).notifier,
              )
              .selectTag(_tag(52, 'Из редактора').id);
          repository.tagRead(_tag(52, 'Из редактора'), revision: 2);
          await tester.pumpAndSettle();
          final assign = find.byKey(const ValueKey('tag-catalog-assign'));
          expect(tester.widget<FilledButton>(assign).onPressed, isNull);

          for (var index = 0; index < 8; index++) {
            repository.statusReads[index].complete(
              const TagAssignmentStatusSuccess(
                GraphSnapshot(value: false, revision: _Revision(1)),
              ),
            );
            await tester.pumpAndSettle();
          }
          expect(repository.statusReads, hasLength(8));
          expect(find.text('Try again'), findsOneWidget);
          expect(tester.widget<FilledButton>(assign).onPressed, isNull);

          await tester.tap(find.text('Try again'));
          await tester.pump();
          expect(repository.statusReads, hasLength(9));
          for (var index = 8; index < 11; index++) {
            repository.statusReads[index].complete(
              const TagAssignmentStatusSuccess(
                GraphSnapshot(value: false, revision: _Revision(1)),
              ),
            );
            await tester.pumpAndSettle();
            expect(repository.statusReads, hasLength(index + 2));
            expect(find.text('Try again'), findsNothing);
            expect(tester.widget<FilledButton>(assign).onPressed, isNull);
          }
          repository.statusReads[11].complete(
            TagAssignmentStatusSuccess(
              GraphSnapshot(value: assigned, revision: const _Revision(2)),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Try again'), findsNothing);
          if (assigned) {
            expect(tester.widget<FilledButton>(assign).onPressed, isNull);
          } else {
            expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
          }
          expect(repository._commands, isEmpty);
        },
      );
    }
    for (final assigned in [false, true]) {
      testWidgets(
        'экран сохраняет статус полного снимка после позднего отказа для $recipient: ${assigned ? 'назначен' : 'свободен'}',
        (tester) async {
          final repository = _CatalogRepository();
          addTearDown(repository.dispose);
          final intentionId = second
              ? (IntentionId.decode(_id(101)) as IntentionIdDecodingSuccess).id
              : (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
          await _pumpCatalog(tester, repository, intentionId: intentionId);
          repository.complete(
            TagCatalogSuccess(
              TagCatalogSnapshot.selection(
                intentionId: intentionId,
                rows: [
                  TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
                ],

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
                  mode: TagCatalogSelectionMode(intentionId),
                ).notifier,
              )
              .selectTag(_tag(52, 'Из редактора').id);
          repository.tagRead(_tag(52, 'Из редактора'));
          await tester.pumpAndSettle();
          expect(repository.statusReads, hasLength(1));
          final assign = find.byKey(const ValueKey('tag-catalog-assign'));
          expect(tester.widget<FilledButton>(assign).onPressed, isNull);

          final accepted =
              container
                      .read(graphCommandCoordinatorProvider.notifier)
                      .acceptTagCreation(
                        TagCreationFormKey(),
                        CreateTag(TagName.fromInput('Из редактора')),
                      )
                  as TagCommandAccepted;
          repository.completeCommand(
            TagCreated(
              TagCreatedChange(
                revision: const _Revision(2),
                after: _tag(52, 'Из редактора'),
              ),
            ),
          );
          await accepted.future;
          await tester.pump();
          repository.complete(
            TagCatalogSuccess(
              TagCatalogSnapshot.selection(
                intentionId: intentionId,
                rows: [
                  TagSelectionRow(
                    tag: _tag(52, 'Из редактора'),
                    isAssigned: assigned,
                  ),
                ],

                revision: const _Revision(2),
              ),
            ),
          );
          await tester.pumpAndSettle();
          repository.statusReads.first.complete(
            const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
          );
          await tester.pumpAndSettle();

          expect(
            find.text('Could not load assignments. Try again.'),
            findsNothing,
          );
          expect(find.text('Try again'), findsNothing);
          expect(repository.statusReads, hasLength(2));
          if (assigned) {
            expect(tester.widget<FilledButton>(assign).onPressed, isNull);
            expect(repository._commands, hasLength(1));
          } else {
            expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
          }
        },
      );
    }
  }

  for (final (second, recipient) in [
    (false, 'первого намерения'),
    (true, 'другого намерения'),
  ]) {
    for (final assigned in [false, true]) {
      for (final tagReadFirst in [false, true]) {
        testWidgets(
          'экран повторяет проверку пары $recipient после ${tagReadFirst ? 'раннего' : 'позднего'} чтения тега: ${assigned ? 'назначен' : 'свободен'}',
          (tester) async {
            final repository = _CatalogRepository();
            addTearDown(repository.dispose);
            final intentionId = second
                ? (IntentionId.decode(
                    _id(101),
                  ) as IntentionIdDecodingSuccess).id
                : (IntentionId.decode(
                    _id(100),
                  ) as IntentionIdDecodingSuccess).id;
            await _pumpCatalog(tester, repository, intentionId: intentionId);
            repository.complete(
              TagCatalogSuccess(
                TagCatalogSnapshot.selection(
                  intentionId: intentionId,
                  rows: [
                    TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
                  ],

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
                    mode: TagCatalogSelectionMode(intentionId),
                  ).notifier,
                )
                .selectTag(_tag(52, 'Из редактора').id);
            if (tagReadFirst) {
              repository.tagRead(_tag(52, 'Из редактора'));
            }
            repository.statusReads.single.complete(
              const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
            );
            await tester.pump();
            await tester.pump();
            if (!tagReadFirst) {
              repository.tagRead(_tag(52, 'Из редактора'));
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
              expect(tester.widget<FilledButton>(assign).onPressed, isNull);
              expect(repository._commands, isEmpty);
            } else {
              expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
            }
          },
        );
      }
    }
  }

  for (final (second, recipient) in [
    (false, 'первого намерения'),
    (true, 'другого намерения'),
  ]) {
    for (final assigned in [false, true]) {
      testWidgets(
        'редактор подтверждает уже загруженный ${assigned ? 'назначенный' : 'свободный'} тег для $recipient',
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
              'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
              [_id(52), _id(second ? 101 : 100)],
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
          final intentionId = second
              ? (IntentionId.decode(_id(101)) as IntentionIdDecodingSuccess).id
              : (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
          router.push<Object?>(TagCatalogRoute(intentionId: intentionId));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('tag-catalog-load-more')),
            findsNothing,
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
            findsNothing,
          );
          final assign = find.byKey(const ValueKey('tag-catalog-assign'));
          if (assigned) {
            expect(tester.widget<FilledButton>(assign).onPressed, isNull);
          } else {
            expect(assign, findsOneWidget);
            expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
            await tester.tap(assign);
            await tester.pumpAndSettle();
            expect(
              raw
                  .select(
                    'SELECT tag_id FROM tag_assignments WHERE intention_id = ?',
                    [_id(second ? 101 : 100)],
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
      final intentionId =
          (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
      final result = router.push<Object?>(
        TagCatalogRoute(intentionId: intentionId),
      );
      await tester.pumpAndSettle();

      expect(find.text('Выбор тега'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagCatalogPage)),
      );
      final catalog = container.read(
        tagCatalogViewModelProvider(mode: TagCatalogSelectionMode(intentionId)),
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

      final lastRow = find.byKey(ValueKey('tag-catalog-row-${_id(52)}'));
      await tester.scrollUntilVisible(
        lastRow,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('tag-catalog-list')),
              matching: find.byType(Scrollable),
            )
            .first,
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
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('tag-catalog-assign')),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Тег 52'),
        -300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('tag-catalog-list')),
              matching: find.byType(Scrollable),
            )
            .first,
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
              tagCatalogViewModelProvider(
                mode: TagCatalogSelectionMode(intentionId),
              ).notifier,
            )
            .assignSelected(),
        isNull,
      );

      await tester.scrollUntilVisible(
        lastRow,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('tag-catalog-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.descendant(of: lastRow, matching: find.text('Назначен')),
        findsOneWidget,
      );
      router.pop();
      expect(await result, isNull);
      await tester.pumpAndSettle();

      final secondIntentionId =
          (IntentionId.decode(_id(101)) as IntentionIdDecodingSuccess).id;
      final secondResult = router.push<Object?>(
        TagCatalogRoute(intentionId: secondIntentionId),
      );
      await tester.pumpAndSettle();
      expect(
        router.current.argsAs<TagCatalogRouteArgs>().intentionId,
        secondIntentionId,
      );
      await tester.tap(find.byKey(ValueKey('tag-catalog-row-${_id(2)}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        lastRow,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('tag-catalog-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(lastRow);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-catalog-assign')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('tag-catalog-assign')),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Тег 52'),
        -300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('tag-catalog-list')),
              matching: find.byType(Scrollable),
            )
            .first,
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
      final secondContainer = ProviderScope.containerOf(
        tester.element(find.byType(TagCatalogPage)),
      );
      expect(
        secondContainer
            .read(
              tagCatalogViewModelProvider(
                mode: TagCatalogSelectionMode(secondIntentionId),
              ).notifier,
            )
            .assignSelected(),
        isNull,
      );
      expect(
        raw
            .select(
              'SELECT tag_id FROM tag_assignments WHERE intention_id = ?',
              [_id(101)],
            )
            .map((row) => row['tag_id']),
        containsAll([_id(2), _id(52)]),
      );
      router.pop();
      expect(await secondResult, isNull);
    },
  );

  testWidgets('выбор из полного каталога следует внешним изменениям тега', (
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
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsNothing);
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
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('tag-catalog-row-${_id(52)}')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('tag-catalog-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Дом'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsNothing);

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
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsNothing);

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

  testWidgets(
    'новый тег из выбора сохраняется до явного назначения другому намерению',
    (tester) async {
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
      final intentionId =
          (IntentionId.decode(_id(101)) as IntentionIdDecodingSuccess).id;
      final result = router.push<Object?>(
        TagCatalogRoute(intentionId: intentionId),
      );
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
      expect(
        router.current.argsAs<TagCatalogRouteArgs>().intentionId,
        intentionId,
      );
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
      expect(
        router.current.argsAs<TagCatalogRouteArgs>().intentionId,
        intentionId,
      );

      router.pop();
      expect(await result, isNull);
      await tester.pumpAndSettle();
      expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);
      router.push<Object?>(TagCatalogRoute(intentionId: intentionId));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('tag-catalog-row-$tagId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
      await tester.pumpAndSettle();
      expect(
        raw.select(
          'SELECT tag_id FROM tag_assignments WHERE intention_id = ?',
          [_id(101)],
        ).single['tag_id'],
        tagId,
      );
    },
  );

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
      final intentionId =
          (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
      router.push<Object?>(TagCatalogRoute(intentionId: intentionId));
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
        tagCatalogViewModelProvider(mode: TagCatalogSelectionMode(intentionId)),
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
      expect(
        router.current.argsAs<TagCatalogRouteArgs>().intentionId,
        intentionId,
      );
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

  testWidgets('переход открывает все 150 тегов реального каталога', (
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
    for (var number = 1; number <= 150; number++) {
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
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Тег 150'),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('tag-catalog-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Тег 150'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TagCatalogPage)),
    );
    expect(
      (container.read(tagCatalogViewModelProvider()) as TagCatalogLoaded).items,
      hasLength(150),
    );
    expect(find.byKey(const ValueKey('tag-catalog-load-more')), findsNothing);
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
    repository.complete(const TagCatalogError(TagCatalogUnavailableFailure()));
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
      final intentionId =
          (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
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
            home: TagCatalogPage(intentionId: intentionId),
          ),
        ),
      );
      repository.complete(
        TagCatalogSuccess(
          TagCatalogSnapshot.selection(
            intentionId: intentionId,
            rows: [TagSelectionRow(tag: _tag(1, 'Home'), isAssigned: false)],

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

  testWidgets(
    'пустой снимок выбора сохраняет недоступное действие назначения',
    (tester) async {
      final repository = _CatalogRepository();
      addTearDown(repository.dispose);
      final intentionId =
          (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
      await _pumpCatalog(tester, repository, intentionId: intentionId);
      repository.complete(
        TagCatalogSuccess(
          TagCatalogSnapshot.selection(
            intentionId: intentionId,
            rows: const [],
            revision: const _Revision(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No tags yet.'), findsOneWidget);
      final assign = find.byKey(const ValueKey('tag-catalog-assign'));
      expect(assign, findsOneWidget);
      expect(tester.widget<FilledButton>(assign).onPressed, isNull);
      expect(repository._commands, isEmpty);
      expect(find.text('Loading tags…'), findsNothing);
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

  testWidgets('пакет после снимка обновляет выбранное имя из редактора', (
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

  testWidgets('пакет после снимка убирает удалённый выбор и действия', (
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
    'фоновое обновление и его повтор сохраняют выбор и прокрутку каталога',
    (tester) async {
      final repository = _CatalogRepository();
      addTearDown(repository.dispose);
      final intentionId =
          (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
      await _pumpCatalog(tester, repository, intentionId: intentionId);
      final rows = [
        for (var number = 1; number <= 30; number++)
          TagSelectionRow(tag: _tag(number, 'Тег $number'), isAssigned: false),
      ];
      repository.complete(
        TagCatalogSuccess(
          TagCatalogSnapshot.selection(
            intentionId: intentionId,
            rows: rows,
            revision: const _Revision(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('tag-catalog-list'));
      final scrollable = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      await tester.drag(list, const Offset(0, -900));
      await tester.pumpAndSettle();
      final scrollState = tester.state<ScrollableState>(scrollable);
      final offset = scrollState.position.pixels;
      expect(offset, greaterThan(0));
      final container = ProviderScope.containerOf(tester.element(list));
      final provider = tagCatalogViewModelProvider(
        mode: TagCatalogSelectionMode(intentionId),
      );
      final model = container.read(provider.notifier);
      model.selectTag(_tag(21, 'Тег 21').id);
      await tester.pump();
      final accepted =
          container
                  .read(graphCommandCoordinatorProvider.notifier)
                  .acceptTagRename(
                    RenameTag(
                      tagId: _tag(1, 'Тег 1').id,
                      name: TagName.fromInput('Новое имя'),
                    ),
                  )
              as TagCommandAccepted;
      repository.completeCommand(
        TagRenamed(
          TagRenamedChange(
            revision: const _Revision(2),
            before: _tag(1, 'Тег 1'),
            after: _tag(1, 'Новое имя'),
          ),
        ),
      );
      await accepted.future;
      await tester.pump();
      expect(tester.state<ScrollableState>(scrollable), same(scrollState));
      expect(scrollState.position.pixels, offset);
      expect(
        (container.read(provider) as TagCatalogLoaded).selection.id,
        _tag(21, 'Тег 21').id,
      );
      final assign = find.byKey(const ValueKey('tag-catalog-assign'));
      expect(tester.widget<FilledButton>(assign).onPressed, isNull);

      repository.complete(
        const TagCatalogError(TagCatalogUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrollable), same(scrollState));
      expect(scrollState.position.pixels, offset);
      final stale = container.read(provider) as TagCatalogLoaded;
      expect(stale.items, hasLength(30));
      expect(stale.selection.id, _tag(21, 'Тег 21').id);
      expect(stale.freshness, TagCatalogFreshness.stale);
      final retry = model.retryRefresh();
      repository.complete(
        TagCatalogSuccess(
          TagCatalogSnapshot.selection(
            intentionId: intentionId,
            rows: [
              TagSelectionRow(tag: _tag(1, 'Новое имя'), isAssigned: false),
              ...rows.skip(1),
            ],
            revision: const _Revision(2),
          ),
        ),
      );
      await retry;
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scrollable), same(scrollState));
      expect(scrollState.position.pixels, offset);
      expect(
        (container.read(provider) as TagCatalogLoaded).selection.id,
        _tag(21, 'Тег 21').id,
      );
      expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
    },
  );

  testWidgets(
    'полное обновление, повтор и длинное название доступны при крупном тексте',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _CatalogRepository();
      addTearDown(repository.dispose);
      await _pumpCatalog(tester, repository, largeText: true);
      final longName = '${'Тег ' * 39}Тег';
      repository.complete(_page([_tag(1, longName)]));
      await tester.pumpAndSettle();
      expect(find.text(longName), findsOneWidget);
      expect(find.text('Show more tags'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagCatalogPage)),
      );
      final accepted =
          container
                  .read(graphCommandCoordinatorProvider.notifier)
                  .acceptTagCreation(
                    TagCreationFormKey(),
                    CreateTag(TagName.fromInput('Другой')),
                  )
              as TagCommandAccepted;
      repository.completeCommand(
        TagCreated(
          TagCreatedChange(
            revision: const _Revision(2),
            after: _tag(2, 'Другой'),
          ),
        ),
      );
      await accepted.future;
      await tester.pump();
      expect(find.text(longName), findsOneWidget);
      expect(find.text('Refreshing tags…'), findsOneWidget);
      repository.complete(
        const TagCatalogError(TagCatalogUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text(longName), findsOneWidget);
      expect(find.text('Tags couldn’t be loaded. Try again.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(repository.queries, [
        const TagCatalogBrowseMode(),
        const TagCatalogBrowseMode(),
        const TagCatalogBrowseMode(),
      ]);
      repository.complete(
        _page([_tag(1, longName), _tag(2, 'Другой')], revision: 2),
      );
      await tester.pumpAndSettle();
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
  IntentionId? intentionId,
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
        home: TagCatalogPage(intentionId: intentionId),
      ),
    ),
  );
}

TagCatalogSuccess _page(List<Tag> tags, {int revision = 1}) =>
    TagCatalogSuccess(
      TagCatalogSnapshot(items: tags, revision: _Revision(revision)),
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

final class _CatalogRepository extends Fake implements PersonalGraphRepository {
  final _pending = <Completer<TagCatalogResult>>[];
  final _commands = <Completer<TagCommandResult>>[];
  final _tagReads = StreamController<TagReadResult>.broadcast();
  final statusReads = <Completer<TagAssignmentStatusResult>>[];
  final queries = <TagCatalogMode>[];
  int get calls => _pending.length;

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId id,
    IntentionId intentionId,
  ) {
    final read = Completer<TagAssignmentStatusResult>();
    statusReads.add(read);
    return read.future;
  }

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) {
    queries.add(mode);
    final request = Completer<TagCatalogResult>();
    _pending.add(request);
    return request.future;
  }

  void complete(TagCatalogResult result) => _pending.last.complete(result);

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
