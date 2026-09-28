import 'dart:async';

import 'package:auto_route/auto_route.dart';
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
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
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
import '../../../support/tag_storage_fixture.dart';

final _modes = <(String, TagTarget?)>[
  ('каталог', null),
  (
    'выбор для намерения',
    IntentionTagTarget(
      (IntentionId.decode(_id(1)) as IntentionIdDecodingSuccess).id,
    ),
  ),
  (
    'выбор для связи «нужно»',
    LongTermRelationTagTarget(
      (LongTermRelationId.decode(
        _id(101),
      ) as LongTermRelationIdDecodingSuccess).id,
    ),
  ),
  (
    'выбор для связи «можно»',
    LongTermRelationTagTarget(
      (LongTermRelationId.decode(
        _id(103),
      ) as LongTermRelationIdDecodingSuccess).id,
    ),
  ),
];

final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _list = find.byKey(const ValueKey('tag-catalog-list'));

void main() {
  for (final (description, target) in _modes) {
    testWidgets(
      '$description: текущий ввод сразу фильтрует пары в прежнем порядке, очистка возвращает снимок',
      (tester) async {
        final repository = await _pumpCatalog(tester, target: target);
        final tags = [
          _tag(1, 'Работа'),
          _tag(2, 'Дом'),
          _tag(3, 'Для дома'),
          _tag(4, 'Домашнее'),
        ];
        repository.complete(tags);
        await tester.pumpAndSettle();

        await tester.enterText(_search, 'ДОМ');
        await tester.pump();
        expect(_visibleNames(tester), ['Дом', 'Для дома', 'Домашнее']);
        if (target != null) {
          expect(_assignment(tester, tags[1]), 'Назначен');
          expect(_assignment(tester, tags[2]), 'Доступен для назначения');
          expect(_assignment(tester, tags[3]), 'Назначен');
        }

        await tester.enterText(_search, 'работ');
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.text, 'работ');
        expect(_visibleNames(tester), ['Работа']);
        if (target != null) {
          expect(_assignment(tester, tags[0]), 'Доступен для назначения');
        }

        await tester.tap(find.byTooltip('Очистить поиск тегов'));
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
        expect(_visibleNames(tester), tags.map((tag) => tag.name.value));
        final state = _loaded(tester, target);
        expect(state.items, tags);
        if (target != null) {
          expect(state.selectionRows.map((row) => row.isAssigned), [
            false,
            true,
            false,
            true,
          ]);
        }
      },
    );

    testWidgets('$description: поиск находит тег вне видимой области', (
      tester,
    ) async {
      final repository = await _pumpCatalog(tester, target: target);
      repository.complete([
        for (var index = 1; index <= 132; index++) _tag(index, 'Тег $index'),
        _tag(133, 'Straße'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Straße'), findsNothing);

      await tester.enterText(_search, 'STRASS');
      await tester.pump();

      expect(_visibleNames(tester), ['Straße']);
      expect(_loaded(tester, target).items, hasLength(133));
    });

    for (final language in ['ru', 'en']) {
      testWidgets(
        '$description: пустой каталог и отсутствие совпадений различаются на $language',
        (tester) async {
          final repository = await _pumpCatalog(
            tester,
            target: target,
            language: language,
          );
          final l10n = _localizations(tester);
          repository.complete([]);
          await tester.pumpAndSettle();
          expect(find.text(l10n.tagCatalogEmpty), findsOneWidget);
          expect(find.text(l10n.tagCatalogSearch), findsOneWidget);

          await tester.enterText(_search, 'спорт');
          await tester.pump();

          expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
          expect(find.text(l10n.tagCatalogEmpty), findsNothing);
          expect(tester.widget<TextField>(_search).controller!.text, 'спорт');
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('tag-catalog-create')),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
          await tester.pump();
          expect(find.text(l10n.tagCatalogEmpty), findsOneWidget);
          expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        },
      );

      testWidgets(
        '$description: некорректный ввод сохраняется с последним корректным фильтром на $language',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final repository = await _pumpCatalog(
              tester,
              target: target,
              language: language,
            );
            final l10n = _localizations(tester);
            final tags = [
              _tag(1, 'Работа'),
              _tag(2, 'Дом'),
              _tag(3, 'Для дома'),
            ];
            repository.complete(tags);
            await tester.pumpAndSettle();

            await tester.enterText(_search, '\u0000');
            await tester.pump();
            expect(_visibleNames(tester), ['Работа', 'Дом', 'Для дома']);
            expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
            expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);

            await tester.enterText(_search, 'дом');
            await tester.pump();
            for (final input in ['спорт\u0000', '\ud800', '\udc00']) {
              await tester.enterText(_search, input);
              await tester.pump();

              expect(tester.widget<TextField>(_search).controller!.text, input);
              expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
              expect(_visibleNames(tester), ['Дом', 'Для дома']);
              expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
              if (target != null) {
                expect(_assignment(tester, tags[1]), l10n.tagCatalogAssigned);
                expect(_assignment(tester, tags[2]), l10n.tagCatalogAvailable);
              }
            }

            await tester.enterText(_search, 'работ');
            await tester.pump();
            expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
            expect(_visibleNames(tester), ['Работа']);

            await tester.enterText(_search, '\u0000');
            await tester.pump();
            await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
            await tester.pump();
            expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
            expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
            expect(_visibleNames(tester), ['Работа', 'Дом', 'Для дома']);

            await tester.enterText(_search, 'спорт');
            await tester.pump();
            await tester.enterText(_search, '\u0000');
            await tester.pump();
            expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
            expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
            expect(_visibleNames(tester), isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$description: загрузка и отказ первоначального чтения имеют приоритет перед отсутствием совпадений',
      (tester) async {
        final repository = await _pumpCatalog(tester, target: target);
        final l10n = _localizations(tester);
        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(find.text(l10n.tagCatalogLoading), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);

        repository.reads.last.complete(
          const TagCatalogError(TagCatalogUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        expect(tester.widget<TextField>(_search).controller!.text, 'спорт');

        await tester.tap(find.text(l10n.commonRetry));
        await tester.pump();
        expect(find.text(l10n.tagCatalogLoading), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        repository.complete([_tag(1, 'Дом')]);
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
      },
    );

    testWidgets(
      '$description: при отказе обновления поиск сохраняет неактуальные строки и ограничения действий',
      (tester) async {
        final repository = await _pumpCatalog(tester, target: target);
        final l10n = _localizations(tester);
        repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')]);
        await tester.pumpAndSettle();
        await tester.enterText(_search, 'дом');
        await tester.pump();
        await _beginRefresh(tester, repository);
        expect(find.text(l10n.tagCatalogRefreshing), findsOneWidget);
        expect(_visibleNames(tester), ['Дом']);

        repository.reads.last.complete(
          const TagCatalogError(TagCatalogUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
        expect(_visibleNames(tester), ['Дом']);
        final tile = tester.widget<ListTile>(
          find.descendant(of: _list, matching: find.byType(ListTile)),
        );
        expect(tile.onTap, isNull);
        expect(tile.trailing, isNull);
        if (target != null) {
          expect(_assignment(tester, _tag(2, 'Дом')), l10n.tagCatalogAssigned);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('tag-catalog-assign')),
                )
                .onPressed,
            isNull,
          );
        }

        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(_visibleNames(tester), isEmpty);
        expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        await tester.tap(find.text(l10n.commonRetry));
        await tester.pump();
        expect(find.text(l10n.tagCatalogRefreshing), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        repository.complete([_tag(1, 'Рабочее'), _tag(2, 'Дом')], revision: 2);
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
        expect(tester.widget<TextField>(_search).controller!.text, 'спорт');
      },
    );

    testWidgets(
      '$description: реальный каталог включает неиспользуемые теги и назначения только в архиве, создание доступно из пустого результата',
      (tester) async {
        final router = await _pumpStoredCatalog(tester, target: target);
        await tester.enterText(_search, 'дом');
        await tester.pump();
        expect(_visibleNames(tester), [
          'Дом 🏷️',
          'Дом без назначений',
          'Дом в архиве',
        ]);
        if (target != null) {
          expect(_assignment(tester, _tag(301, 'Дом 🏷️')), 'Назначен');
          expect(
            _assignment(tester, _tag(303, 'Дом без назначений')),
            'Доступен для назначения',
          );
          expect(
            _assignment(tester, _tag(304, 'Дом в архиве')),
            'Доступен для назначения',
          );
        }

        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(find.text('Теги не найдены'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        expect(router.current.name, TagEditorRoute.name);
        expect(find.byKey(const ValueKey('tag-editor-name')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$description: ввод с emoji сохраняет область набора и исправляется после непарного surrogate',
      (tester) async {
        final repository = await _pumpCatalog(tester, target: target);
        repository.complete([_tag(1, 'Дом 😀'), _tag(2, 'Работа')]);
        await tester.pumpAndSettle();
        await tester.showKeyboard(_search);
        const input = TextEditingValue(
          text: 'ДОМ 😀',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 4, end: 6),
        );
        tester.testTextInput.updateEditingValue(input);
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.value, input);
        expect(_visibleNames(tester), ['Дом 😀']);

        final invalid = input.copyWith(
          text: 'ДОМ 😀\ud800',
          selection: const TextSelection.collapsed(offset: 7),
          composing: const TextRange(start: 4, end: 7),
        );
        tester.testTextInput.updateEditingValue(invalid);
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.value, invalid);
        expect(_visibleNames(tester), ['Дом 😀']);
        expect(
          find.text(_localizations(tester).tagCatalogInvalidSearch),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        tester.testTextInput.updateEditingValue(input);
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.value, input);
        expect(
          find.text(_localizations(tester).tagCatalogInvalidSearch),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

AppLocalizations _localizations(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TagCatalogPage)));

Future<void> _beginRefresh(
  WidgetTester tester,
  _CatalogRepository repository,
) async {
  final before = _tag(1, 'Работа');
  final after = _tag(1, 'Рабочее');
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TagCatalogPage)),
  );
  final accepted =
      container
              .read(graphCommandCoordinatorProvider.notifier)
              .acceptTagRename(RenameTag(tagId: before.id, name: after.name))
          as TagCommandAccepted;
  repository.command.complete(
    TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: const _Revision(2),
        value: TagRenamed(
          TagRenamedChange(
            revision: const _Revision(2),
            before: before,
            after: after,
          ),
        ),
      ),
    ),
  );
  await accepted.future;
  await tester.pump();
}

Future<AppRouter> _pumpStoredCatalog(
  WidgetTester tester, {
  TagTarget? target,
}) async {
  late sqlite.Database raw;
  final database = AppDatabase(
    openInMemoryLocalDatabase(setup: (db) => raw = db),
  );
  await database.open();
  seedTagNavigationFixture(raw, extraPairsPerScope: 0);
  for (final (number, name) in [
    (303, 'Дом без назначений'),
    (304, 'Дом в архиве'),
  ]) {
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', [name, _id(number)]);
  }
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
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink([TagCatalogRoute(target: target)]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<_CatalogRepository> _pumpCatalog(
  WidgetTester tester, {
  TagTarget? target,
  String language = 'ru',
}) async {
  final repository = _CatalogRepository(target);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TagCatalogPage(target: target),
      ),
    ),
  );
  return repository;
}

List<String> _visibleNames(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(of: _list, matching: find.byType(ListTile)),
  ))
    (tile.title! as Text).data!,
];

String _assignment(WidgetTester tester, Tag tag) =>
    (tester
                .widget<ListTile>(
                  find.descendant(
                    of: find.byKey(
                      ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'),
                    ),
                    matching: find.byType(ListTile),
                  ),
                )
                .subtitle!
            as Text)
        .data!;

TagCatalogLoaded _loaded(WidgetTester tester, TagTarget? target) =>
    ProviderScope.containerOf(tester.element(find.byType(TagCatalogPage))).read(
      tagCatalogViewModelProvider(
        mode: target == null
            ? const TagCatalogBrowseMode()
            : TagCatalogSelectionMode(target),
      ),
    ) as TagCatalogLoaded;

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

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
  _CatalogRepository(this.target);

  final TagTarget? target;
  final reads = <Completer<TagCatalogResult>>[];
  final command = Completer<TagCommandResult>();

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async =>
      await this.command.future as GraphCommandResult<TSuccess, TFailure>;

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) {
    final read = Completer<TagCatalogResult>();
    reads.add(read);
    return read.future;
  }

  void complete(List<Tag> tags, {int revision = 1}) => reads.last.complete(
    TagCatalogSuccess(switch (target) {
      null => TagCatalogSnapshot(items: tags, revision: _Revision(revision)),
      final target => TagCatalogSnapshot.selection(
        target: target,
        rows: [
          for (var index = 0; index < tags.length; index++)
            TagSelectionRow(tag: tags[index], isAssigned: index.isOdd),
        ],
        revision: _Revision(revision),
      ),
    }),
  );
}
