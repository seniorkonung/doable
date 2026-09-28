import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tag;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';

void main() {
  for (final locale in ['ru', 'en']) {
    for (final (number, archivedOnly) in [(303, false), (304, true)]) {
      testWidgets(
        'каталог открывает ${archivedOnly ? 'тег только в архиве' : 'тег без назначений'} и возвращается без записи на $locale',
        (tester) async {
          final h = await _pumpCatalog(tester, locale: locale);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(TagCatalogPage)),
          );
          final before = _tagData(h.raw);
          final open = _open(number);
          expect(open, findsOneWidget);
          expect(
            tester.widget<IconButton>(open).tooltip,
            l10n.tagNavigationTitle,
          );

          await tester.tap(open);
          await tester.pumpAndSettle();
          expect(h.router.current.name, TagNavigationRoute.name);
          expect(
            h.router.current.argsAs<TagNavigationRouteArgs>().tagId,
            _tagId(number),
          );
          expect(
            tester
                .widget<ChoiceChip>(_scope(TaggedEntitiesScope.active))
                .selected,
            isTrue,
          );
          expect(find.text(l10n.tagNavigationEmptyActive), findsOneWidget);
          await tester.tap(_scope(TaggedEntitiesScope.archived));
          await tester.pumpAndSettle();
          expect(
            archivedOnly
                ? find.text('Намерение 2')
                : find.text(l10n.tagNavigationEmptyArchived),
            findsOneWidget,
          );

          h.router.pop();
          await tester.pumpAndSettle();
          expect(h.router.current.name, TagCatalogRoute.name);
          expect(_open(number), findsOneWidget);
          expect(find.byTooltip(l10n.tagCatalogRename), findsNWidgets(4));
          expect(find.byTooltip(l10n.tagCatalogDelete), findsNWidgets(4));
          expect(
            find.byKey(const ValueKey('tag-catalog-create')),
            findsOneWidget,
          );

          await tester.tap(_open(number));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ChoiceChip>(_scope(TaggedEntitiesScope.active))
                .selected,
            isTrue,
          );
          expect(_tagData(h.raw), before);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'переход доступен с длинным названием и крупным текстом на $locale',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final name = ('Длинный тег ' * 15).trimRight();
          final h = await _pumpCatalog(
            tester,
            locale: locale,
            textScale: 3,
            size: const Size(360, 800),
            seed: (raw) => raw.execute(
              'UPDATE tags SET name = ? WHERE id = ?',
              [name, tagFixtureId(303)],
            ),
          );
          final l10n = AppLocalizations.of(
            tester.element(find.byType(TagCatalogPage)),
          );
          await tester.ensureVisible(_open(303));
          await tester.pumpAndSettle();
          final node = tester.getSemantics(_open(303));
          expect(node.tooltip, l10n.tagNavigationTitle);
          expect(node.flagsCollection.isButton, isTrue);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(_open(303));
          await tester.pumpAndSettle();
          expect(
            h.router.current.argsAs<TagNavigationRouteArgs>().tagId,
            _tagId(303),
          );
          expect(find.text(l10n.tagNavigationTag(name)), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'выбор из полного каталога сохраняет идентичность при переименовании и удалении',
    (tester) async {
      final h = await _pumpCatalog(
        tester,
        seed: (raw) {
          for (var number = 305; number <= 352; number++) {
            raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
              tagFixtureId(number),
              'Тег $number',
            ]);
          }
        },
      );
      final model = h.container.read(tagCatalogViewModelProvider().notifier);
      model.selectTag(_tagId(352));
      await tester.pumpAndSettle();
      expect(
        (h.container.read(
          tagCatalogViewModelProvider(),
        ) as TagCatalogLoaded).items,
        hasLength(52),
      );
      await tester.scrollUntilVisible(
        _open(352),
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('tag-catalog-list')),
          matching: find.byType(Scrollable),
        ),
      );
      final oldCallback = tester.widget<IconButton>(_open(352)).onPressed!;
      await tester.tap(_open(352));
      await tester.pumpAndSettle();
      expect(
        h.router.current.argsAs<TagNavigationRouteArgs>().tagId,
        _tagId(352),
      );
      h.router.pop();
      await tester.pumpAndSettle();
      expect(_open(352), findsOneWidget);
      final coordinator = h.container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final renamed = coordinator.acceptTagRename(
        RenameTag(tagId: _tagId(352), name: TagName.fromInput('Новое имя')),
      ) as TagCommandAccepted;
      expect((await renamed.future).result, isA<GraphResultSuccess>());
      await tester.pumpAndSettle();
      expect(find.text('Новое имя'), findsOneWidget);
      expect(
        (h.container.read(
          tagCatalogViewModelProvider(),
        ) as TagCatalogLoaded).items,
        hasLength(52),
      );
      oldCallback();
      await tester.pumpAndSettle();
      expect(
        h.router.current.argsAs<TagNavigationRouteArgs>().tagId,
        _tagId(352),
      );
      expect(find.text('Тег: Новое имя'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();

      final deleted = coordinator.acceptTagDelete(
        DeleteTag(_tagId(352)),
      ) as TagCommandAccepted;
      expect((await deleted.future).result, isA<GraphResultSuccess>());
      await tester.pumpAndSettle();
      final created = coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(TagName.fromInput('Новое имя')),
      ) as TagCommandAccepted;
      expect((await created.future).result, isA<GraphResultSuccess>());
      await tester.pumpAndSettle();
      expect(
        h.raw.select('SELECT id FROM tags WHERE name = ?', [
          'Новое имя',
        ]).single['id'],
        isNot(tagFixtureId(352)),
      );
      expect(_open(352), findsNothing);
      oldCallback();
      await tester.pumpAndSettle();
      expect(h.router.current.name, TagCatalogRoute.name);
      expect(tester.takeException(), isNull);
    },
  );

  for (final relation in [false, true]) {
    testWidgets(
      'режим назначения ${relation ? 'связи' : 'намерению'} сохраняет явный выбор',
      (tester) async {
        final target = relation
            ? LongTermRelationTagTarget(
                (LongTermRelationId.decode(
                  tagFixtureId(101),
                ) as LongTermRelationIdDecodingSuccess).id,
              )
            : IntentionTagTarget(
                (IntentionId.decode(
                  tagFixtureId(1),
                ) as IntentionIdDecodingSuccess).id,
              );
        final h = await _pumpCatalog(tester, target: target);
        final before = _tagData(h.raw);
        expect(find.byTooltip('Сущности с тегом'), findsNothing);
        await tester.tap(
          find.byKey(ValueKey('tag-catalog-row-${tagFixtureId(303)}')),
        );
        await tester.pumpAndSettle();
        expect(h.router.current.name, TagCatalogRoute.name);
        expect(h.router.current.argsAs<TagCatalogRouteArgs>().target, target);
        expect(_tagData(h.raw), before);
        final assign = find.byKey(const ValueKey('tag-catalog-assign'));
        expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
        await tester.tap(assign);
        await tester.pumpAndSettle();
        expect(
          h.raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            tagFixtureId(303),
          ]),
          hasLength(1),
        );
        expect(tester.widget<FilledButton>(assign).onPressed, isNull);
        expect(h.router.current.name, TagCatalogRoute.name);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

Finder _open(int number) =>
    find.byKey(ValueKey('tag-catalog-open-${tagFixtureId(number)}'));

Finder _scope(TaggedEntitiesScope scope) => find.byKey(ValueKey(scope));

Map<String, List<List<Object?>>> _tagData(sqlite.Database raw) => {
  for (final table in ['tags', 'tag_assignments'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

Future<({AppRouter router, sqlite.Database raw, ProviderContainer container})>
_pumpCatalog(
  WidgetTester tester, {
  String locale = 'ru',
  TagTarget? target,
  void Function(sqlite.Database)? seed,
  double textScale = 1,
  Size size = const Size(1000, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late sqlite.Database raw;
  final database = AppDatabase(
    openInMemoryLocalDatabase(setup: (db) => raw = db),
  );
  await database.open();
  seedTagStorageFixture(raw);
  for (final (number, name) in [(303, 'Свободный'), (304, 'Только в архиве')]) {
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(number),
      name,
    ]);
  }
  raw.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(304), tagFixtureId(2)],
  );
  seed?.call(raw);
  final repository = DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => DateTime.utc(2026, 9, 28),
    InMemoryDiagnosticsSink(),
  );
  final router = AppRouter();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink([TagCatalogRoute(target: target)]),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TagCatalogPage)),
  );
  return (router: router, raw: raw, container: container);
}
