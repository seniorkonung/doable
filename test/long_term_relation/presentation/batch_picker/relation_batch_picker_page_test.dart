import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/docked_footer.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
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
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
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

  Future<void> open(
    WidgetTester tester,
    IntentionRelationGroup group, {
    Locale locale = const Locale('ru'),
    bool overIntentionPage = false,
  }) async {
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
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
          builder: (context, child) => GraphOperationPresenter(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (overIntentionPage) {
      unawaited(router.push(IntentionDetailsRoute(intentionId: _id(1))));
      await tester.pumpAndSettle();
    }
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

  /// Удерживает хранилище, чтобы принятая команда не завершалась.
  Completer<void> holdStorage() {
    final gate = Completer<void>();
    unawaited(database.transaction(() => gate.future));
    return gate;
  }

  /// Занимает пару в обход открытого поиска: команда получает отказ записи.
  Future<void> occupyPair(int source, int related) => seedGraph(
    database,
    () => database
        .into(database.longTermRelations)
        .insert(
          LongTermRelationsCompanion.insert(
            id: _uuid(1000 + source * 10 + related),
            sourceIntentionId: _uuid(source),
            relatedIntentionId: _uuid(related),
            type: 'need',
            priority: 4,
            createdAt: 1000,
            updatedAt: 1000,
          ),
        ),
  );

  Future<void> settleCommand(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<List<LongTermRelation>> relations() => (database.select(
    database.longTermRelations,
  )..orderBy([(row) => OrderingTerm.asc(row.creationSequence)])).get();

  final addButton = find.descendant(
    of: find.byType(DockedFooter),
    matching: find.byType(FilledButton),
  );

  testWidgets('кнопка называет число связей, а без отметок недоступна', (
    tester,
  ) async {
    await open(tester, IntentionRelationGroup.neededFor);
    final button = find.widgetWithText(FilledButton, 'Добавить связи');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.text('Плавать'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить 1 связь'), findsOneWidget);
    await tester.tap(find.text('Бегать'));
    await tester.tap(find.text('Высыпаться'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить 3 связи'), findsOneWidget);
    expect(tester.widget<FilledButton>(addButton).onPressed, isNotNull);
  });

  testWidgets('кнопка называет число связей на английском', (tester) async {
    await open(
      tester,
      IntentionRelationGroup.neededFor,
      locale: const Locale('en'),
    );
    expect(find.text('Add relations'), findsOneWidget);
    await tester.tap(find.text('Плавать'));
    await tester.pumpAndSettle();
    expect(find.text('Add 1 relation'), findsOneWidget);
    await tester.tap(find.text('Бегать'));
    await tester.pumpAndSettle();
    expect(find.text('Add 2 relations'), findsOneWidget);
  });

  testWidgets('сообщение приложения стоит над нижней частью поиска', (
    tester,
  ) async {
    await open(tester, IntentionRelationGroup.needs);
    ScaffoldMessenger.of(tester.element(find.byType(IntentionPickerView)))
        .showSnackBar(const SnackBar(content: Text('Сообщение')));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.text('Сообщение')).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byType(DockedFooter)).dy - DoableMetrics.space3,
      ),
    );
  });

  testWidgets(
    'добавление создаёт связи в порядке отметок, включая скрытые фильтром, и '
    'закрывает только свой поиск без подробного просмотра',
    (tester) async {
      await open(
        tester,
        IntentionRelationGroup.neededFor,
        overIntentionPage: true,
      );
      await tester.tap(find.text('Бегать'));
      await tester.tap(find.text('Плавать'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('participant-picker-filter')),
        'Высыпаться',
      );
      await tester.pumpAndSettle();
      expect(find.text('Бегать'), findsNothing);

      await tester.tap(addButton);
      await settleCommand(tester);

      expect(find.byType(RelationBatchPickerPage), findsNothing);
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      expect(router.stackData.last.name, IntentionDetailsRoute.name);
      expect(find.textContaining('Добавлено 2 связи.'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final added = (await tester.runAsync(relations))!.skip(4).toList();
      expect(added.map((row) => row.sourceIntentionId), [_uuid(3), _uuid(2)]);
      for (final relation in added) {
        expect(relation.relatedIntentionId, _uuid(1));
        expect(relation.type, 'need');
        expect(relation.priority, 4);
        expect(relation.description, isNull);
      }
    },
  );

  testWidgets(
    'во время добавления повтор не принимается, кнопка показывает выполнение, '
    'а отметки, стрелки и лист действий не принимают',
    (tester) async {
      await open(tester, IntentionRelationGroup.neededFor);
      await tester.tap(find.text('Плавать'));
      await tester.tap(find.text('Бегать'));
      await tester.pumpAndSettle();
      final gate = holdStorage();

      await tester.tap(addButton);
      await tester.tap(addButton);
      await tester.pump();

      expect(find.text('Добавляем…'), findsOneWidget);
      expect(tester.widget<FilledButton>(addButton).onPressed, isNull);
      await tester.tap(find.text('Высыпаться'));
      await tester.pump();
      expect(find.text('Добавить в "Нужно для" · выбрано 2'), findsOneWidget);
      final row = find.ancestor(
        of: find.text('Высыпаться'),
        matching: intentionPickerRows,
      );
      await tester.tap(intentionPickerArrow(row));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(IntentionDetailsPage), findsNothing);
      await tester.tap(find.text('Добавить в "Нужно для" · выбрано 2'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Снять отметку: Плавать'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Снять отметку: Плавать'), findsOneWidget);

      gate.complete();
      await settleCommand(tester);
      expect(find.byType(RelationBatchPickerPage), findsNothing);
      expect(await tester.runAsync(relations), hasLength(6));
    },
  );

  testWidgets(
    'отказ остаётся на экране поиска с отметками, а изменение отметок и новая '
    'отправка его снимают',
    (tester) async {
      await open(tester, IntentionRelationGroup.neededFor);
      await tester.tap(find.text('Плавать'));
      await tester.tap(find.text('Бегать'));
      await tester.tap(find.text('Высыпаться'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => occupyPair(3, 1));
      const failure =
          'Между некоторыми выбранными намерениями уже есть связь. '
          'Связи не созданы.';

      await tester.tap(addButton);
      await settleCommand(tester);

      expect(find.byType(RelationBatchPickerPage), findsOneWidget);
      expect(find.text(failure), findsOneWidget);
      expect(find.text('Добавить 3 связи'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(Notice)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(DockedFooter)).dy),
      );
      expect(await tester.runAsync(relations), hasLength(5));

      await tester.tap(find.text('Высыпаться'));
      await tester.pumpAndSettle();
      expect(find.byType(Notice), findsNothing);
      await tester.tap(addButton);
      await settleCommand(tester);
      expect(find.text(failure), findsOneWidget);

      final gate = holdStorage();
      await tester.tap(addButton);
      await tester.pump();
      expect(find.byType(Notice), findsNothing);
      gate.complete();
      await settleCommand(tester);
      expect(find.text(failure), findsOneWidget);
    },
  );

  testWidgets('архивирование отмеченного намерения снимает отказ', (
    tester,
  ) async {
    await open(tester, IntentionRelationGroup.neededFor);
    await tester.tap(find.text('Плавать'));
    await tester.tap(find.text('Бегать'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => occupyPair(3, 1));
    await tester.tap(addButton);
    await settleCommand(tester);
    expect(find.byType(Notice), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RelationBatchPickerPage)),
    );
    final accepted =
        container
                .read(graphCommandCoordinatorProvider.notifier)
                .acceptExisting(
                  ArchiveIntention(_id(3)),
                  presentationTitle: 'Бегать',
                )
            as IntentionCommandAccepted;
    await tester.runAsync(() => accepted.future);
    await tester.pumpAndSettle();

    expect(find.byType(Notice), findsNothing);
    expect(find.text('Добавить 1 связь'), findsOneWidget);
  });

  testWidgets('отказ сохраняет отметку на том же одноимённом намерении', (
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
    await tester.runAsync(() => occupyPair(1, 5));

    await tester.tap(addButton);
    await settleCommand(tester);

    expect(find.byType(Notice), findsOneWidget);
    expect(find.text('Добавить 1 связь'), findsOneWidget);
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

  testWidgets('успех после ухода с поиска предъявляется оболочкой один раз', (
    tester,
  ) async {
    await open(
      tester,
      IntentionRelationGroup.neededFor,
      overIntentionPage: true,
    );
    await tester.tap(find.text('Плавать'));
    await tester.pumpAndSettle();
    final gate = holdStorage();
    await tester.tap(addButton);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('participant-picker-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(RelationBatchPickerPage), findsNothing);

    gate.complete();
    await settleCommand(tester);

    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(find.textContaining('Добавлена 1 связь.'), findsOneWidget);
    expect(await tester.runAsync(relations), hasLength(5));
  });

  testWidgets('отказ во время закрытия поиска предъявляется оболочкой', (
    tester,
  ) async {
    await open(
      tester,
      IntentionRelationGroup.neededFor,
      overIntentionPage: true,
    );
    await tester.tap(find.text('Плавать'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => occupyPair(2, 1));
    final gate = holdStorage();
    await tester.tap(addButton);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('participant-picker-cancel')));
    await tester.pump(const Duration(milliseconds: 16));
    gate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byType(Notice), findsNothing);
    await tester.pumpAndSettle();

    expect(find.byType(RelationBatchPickerPage), findsNothing);
    expect(
      find.textContaining(
        'Между некоторыми выбранными намерениями уже есть связь. '
        'Связи не созданы.',
      ),
      findsOneWidget,
    );
  });

  for (final (group, ruGroup, enGroup, ruNote, enNote) in [
    (
      IntentionRelationGroup.needs,
      'Нужно',
      'Needs',
      'оно нужно этому намерению',
      'this intention needs it',
    ),
    (
      IntentionRelationGroup.canUse,
      'Можно использовать',
      'Can use',
      'это намерение может его использовать',
      'this intention can use it',
    ),
    (
      IntentionRelationGroup.neededFor,
      'Нужно для',
      'Needed for',
      'ему нужно это намерение',
      'it needs this intention',
    ),
    (
      IntentionRelationGroup.canBeUsedFor,
      'Можно использовать для',
      'Can be used for',
      'оно может использовать это намерение',
      'it can use this intention',
    ),
  ]) {
    for (final locale in [const Locale('ru'), const Locale('en')]) {
      testWidgets('назначение $group на языке ${locale.languageCode}', (
        tester,
      ) async {
        await open(tester, group, locale: locale);
        final ru = locale.languageCode == 'ru';
        final name = ru ? ruGroup : enGroup;
        final subtitle = ru ? 'Добавить в "$name"' : 'Add to "$name"';
        await tester.tap(find.text(subtitle));
        await tester.pumpAndSettle();
        expect(
          find.text(ru ? 'Новые связи в "$name"' : 'New relations in "$name"'),
          findsOneWidget,
        );
        expect(find.textContaining(ru ? ruNote : enNote), findsOneWidget);
        expect(
          find.textContaining(
            ru
                ? 'Связи получат приоритет P4'
                : 'Relations will have priority P4',
          ),
          findsOneWidget,
        );
        expect(
          find.text(ru ? 'Пока ничего не выбрано' : 'Nothing selected yet'),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets(
    'лист показывает новое название намерения страницы и сохраняет поиск',
    (tester) async {
      await open(tester, IntentionRelationGroup.neededFor);
      await tester.tap(find.text('Плавать'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('participant-picker-filter'));
      await tester.enterText(field, 'Бегать');
      await tester.pumpAndSettle();
      await tester.tap(intentionPickerArrow(intentionPickerRows.first));
      await tester.pumpAndSettle();
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      expect(find.textContaining('Добавить в "Нужно для"'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(IntentionDetailsPage)),
      );
      final accepted =
          container
                  .read(graphCommandCoordinatorProvider.notifier)
                  .acceptExisting(
                    UpdateIntention(
                      id: _id(1),
                      title: 'Бодрость',
                      description: null,
                    ),
                    presentationTitle: 'Здоровье',
                  )
              as IntentionCommandAccepted;
      await tester.runAsync(() => accepted.future);
      await tester.pumpAndSettle();
      await router.maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить в "Нужно для" · выбрано 1'));
      await tester.pumpAndSettle();
      expect(find.text('Бодрость'), findsOneWidget);
      expect(
        find.text('Намерение, со страницы которого вы пришли'),
        findsOneWidget,
      );
      expect(find.byTooltip('Снять отметку: Плавать'), findsOneWidget);
      await tester.tap(find.text('Вернуться к списку'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Бегать'), findsOneWidget);
    },
  );

  testWidgets('лист входящей группы показывает отметки и позволяет их снять', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester, IntentionRelationGroup.neededFor);
    expect(find.text('Добавить в "Нужно для"'), findsOneWidget);
    await tester.tap(find.text('Плавать'));
    await tester.tap(find.text('Бегать'));
    await tester.tap(find.text('Высыпаться'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить в "Нужно для" · выбрано 3'), findsOneWidget);
    await tester.tap(find.text('Добавить в "Нужно для" · выбрано 3'));
    await tester.pumpAndSettle();
    expect(find.text('Новые связи в "Нужно для"'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Плавать').last).dy,
      lessThan(tester.getTopLeft(find.text('Бегать').last).dy),
    );
    expect(
      tester.getTopLeft(find.text('Бегать').last).dy,
      lessThan(tester.getTopLeft(find.text('Здоровье')).dy),
    );
    await tester.tap(find.byTooltip('Снять отметку: Плавать'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Снять отметку: Плавать'), findsNothing);
    await tester.tap(find.text('Вернуться к списку'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить в "Нужно для" · выбрано 2'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Плавать')).flagsCollection.isChecked,
      CheckedState.isFalse,
    );
    semantics.dispose();
  });

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
