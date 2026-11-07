import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/action_seed.dart';
import '../../../support/app_root_pages.dart';
import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

void main() {
  // Активность связи и вход в путь действия не влияют на
  // отсутствие её тегов, а тип меняет только шапку: двух комбинаций хватает на
  // все значения.
  for (final (number, usedByAction, type) in [
    (101, false, 'need'),
    (102, true, 'can'),
  ]) {
    testWidgets(
      'связь «${type == 'need' ? 'нужно' : 'можно'}» ${number == 101 ? 'активна' : 'в архиве'}, ${usedByAction ? 'в пути действия' : 'без пути'}: собственных тегов нет',
      (tester) async {
        final semantics = tester.ensureSemantics();
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
        seedRawGraph(raw, () {
          // Путь действия фикстуры проходит через связь 101.
          if (!usedByAction) {
            raw.execute('DELETE FROM actions WHERE id = ?', [
              tagFixtureId(201),
            ]);
          }
          raw.execute(
            'UPDATE long_term_relations SET type = ?, description = ? WHERE id = ?',
            [type, 'Описание связи $number', tagFixtureId(number)],
          );
          if (usedByAction) {
            seedAction(
              raw,
              id: tagFixtureId(203),
              path: [tagFixtureId(1), tagFixtureId(2)],
              isCompleted: true,
            );
          }
        });
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
        await openIntentionGraph(tester);
        unawaited(
          showRelationDetailsSheet(
            tester.element(find.byType(AppNavigationBar)),
            _relationId(number),
          ),
        );
        await tester.pumpAndSettle();

        final head = find.byType(RelationHead);
        final l10n = AppLocalizations.of(tester.element(head));
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
        // Каталог под панелью показывает теги намерений: проверяется сама панель.
        for (final tag in ['Дом', 'Работа']) {
          expect(
            find.descendant(of: find.byType(Sheet), matching: find.text(tag)),
            findsNothing,
          );
        }
        expect(
          tester.widget<RelationHead>(head).kind,
          type == 'need' ? RelationHeadKind.need : RelationHeadKind.can,
        );
        expect(find.text('Описание связи $number'), findsOneWidget);
        expect(
          find.text(l10n.relationSheetArchivedNote),
          number == 101 ? findsNothing : findsOneWidget,
        );

        for (final (participantNumber, tagNumber) in [
          (1, firstTagNumber),
          (
            number == 101 ? 3 : 2,
            number == 101 ? lastTagNumber : firstTagNumber,
          ),
        ]) {
          await tester.tap(
            find.descendant(
              of: head,
              matching: find.text('Намерение $participantNumber'),
            ),
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
          expect(
            find.byKey(const ValueKey('tag-assignments-choose')),
            findsOneWidget,
          );
          expect(
            find.byKey(
              ValueKey('tag-assignment-remove-${tagFixtureId(tagNumber)}'),
            ),
            findsOneWidget,
          );
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        expect(
          find
              .descendant(of: head, matching: find.text('Намерение 1'))
              .hitTestable(),
          findsOneWidget,
        );
        expect(_storedGraph(raw), graphBefore);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}

Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  ...retainedTagFixtureGraph(raw),
  for (final table in ['tags', 'tag_assignments'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};
