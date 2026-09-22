import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../neighborhood/neighborhood_test_support.dart';
import 'relation_details_test_support.dart';

void main() {
  const revision = TestGraphRevision(1);

  testWidgets('раскрывает полное описание, тип, приоритет и архив связи', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(1);
    final description = 'Полное описание. ${'Подробность. ' * 40}'.trim();

    await _pumpRelationDetails(tester, repository, relationId);
    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            sourceTitle: 'быть здоровым',
            relatedTitle: 'много ходить',
            sourceActiveRelationCount: 3,
            relatedActiveRelationCount: 5,
            relatedArchiveState: IntentionArchiveState.archived,
            priority: RelationPriority.p3,
            scope: RelationScope.archived,
            description: description,
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(find.text('Relation'), findsOneWidget);
    expect(
      find.text('To быть здоровым, you need много ходить'),
      findsOneWidget,
    );
    expect(_textOf(tester, 'relation-details-type'), 'Need');
    expect(_textOf(tester, 'relation-details-priority'), 'P3');
    expect(_textOf(tester, 'relation-details-scope'), 'Archived relation');
    expect(_textOf(tester, 'relation-details-description'), description);
    expect(find.text('Source intention'), findsOneWidget);
    expect(find.text('Related intention'), findsOneWidget);
    expect(find.text('быть здоровым'), findsOneWidget);
    expect(find.text('много ходить'), findsOneWidget);
    expect(find.text('Active relations: 3'), findsOneWidget);
    expect(find.text('Active relations: 5'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
  });

  testWidgets('отсутствие описания показывается отдельной подписью', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(2);

    await _pumpRelationDetails(tester, repository, relationId);
    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            type: LongTermRelationType.can,
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(_textOf(tester, 'relation-details-type'), 'Can');
    expect(_textOf(tester, 'relation-details-description'), 'No description');
  });

  testWidgets('входящий контекст не переворачивает формулировку', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(3);
    final openedFrom = testIntentionId(2);

    await _pumpRelationDetails(tester, repository, relationId);
    repository
        .watchAt(0)
        .emitDetails(
          // Просмотр открыт из входящих связей «много ходить», но исходным
          // участником остаётся «быть здоровым».
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: openedFrom,
            sourceTitle: 'быть здоровым',
            relatedTitle: 'много ходить',
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(
      find.text('To быть здоровым, you need много ходить'),
      findsOneWidget,
    );
    expect(find.text('To много ходить, you need быть здоровым'), findsNothing);
  });

  testWidgets('подтверждённое отсутствие связи отличается от ошибки', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(4);

    await _pumpRelationDetails(tester, repository, relationId);
    expect(_textOf(tester, 'relation-details-status'), 'Loading the relation…');

    repository.watchAt(0).emitMissing(revision: revision);
    await tester.pumpAndSettle();

    expect(
      _textOf(tester, 'relation-details-status'),
      'This relation no longer exists.',
    );
    expect(find.byKey(const ValueKey('relation-details-retry')), findsNothing);
  });

  testWidgets('безопасные отказы различимы, повтор только при устранимом', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(5);

    await _pumpRelationDetails(tester, repository, relationId);
    repository.watchAt(0).fail(const LongTermRelationReadUnexpectedFailure());
    await tester.pumpAndSettle();

    expect(
      _textOf(tester, 'relation-details-status'),
      'The relation couldn’t be loaded because of an unexpected error.',
    );
    expect(find.byKey(const ValueKey('relation-details-retry')), findsNothing);
  });

  testWidgets('устранимая недоступность предлагает повтор чтения', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(6);

    await _pumpRelationDetails(tester, repository, relationId);
    repository.watchAt(0).fail(const LongTermRelationReadUnavailableFailure());
    await tester.pumpAndSettle();

    expect(
      _textOf(tester, 'relation-details-status'),
      'The relation couldn’t be loaded. Try again.',
    );
    await tester.tap(find.byKey(const ValueKey('relation-details-retry')));
    // Индикатор чтения анимируется непрерывно: ждать покоя нельзя.
    await tester.pump();

    expect(repository.relationWatches, hasLength(2));
    expect(_textOf(tester, 'relation-details-status'), 'Loading the relation…');
    repository
        .watchAt(1)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
          ),
          revision: const TestGraphRevision(2),
        );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('relation-details-phrase')),
      findsOneWidget,
    );
  });

  testWidgets('переименование и каскад участника обновляют открытый просмотр', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(7);

    await _pumpRelationDetails(tester, repository, relationId);
    final watch = repository.watchAt(0);
    watch.emitDetails(
      testRelationDetails(
        relationId: relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        relatedTitle: 'прежнее название',
        relatedActiveRelationCount: 2,
      ),
      revision: revision,
    );
    await tester.pumpAndSettle();
    expect(find.text('прежнее название'), findsOneWidget);

    watch.emitDetails(
      testRelationDetails(
        relationId: relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        relatedTitle: 'новое название',
        relatedArchiveState: IntentionArchiveState.archived,
        relatedActiveRelationCount: 0,
        scope: RelationScope.archived,
      ),
      revision: const TestGraphRevision(2),
    );
    await tester.pumpAndSettle();

    expect(find.text('прежнее название'), findsNothing);
    expect(find.text('новое название'), findsOneWidget);
    expect(find.text('Active relations: 0'), findsOneWidget);
    expect(_textOf(tester, 'relation-details-scope'), 'Archived relation');
  });

  testWidgets('русская локализация и увеличенный текст сохраняют данные', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(8);

    await _pumpRelationDetails(
      tester,
      repository,
      relationId,
      locale: const Locale('ru'),
      textScaler: const TextScaler.linear(3),
    );
    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            sourceTitle: 'быть здоровым',
            relatedTitle: 'много ходить',
            description: 'Описание связи.',
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    expect(find.text('Связь'), findsOneWidget);
    expect(
      find.text('Чтобы быть здоровым, нужно много ходить'),
      findsOneWidget,
    );
    expect(_textOf(tester, 'relation-details-type'), 'Нужно');
    expect(_textOf(tester, 'relation-details-scope'), 'Активная связь');
    expect(_textOf(tester, 'relation-details-description'), 'Описание связи.');
    expect(find.text('Исходное намерение'), findsOneWidget);
    expect(find.text('Связанное намерение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('экранный диктор получает назначение перехода к участнику', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(9);

    await _pumpRelationDetails(
      tester,
      repository,
      relationId,
      locale: const Locale('ru'),
    );
    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
            sourceTitle: 'быть здоровым',
            sourceActiveRelationCount: 2,
          ),
          revision: revision,
        );
    await tester.pumpAndSettle();

    final node = tester.getSemantics(
      find.byKey(const ValueKey('relation-details-source-participant')),
    );
    expect(node.label, contains('быть здоровым'));
    expect(node.label, contains('Активных связей: 2'));
    expect(node.hint, contains('Открывает намерение и его собственные связи'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    semantics.dispose();
  });

  testWidgets('повторно открытый просмотр показывает выполняющееся изменение', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(10);

    await _pumpRelationDetails(
      tester,
      repository,
      relationId,
      startUpdateBeforeOpening: true,
    );
    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: testIntentionId(1),
            relatedId: testIntentionId(2),
          ),
          revision: revision,
        );
    await tester.pump();

    expect(
      _textOf(tester, 'relation-details-operation-running'),
      'Saving changes…',
    );
  });

  testWidgets(
    'ошибка согласования оставляет данные и предлагает уместный повтор',
    (tester) async {
      final repository = ControlledRelationDetailsRepository();
      addTearDown(repository.dispose);
      final relationId = testRelationId(11);
      final container = await _pumpRelationDetails(
        tester,
        repository,
        relationId,
      );
      final initial = testRelationDetails(
        relationId: relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        description: 'Прежнее подтверждённое описание',
      );
      repository
          .watchAt(0)
          .emitDetails(initial, revision: const TestGraphRevision(1));
      await tester.pumpAndSettle();

      container
          .read(graphCommandCoordinatorProvider.notifier)
          .acceptRelationUpdate(
            UpdateLongTermRelation(
              relationId: relationId,
              patch: const LongTermRelationPatch(
                priority: LongTermRelationFieldSet(RelationPriority.p1),
              ),
            ),
          );
      repository.completeRelationUpdate(
        0,
        before: initial.relation,
        after: LongTermRelation(
          id: initial.relation.id,
          sourceIntentionId: initial.relation.sourceIntentionId,
          relatedIntentionId: initial.relation.relatedIntentionId,
          type: initial.relation.type,
          priority: RelationPriority.p1,
          scope: initial.relation.scope,
          creationSequence: initial.relation.creationSequence,
        ),
        revision: const TestGraphRevision(5),
      );
      await tester.pump();
      await tester.pump();

      expect(
        _textOf(tester, 'relation-details-description'),
        'Прежнее подтверждённое описание',
      );
      expect(
        _textOf(tester, 'relation-details-refresh-status'),
        'Refreshing relation details…',
      );

      repository
          .watchAt(1)
          .fail(const LongTermRelationReadUnavailableFailure());
      await tester.pumpAndSettle();

      expect(
        _textOf(tester, 'relation-details-description'),
        'Прежнее подтверждённое описание',
      );
      expect(
        _textOf(tester, 'relation-details-refresh-status'),
        'The relation details couldn’t be refreshed. Previously confirmed data is still shown.',
      );
      expect(
        find.byKey(const ValueKey('relation-details-refresh-retry')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('relation-details-refresh-retry')),
      );
      await tester.pump();
      expect(repository.relationWatches, hasLength(3));

      repository
          .watchAt(2)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: testIntentionId(1),
              relatedId: testIntentionId(2),
              priority: RelationPriority.p1,
              description: 'Новое подтверждённое описание',
            ),
            revision: const TestGraphRevision(5),
          );
      await tester.pumpAndSettle();

      expect(
        _textOf(tester, 'relation-details-description'),
        'Новое подтверждённое описание',
      );
      expect(
        find.byKey(const ValueKey('relation-details-refresh-status')),
        findsNothing,
      );
    },
  );

  testWidgets('активная связь архивируется из подробного просмотра', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(12);
    final details = testRelationDetails(
      relationId: relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
    );

    await _pumpRelationDetails(tester, repository, relationId);
    repository
        .watchAt(0)
        .emitDetails(details, revision: const TestGraphRevision(1));
    await tester.pumpAndSettle();

    expect(find.text('Archive relation'), findsOneWidget);
    expect(find.text('Restore relation'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('relation-details-archive-relation')),
    );
    await tester.pump();

    expect(repository.relationCommands.single, isA<ArchiveLongTermRelation>());
    expect(
      find.byKey(const ValueKey('relation-details-operation-running')),
      findsOneWidget,
    );
  });

  testWidgets(
    'архивный участник объясняет препятствие и остаётся отдельным переходом',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledRelationDetailsRepository();
      addTearDown(repository.dispose);
      final relationId = testRelationId(13);

      await _pumpRelationDetails(
        tester,
        repository,
        relationId,
        locale: const Locale('ru'),
        textScaler: const TextScaler.linear(3),
      );
      repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: testIntentionId(1),
              relatedId: testIntentionId(2),
              sourceArchiveState: IntentionArchiveState.archived,
              scope: RelationScope.archived,
            ),
            revision: const TestGraphRevision(1),
          );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Сначала восстановите исходное намерение, затем восстановите эту связь.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('relation-details-open-archived-source-participant'),
        ),
        findsOneWidget,
      );
      final restore = tester.widget<FilledButton>(
        find.byKey(const ValueKey('relation-details-restore-relation')),
      );
      expect(restore.onPressed, isNull);
      expect(tester.takeException(), isNull);

      semantics.dispose();
    },
  );

  testWidgets('отказ восстановления предъявляется инлайн и сохраняет данные', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(14);
    final details = testRelationDetails(
      relationId: relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
      scope: RelationScope.archived,
      description: 'Подтверждённое описание',
    );

    await _pumpRelationDetails(tester, repository, relationId);
    repository
        .watchAt(0)
        .emitDetails(details, revision: const TestGraphRevision(1));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('relation-details-restore-relation')),
    );
    await tester.pump();
    repository.failRelationCommand(
      0,
      LongTermRelationParticipantArchivedFailure(
        role: RelationParticipantRole.related,
        intentionId: details.related.id,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      _textOf(tester, 'relation-details-description'),
      'Подтверждённое описание',
    );
    expect(
      find.text(
        'Restore the related intention before restoring this relation.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('relation-details-open-archived-related-participant'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'удаление конкретной архивной связи требует содержательного подтверждения',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledRelationDetailsRepository();
      addTearDown(repository.dispose);
      final relationId = testRelationId(15);
      final details = testRelationDetails(
        relationId: relationId,
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        sourceTitle: 'быть здоровым',
        relatedTitle: 'много ходить',
        scope: RelationScope.archived,
      );

      await _pumpRelationDetails(
        tester,
        repository,
        relationId,
        locale: const Locale('ru'),
        textScaler: const TextScaler.linear(3),
      );
      repository
          .watchAt(0)
          .emitDetails(details, revision: const TestGraphRevision(1));
      await tester.pumpAndSettle();

      final delete = find.byKey(
        const ValueKey('relation-details-delete-relation'),
      );
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();

      expect(find.text('Удалить связь навсегда?'), findsOneWidget);
      expect(
        find.textContaining('Чтобы быть здоровым, нужно много ходить'),
        findsWidgets,
      );
      expect(
        find.textContaining('Исходное намерение: быть здоровым'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Связанное намерение: много ходить'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Состояние связи: Связь в архиве'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Это действие нельзя отменить'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
      await tester.pumpAndSettle();
      expect(repository.relationCommands, isEmpty);

      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('relation-details-confirm-delete')),
      );
      await tester.pump();

      expect(repository.relationCommands.single, isA<DeleteLongTermRelation>());
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('отказ удаления сохраняет данные и предлагает уместный повтор', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(16);
    final details = testRelationDetails(
      relationId: relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
      description: 'Подтверждённое описание',
    );

    await _pumpRelationDetails(tester, repository, relationId);
    repository
        .watchAt(0)
        .emitDetails(details, revision: const TestGraphRevision(1));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('relation-details-delete-relation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('relation-details-confirm-delete')),
    );
    await tester.pump();
    repository.failRelationCommand(
      0,
      const LongTermRelationUnavailableFailure(),
    );
    await tester.pump();
    await tester.pump();

    expect(
      _textOf(tester, 'relation-details-description'),
      'Подтверждённое описание',
    );
    expect(
      find.text('The relation couldn’t be deleted. Try again.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('relation-details-lifecycle-retry')),
      findsOneWidget,
    );
  });

  testWidgets('успешное удаление закрывает просмотр до позднего снимка', (
    tester,
  ) async {
    final repository = ControlledRelationDetailsRepository();
    addTearDown(repository.dispose);
    final relationId = testRelationId(17);
    final details = testRelationDetails(
      relationId: relationId,
      sourceId: testIntentionId(1),
      relatedId: testIntentionId(2),
    );
    final container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const ValueKey('open-relation-details'),
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RelationDetailsPage(relationId: relationId),
                    ),
                  ),
                ),
                child: const Text('Открыть связь'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-relation-details')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final watch = repository.watchAt(0);
    watch.emitDetails(details, revision: const TestGraphRevision(1));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('relation-details-delete-relation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('relation-details-confirm-delete')),
    );
    await tester.pump();
    repository.completeRelationDelete(
      0,
      relation: details.relation,
      revision: const TestGraphRevision(2),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-relation-details')), findsOneWidget);
    expect(find.byKey(const ValueKey('relation-details-phrase')), findsNothing);

    watch.emitDetails(details, revision: const TestGraphRevision(3));
    await tester.pump();
    expect(find.byKey(const ValueKey('relation-details-phrase')), findsNothing);
  });
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Future<ProviderContainer> _pumpRelationDetails(
  WidgetTester tester,
  ControlledRelationDetailsRepository repository,
  LongTermRelationId relationId, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  bool startUpdateBeforeOpening = false,
}) async {
  // Просмотр проверяется целиком: высокая поверхность исключает влияние
  // прокрутки на поиск данных и переходов.
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  if (startUpdateBeforeOpening) {
    container
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptRelationUpdate(
          UpdateLongTermRelation(
            relationId: relationId,
            patch: const LongTermRelationPatch(
              priority: LongTermRelationFieldSet(RelationPriority.p1),
            ),
          ),
        );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: RelationDetailsPage(relationId: relationId),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}
