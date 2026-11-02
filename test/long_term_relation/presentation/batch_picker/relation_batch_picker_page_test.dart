import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/picker/intention_picker_test_support.dart';
import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/tag_positions.dart';

String _uuid(int value) =>
    '018f0b5d-6b2e-7c80-8000-${value.toString().padLeft(12, '0')}';
IntentionId _id(int value) =>
    (IntentionId.decode(_uuid(value)) as IntentionIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late AppRouter router;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    await seedGraph(database, () async {
      for (final (id, title) in [
        (1, 'Здоровье'),
        (2, 'Плавать'),
        (3, 'Бегать'),
        (4, 'Высыпаться'),
        (5, 'Гулять'),
      ]) {
        await database
            .into(database.intentions)
            .insert(
              IntentionsCompanion.insert(
                id: _uuid(id),
                title: title,
                createdAt: id,
                updatedAt: id,
              ),
            );
      }
      for (final (id, source, related, type, archived) in [
        (101, 1, 2, 'need', false),
        (102, 1, 3, 'need', true),
        (103, 1, 4, 'can', false),
        (104, 5, 1, 'need', false),
      ]) {
        await database
            .into(database.longTermRelations)
            .insert(
              LongTermRelationsCompanion.insert(
                id: _uuid(id),
                sourceIntentionId: _uuid(source),
                relatedIntentionId: _uuid(related),
                type: type,
                priority: 4,
                isArchived: Value(archived),
                createdAt: id,
                updatedAt: id,
              ),
            );
      }
    });
    router = AppRouter();
  });

  tearDown(() async {
    router.dispose();
    await database.close();
  });

  Future<void> open(WidgetTester tester, IntentionRelationGroup group) async {
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      DateTime.now,
      InMemoryDiagnosticsSink(),
    );
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
    unawaited(
      router.push(
        RelationBatchPickerRoute(
          pageIntentionId: _id(1),
          pageTitle: 'Здоровье',
          group: group,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'реальная занятость показывает причину, свободная строка отмечается и поиск остаётся открыт',
    (tester) async {
      await open(tester, IntentionRelationGroup.needs);
      expect(find.byType(RelationBatchPickerPage), findsOneWidget);
      expect(find.text('Выбор намерений'), findsOneWidget);
      expect(find.text('Здоровье'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CatalogHeader),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );
      expect(find.text('Уже добавлено'), findsOneWidget);
      expect(find.text('Уже добавлено, в архиве'), findsOneWidget);
      expect(find.text('Уже в группе "Можно использовать"'), findsOneWidget);
      await tester.tap(find.text('Плавать'));
      await tester.pumpAndSettle();
      expect(find.byType(RelationBatchPickerPage), findsOneWidget);
      await tester.tap(find.text('Гулять'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Гулять')).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
    },
  );

  testWidgets(
    'входящая группа проверяет обратное направление, стрелка сохраняет поиск',
    (tester) async {
      await open(tester, IntentionRelationGroup.neededFor);
      expect(find.text('Уже добавлено'), findsOneWidget);
      final row = find.ancestor(
        of: find.text('Гулять'),
        matching: intentionPickerRows,
      );
      await tester.tap(intentionPickerArrow(row));
      await tester.pumpAndSettle();
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      await router.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Уже добавлено'), findsOneWidget);
    },
  );

  testWidgets('другая группа запрещает повторить пару того же направления', (
    tester,
  ) async {
    await open(tester, IntentionRelationGroup.canUse);
    expect(find.text('Уже в группе "Нужно"'), findsOneWidget);
    await tester.tap(find.text('Плавать'));
    await tester.pumpAndSettle();
    expect(find.byType(RelationBatchPickerPage), findsOneWidget);
    expect(
      (await database.select(database.longTermRelations).get()),
      hasLength(4),
    );
  });

  testWidgets('архивная связь другого типа называет её группу и архив', (
    tester,
  ) async {
    await seedGraph(database, () async {
      await database
          .into(database.intentions)
          .insert(
            IntentionsCompanion.insert(
              id: _uuid(8),
              title: 'Отдыхать',
              createdAt: 8,
              updatedAt: 8,
            ),
          );
      await database
          .into(database.longTermRelations)
          .insert(
            LongTermRelationsCompanion.insert(
              id: _uuid(105),
              sourceIntentionId: _uuid(1),
              relatedIntentionId: _uuid(8),
              type: 'can',
              priority: 4,
              isArchived: const Value(true),
              createdAt: 105,
              updatedAt: 105,
            ),
          );
    });
    await open(tester, IntentionRelationGroup.needs);
    expect(
      find.text('Уже в группе "Можно использовать", в архиве'),
      findsOneWidget,
    );
  });

  testWidgets(
    'отметка переживает фильтр и возврат со страницы свободного намерения',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, IntentionRelationGroup.needs);
      await tester.tap(find.text('Гулять'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('participant-picker-filter'));
      await tester.enterText(field, 'Плавать');
      await tester.pumpAndSettle();
      expect(find.text('Гулять'), findsNothing);
      await tester.enterText(field, 'Гулять');
      await tester.pumpAndSettle();
      final selectedText = find.descendant(
        of: intentionPickerRows.first,
        matching: find.text('Гулять'),
      );
      expect(
        tester.getSemantics(selectedText).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      await tester.tap(intentionPickerArrow(intentionPickerRows.first));
      await tester.pumpAndSettle();
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      await router.maybePop();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Гулять'), findsOneWidget);
      expect(
        tester.getSemantics(selectedText).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('одноимённые намерения отмечаются независимо по идентификатору', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await seedGraph(
      database,
      () => database
          .into(database.intentions)
          .insert(
            IntentionsCompanion.insert(
              id: _uuid(6),
              title: 'Гулять',
              createdAt: 6,
              updatedAt: 6,
            ),
          ),
    );
    await open(tester, IntentionRelationGroup.needs);
    final first = find.byKey(ValueKey('participant-picker-${_uuid(5)}'));
    final second = find.byKey(ValueKey('participant-picker-${_uuid(6)}'));
    await tester.tap(find.descendant(of: first, matching: find.text('Гулять')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(
            find.descendant(of: first, matching: find.text('Гулять')),
          )
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.descendant(of: second, matching: find.text('Гулять')),
          )
          .flagsCollection
          .isChecked,
      CheckedState.isFalse,
    );
    semantics.dispose();
  });

  testWidgets('возврат со страницы сохраняет положение выдачи и отметку', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await seedGraph(database, () async {
      for (var id = 10; id < 18; id++) {
        await database
            .into(database.intentions)
            .insert(
              IntentionsCompanion.insert(
                id: _uuid(id),
                title: 'Намерение $id',
                createdAt: id,
                updatedAt: id,
              ),
            );
      }
    });
    await open(tester, IntentionRelationGroup.needs);
    final list = find.byKey(
      const PageStorageKey<String>('participant-picker-list'),
    );
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(0));
    final row = intentionPickerRows.first;
    final name = tester.widget<PickerRow>(row).name;
    await tester.tap(find.descendant(of: row, matching: find.text(name)));
    await tester.pumpAndSettle();
    await tester.tap(intentionPickerArrow(row));
    await tester.pumpAndSettle();
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
    expect(
      tester
          .getSemantics(
            find.descendant(
              of: intentionPickerRows.first,
              matching: find.text(name),
            ),
          )
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
    semantics.dispose();
  });

  testWidgets(
    'условия тегов сохраняют активный охват и исключают намерение страницы',
    (tester) async {
      await seedGraph(database, () async {
        await database
            .into(database.intentions)
            .insert(
              IntentionsCompanion.insert(
                id: _uuid(7),
                title: 'Архив',
                isArchived: const Value(true),
                createdAt: 7,
                updatedAt: 7,
              ),
            );
        for (final (number, name) in [(201, 'Здоровье'), (202, 'Спорт')]) {
          await database.customStatement(
            'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
            [_uuid(number), name, tagPositionKey(number)],
          );
        }
        for (final (intention, tag) in [
          (1, 201),
          (4, 201),
          (4, 202),
          (5, 201),
          (7, 201),
        ]) {
          await database.customStatement(
            'INSERT INTO tag_assignments (intention_id, tag_id) VALUES (?, ?)',
            [_uuid(intention), _uuid(tag)],
          );
        }
      });
      await open(tester, IntentionRelationGroup.needs);
      final purpose = tester
          .widget<IntentionPickerView>(find.byType(IntentionPickerView))
          .purpose;
      final model = ProviderScope.containerOf(
        tester.element(find.byType(IntentionPickerView)),
      ).read(intentionTagConditionsViewModelProvider(purpose).notifier);
      TagId tag(int number) =>
          (TagId.decode(_uuid(number)) as TagIdDecodingSuccess).id;
      model.cycle(tag(201));
      model.cycle(tag(202));
      model.cycle(tag(202));
      await tester.pumpAndSettle();
      expect(find.text('Гулять'), findsOneWidget);
      expect(
        find.text('Здоровье'),
        findsOneWidget,
      ); // Тег, а не намерение страницы.
      expect(find.text('Высыпаться'), findsNothing);
      expect(find.text('Архив'), findsNothing);
      expect(
        find.byKey(ValueKey('participant-picker-${_uuid(1)}')),
        findsNothing,
      );
    },
  );
}
