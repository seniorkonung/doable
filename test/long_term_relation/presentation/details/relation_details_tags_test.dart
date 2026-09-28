import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';

LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

void main() {
  for (final (number, locale, usedByDailyPath) in [
    (101, const Locale('ru'), true),
    (102, const Locale('en'), true),
    (102, const Locale('ru'), false),
    (102, const Locale('en'), false),
  ]) {
    testWidgets(
      'подробности связи $number ${usedByDailyPath ? 'в дневном пути' : 'без пути'} независимо управляют назначениями на ${locale.languageCode}',
      (tester) async {
        late sqlite.Database raw;
        final database = AppDatabase(
          openInMemoryLocalDatabase(setup: (db) => raw = db),
        );
        await database.open();
        addTearDown(database.close);
        seedTagStorageFixture(raw);
        raw.execute(
          'UPDATE long_term_relations SET description = ? WHERE id = ?',
          ['Описание связи $number', tagFixtureId(number)],
        );
        if (number == 102) {
          raw.execute('UPDATE long_term_relations SET type = ? WHERE id = ?', [
            'can',
            tagFixtureId(102),
          ]);
          if (usedByDailyPath) {
            raw.execute(
              'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
              [
                tagFixtureId(203),
                tagFixtureId(1),
                tagFixtureId(2),
                '2026-09-26',
                1,
              ],
            );
            raw.execute(
              'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
              [tagFixtureId(204), tagFixtureId(203), tagFixtureId(102)],
            );
          }
        }
        final graphBefore = retainedTagFixtureGraph(raw);
        final assignmentsBefore = raw
            .select('SELECT * FROM tag_assignments ORDER BY creation_sequence')
            .map((row) => row.values.toList())
            .toList();
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
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router.config(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tagId = (TagId.decode(
          tagFixtureId(firstTagNumber),
        ) as TagIdDecodingSuccess).id;
        unawaited(router.push(TagNavigationRoute(tagId: tagId)));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey(TaggedEntitiesScope.archived)),
        );
        await tester.pumpAndSettle();
        unawaited(
          router.push(RelationDetailsRoute(relationId: _relationId(number))),
        );
        await tester.pumpAndSettle();

        final choose = find.byKey(const ValueKey('tag-assignments-choose'));
        await tester.scrollUntilVisible(
          choose,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(choose, findsOneWidget);
        expect(find.text('Дом'), findsOneWidget);
        final open = find.byKey(
          ValueKey('tag-assignment-open-${tagFixtureId(firstTagNumber)}'),
        );
        expect(open, findsOneWidget);
        await Scrollable.ensureVisible(tester.element(open), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(router.current.name, TagNavigationRoute.name);
        expect(
          router.current
              .argsAs<TagNavigationRouteArgs>()
              .tagId
              .toCanonicalString(),
          tagFixtureId(firstTagNumber),
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey(TaggedEntitiesScope.active)),
              )
              .selected,
          isTrue,
        );
        expect(retainedTagFixtureGraph(raw), graphBefore);
        expect(
          raw
              .select(
                'SELECT * FROM tag_assignments ORDER BY creation_sequence',
              )
              .map((row) => row.values.toList())
              .toList(),
          assignmentsBefore,
        );
        router.pop();
        await tester.pumpAndSettle();
        expect(router.current.name, RelationDetailsRoute.name);
        await Scrollable.ensureVisible(tester.element(choose), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(choose);
        await tester.pumpAndSettle();
        expect(router.current.name, TagCatalogRoute.name);
        expect(
          router.current.argsAs<TagCatalogRouteArgs>().target,
          LongTermRelationTagTarget(_relationId(number)),
        );

        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('tag-editor-name')),
          'Новый тег $number',
        );
        await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
        await _waitUntil(
          tester,
          () =>
              find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty,
        );
        final newTagId =
            raw.select('SELECT id FROM tags WHERE name = ?', [
                  'Новый тег $number',
                ]).single['id']
                as String;
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            newTagId,
          ]),
          isEmpty,
        );

        await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
        await _waitUntil(
          tester,
          () => raw.select(
            'SELECT * FROM tag_assignments WHERE tag_id = ? AND long_term_relation_id = ?',
            [newTagId, tagFixtureId(number)],
          ).isNotEmpty,
        );
        router.pop();
        await tester.pumpAndSettle();
        final remove = find.byKey(ValueKey('tag-assignment-remove-$newTagId'));
        await Scrollable.ensureVisible(tester.element(remove), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(remove);
        await _waitUntil(
          tester,
          () => raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            newTagId,
          ]).isEmpty,
        );
        expect(
          raw.select('SELECT * FROM tags WHERE id = ?', [newTagId]),
          hasLength(1),
        );
        expect(
          raw.select(
            'SELECT * FROM tag_assignments WHERE intention_id IS NOT NULL',
          ),
          hasLength(3),
        );
        expect(
          raw.select(
            'SELECT * FROM tag_assignments WHERE long_term_relation_id = ?',
            [tagFixtureId(number == 101 ? 102 : 101)],
          ),
          hasLength(1),
        );
        expect(
          raw.select(
            'SELECT * FROM tag_assignments WHERE long_term_relation_id = ?',
            [tagFixtureId(number)],
          ),
          hasLength(1),
        );
        expect(retainedTagFixtureGraph(raw), graphBefore);

        if (number == 102 && !usedByDailyPath) {
          final delete = find.byKey(
            const ValueKey('relation-details-delete-relation'),
          );
          await tester.scrollUntilVisible(
            delete,
            -200,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
          await tester.tap(delete);
          await tester.pumpAndSettle();
          expect(
            find.textContaining(
              locale.languageCode == 'ru'
                  ? 'Все назначения тегов этой связи'
                  : 'All tag assignments of this relation',
            ),
            findsOneWidget,
          );
          await tester.tap(
            find.widgetWithText(
              TextButton,
              locale.languageCode == 'ru' ? 'Отмена' : 'Cancel',
            ),
          );
          await tester.pumpAndSettle();
          expect(retainedTagFixtureGraph(raw), graphBefore);
        }
        router.pop();
        await tester.pumpAndSettle();
        expect(router.current.name, TagNavigationRoute.name);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey(TaggedEntitiesScope.archived)),
              )
              .selected,
          isTrue,
        );
      },
    );
  }
}

Future<void> _waitUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 30 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
  expect(done(), isTrue);
}
