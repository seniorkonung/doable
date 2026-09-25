import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tag;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart'
    hide TagCatalogPage;
import 'package:doable/src/tag/application/tag_catalog.dart'
    as data
    show TagCatalogPage;
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

TagId _tagId(int number) =>
    (TagId.decode(_id(number)) as TagIdDecodingSuccess).id;

void main() {
  testWidgets(
    'отмена не удаляет; подтверждение охватывает незагруженные назначения и сохраняет граф',
    (tester) async {
      late sqlite.Database raw;
      final database = AppDatabase(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
      );
      await database.open();
      addTearDown(database.close);
      for (var i = 1; i <= 105; i++) {
        raw.execute(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          [_id(i), 'Намерение $i', 0, i.isEven ? 1 : 0, i, i],
        );
      }
      for (final (id, archived) in [(201, 0), (202, 1)]) {
        raw.execute(
          'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
          [
            _id(id),
            _id(1),
            _id(id == 201 ? 3 : 4),
            id == 201 ? 'need' : 'can',
            2,
            archived,
          ],
        );
      }
      raw.execute(
        'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
        [_id(203), _id(1), _id(3), '2026-09-25', 0],
      );
      raw.execute(
        'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
        [_id(204), _id(203), _id(201)],
      );
      for (var i = 1; i <= 52; i++) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          _id(300 + i),
          'Тег $i',
        ]);
      }
      for (var i = 1; i <= 104; i++) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_id(301), _id(i)],
        );
      }
      for (final id in [201, 202]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
          [_id(301), _id(id)],
        );
      }
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [_id(302), _id(105)],
      );
      final retained = {
        for (final table in [
          'intentions',
          'long_term_relations',
          'daily_choices',
          'daily_choice_path_steps',
        ])
          table: raw
              .select('SELECT * FROM $table ORDER BY rowid')
              .map((row) => row.values.toList())
              .toList(),
      };
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 25),
        InMemoryDiagnosticsSink(),
      );
      await _openRealCatalog(tester, repository);
      expect(
        find.byKey(const ValueKey('tag-catalog-load-more')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-delete-cancel')));
      await tester.pumpAndSettle();
      expect(
        raw.select('SELECT * FROM tags WHERE id = ?', [_id(301)]),
        hasLength(1),
      );
      expect(
        raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
          _id(301),
        ]),
        hasLength(106),
      );

      await tester.tap(find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')));
      await tester.pumpAndSettle();
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [_id(301), _id(105)],
      );
      await tester.tap(find.byKey(const ValueKey('tag-delete-confirm')));
      await _pumpUntil(
        tester,
        () => raw.select('SELECT * FROM tags WHERE id = ?', [_id(301)]).isEmpty,
      );
      expect(
        raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
          _id(301),
        ]),
        isEmpty,
      );
      expect(
        raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
          _id(302),
        ]),
        hasLength(1),
      );
      for (final entry in retained.entries) {
        expect(
          raw
              .select('SELECT * FROM ${entry.key} ORDER BY rowid')
              .map((row) => row.values.toList())
              .toList(),
          entry.value,
        );
      }
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'сбой каскада оставляет тег и назначения, а ошибка отличается от успеха',
    (tester) async {
      late sqlite.Database raw;
      final database = AppDatabase(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
      );
      await database.open();
      addTearDown(database.close);
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [_id(1), 'Дом', 0, 1, 1, 1],
      );
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        _id(301),
        'Дом',
      ]);
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [_id(301), _id(1)],
      );
      raw.execute('''
      CREATE TEMP TRIGGER fail_tag_cascade AFTER DELETE ON tag_assignments
      WHEN OLD.tag_id = '${_id(301)}'
      BEGIN SELECT RAISE(ABORT, 'injected cascade failure'); END
    ''');
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 25),
        InMemoryDiagnosticsSink(),
      );
      await _openRealCatalog(tester, repository);
      await tester.tap(find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-delete-confirm')));
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('tag-delete-failure'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.textContaining('непредвиденной ошибки'), findsWidgets);
      expect(raw.select('SELECT * FROM tags'), hasLength(1));
      expect(raw.select('SELECT * FROM tag_assignments'), hasLength(1));
      expect(
        find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')),
        findsOneWidget,
      );
    },
  );

  testWidgets('устаревший id не удаляет новый одноимённый тег', (tester) async {
    late sqlite.Database raw;
    final database = AppDatabase(
      openInMemoryLocalDatabase(setup: (db) => raw = db),
    );
    await database.open();
    addTearDown(database.close);
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [_id(301), 'Дом']);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    await _openRealCatalog(tester, repository);
    await tester.tap(find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')));
    await tester.pumpAndSettle();
    raw.execute('DELETE FROM tags WHERE id = ?', [_id(301)]);
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [_id(302), 'Дом']);
    await tester.tap(find.byKey(const ValueKey('tag-delete-confirm')));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('tag-delete-failure'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.textContaining('больше нет'), findsWidgets);
    expect(raw.select('SELECT id FROM tags').single['id'], _id(302));
  });

  testWidgets('повторный вход не обходит занятый ключ тега', (tester) async {
    final repository = _PendingRepository();
    final container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final first = container
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptTagDelete(DeleteTag(_tagId(301)));
    expect(first, isA<TagCommandAccepted>());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TagCatalogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-delete-confirm')));
    await tester.pumpAndSettle();
    expect(repository.commands, 1);
    expect(find.textContaining('уже выполняется'), findsWidgets);
    repository.finish();
    await tester.pumpAndSettle();
  });
}

Future<void> _openRealCatalog(
  WidgetTester tester,
  PersonalGraphRepository repository,
) async {
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
        builder: (context, child) => GraphOperationPresenter(child: child!),
      ),
    ),
  );
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 30 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

final class _PendingRepository extends Fake implements PersonalGraphRepository {
  final _pending = Completer<TagCommandResult>();
  int commands = 0;

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) async =>
      TagCatalogPageSuccess(
        data.TagCatalogPage(
          items: [Tag(id: _tagId(301), name: TagName.fromInput('Дом'))],
          pageSize: TagCatalogQuery.defaultPageSize,
          nextCursor: null,
          revision: const _Revision(),
        ),
      );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands++;
    return await _pending.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void finish() =>
      _pending.complete(const TagCommandFailed(TagUnavailableFailure()));
}

final class _Revision implements GraphRevision {
  const _Revision();
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}
