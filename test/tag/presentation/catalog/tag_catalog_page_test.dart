import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tag;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart'
    hide TagCatalogPage;
import 'package:doable/src/tag/application/tag_catalog.dart'
    as data
    show TagCatalogPage;
import 'package:doable/src/tag/application/tag_command.dart';
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

void main() {
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

  testWidgets('пустой каталог отличается от загрузки и отказа', (tester) async {
    final repository = _CatalogRepository();
    await _pumpCatalog(tester, repository);
    expect(find.text('Loading tags…'), findsOneWidget);
    repository.complete(_page([]));
    await tester.pumpAndSettle();
    expect(find.text('No tags yet.'), findsOneWidget);
    expect(find.text('Show more tags'), findsNothing);
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
        home: const TagCatalogPage(),
      ),
    ),
  );
}

TagCatalogPageSuccess _page(List<Tag> tags, {TagCatalogCursor? cursor}) =>
    TagCatalogPageSuccess(
      data.TagCatalogPage(
        items: tags,
        pageSize: TagCatalogQuery.defaultPageSize,
        nextCursor: cursor,
        revision: const _Revision(),
      ),
    );

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(_id(number)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

final class _Cursor implements TagCatalogCursor {}

final class _CatalogRepository extends Fake implements PersonalGraphRepository {
  final _pending = <Completer<TagCatalogPageResult>>[];
  final queries = <TagCatalogQuery>[];
  int get calls => _pending.length;

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) {
    queries.add(query);
    final request = Completer<TagCatalogPageResult>();
    _pending.add(request);
    return request.future;
  }

  void complete(TagCatalogPageResult result) => _pending.last.complete(result);
}
