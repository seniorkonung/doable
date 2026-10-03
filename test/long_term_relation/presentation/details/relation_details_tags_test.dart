import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/app_root_pages.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';

LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

void main() {
  for (final (number, locale, usedByDailyPath, type) in [
    for (final type in ['need', 'can'])
      for (final number in [101, 102])
        for (final locale in [const Locale('ru'), const Locale('en')])
          for (final usedByDailyPath in [false, true])
            (number, locale, usedByDailyPath, type),
  ]) {
    testWidgets(
      'связь «${type == 'need' ? 'нужно' : 'можно'}» ${number == 101 ? 'активна' : 'в архиве'}, ${usedByDailyPath ? 'в дневном пути' : 'без пути'}: собственных тегов нет на ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 6000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late sqlite.Database raw;
        final database = AppDatabase(
          openInMemoryLocalDatabase(setup: (db) => raw = db),
        );
        await database.open();
        addTearDown(database.close);
        seedTagStorageFixture(raw);
        if (number == 101) {
          raw.execute('DELETE FROM daily_choices WHERE id = ?', [
            tagFixtureId(201),
          ]);
        }
        raw.execute(
          'UPDATE long_term_relations SET type = ?, description = ? WHERE id = ?',
          [type, 'Описание связи $number', tagFixtureId(number)],
        );
        if (usedByDailyPath) {
          final choiceNumber = number == 101 ? 201 : 203;
          raw.execute(
            'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
            [
              tagFixtureId(choiceNumber),
              tagFixtureId(1),
              tagFixtureId(number == 101 ? 3 : 2),
              '2026-09-26',
              1,
            ],
          );
          raw.execute(
            'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
            [
              tagFixtureId(choiceNumber + 1),
              tagFixtureId(choiceNumber),
              tagFixtureId(number),
            ],
          );
        }
        final graphBefore = _storedGraph(raw);
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
        await openIntentionGraph(tester);
        final tagId = (TagId.decode(
          tagFixtureId(firstTagNumber),
        ) as TagIdDecodingSuccess).id;
        unawaited(router.push(TagNavigationRoute(tagId: tagId)));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey(TaggedIntentionsScope.archived)),
        );
        await tester.pumpAndSettle();
        unawaited(
          router.push(RelationDetailsRoute(relationId: _relationId(number))),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey('relation-details-phrase'))),
        );
        expect(find.byType(TagAssignmentsSection), findsNothing);
        expect(
          find.byKey(const ValueKey('tag-assignments-choose')),
          findsNothing,
        );
        for (final tagNumber in [firstTagNumber, lastTagNumber]) {
          for (final action in ['open', 'remove']) {
            expect(
              find.byKey(
                ValueKey('tag-assignment-$action-${tagFixtureId(tagNumber)}'),
              ),
              findsNothing,
            );
          }
        }
        expect(find.text('Дом'), findsNothing);
        expect(find.text('Работа'), findsNothing);
        expect(
          _textOf(tester, 'relation-details-type'),
          type == 'need'
              ? l10n.relationNeighborhoodTypeNeed
              : l10n.relationNeighborhoodTypeCan,
        );
        expect(_textOf(tester, 'relation-details-priority'), 'P2');
        expect(
          _textOf(tester, 'relation-details-scope'),
          number == 101
              ? l10n.relationNeighborhoodRelationActive
              : l10n.relationNeighborhoodRelationArchived,
        );
        expect(
          _textOf(tester, 'relation-details-description'),
          'Описание связи $number',
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('relation-details-edit-relation')),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(
                  ValueKey(
                    number == 101
                        ? 'relation-details-archive-relation'
                        : 'relation-details-restore-relation',
                  ),
                ),
              )
              .onPressed,
          number == 101 ? isNotNull : isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('relation-details-delete-relation')),
              )
              .onPressed,
          usedByDailyPath ? isNull : isNotNull,
        );

        for (final (role, participantNumber, tagNumber) in [
          ('source', 1, firstTagNumber),
          (
            'related',
            number == 101 ? 3 : 2,
            number == 101 ? lastTagNumber : firstTagNumber,
          ),
        ]) {
          await tester.tap(
            find.byKey(ValueKey('relation-details-$role-participant')),
          );
          await tester.pumpAndSettle();
          expect(router.current.name, IntentionDetailsRoute.name);
          expect(
            router.current
                .argsAs<IntentionDetailsRouteArgs>()
                .intentionId
                .toCanonicalString(),
            tagFixtureId(participantNumber),
          );
          expect(find.byType(TagAssignmentsSection), findsOneWidget);
          expect(
            find.byKey(const ValueKey('tag-assignments-choose')),
            findsOneWidget,
          );
          for (final action in ['open', 'remove']) {
            expect(
              find.byKey(
                ValueKey('tag-assignment-$action-${tagFixtureId(tagNumber)}'),
              ),
              findsOneWidget,
            );
          }
          router.pop();
          await tester.pumpAndSettle();
        }
        expect(router.current.name, RelationDetailsRoute.name);
        expect(find.byType(TagAssignmentsSection), findsNothing);
        expect(_storedGraph(raw), graphBefore);
        expect(tester.takeException(), isNull);
        router.pop();
        await tester.pumpAndSettle();
        expect(router.current.name, TagNavigationRoute.name);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey(TaggedIntentionsScope.archived)),
              )
              .selected,
          isTrue,
        );
      },
    );
  }
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  ...retainedTagFixtureGraph(raw),
  for (final table in ['tags', 'tag_assignments'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};
