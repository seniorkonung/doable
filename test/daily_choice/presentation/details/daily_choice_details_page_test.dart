import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart'
    as application;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'редактор открывается из подробностей и меняет только выбранные поля',
    (tester) async {
      final repository = _Repository();
      final router = AppRouter();
      addTearDown(() async {
        router.dispose();
        await repository.dispose();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: MaterialApp.router(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
          ),
        ),
      );
      unawaited(router.push(DailyChoiceDetailsRoute(choiceId: _choice(1))));
      await tester.pump();
      repository.emit(_details());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('daily-choice-edit-open')));
      await tester.pumpAndSettle();
      expect(router.current.name, DailyChoiceEditRoute.name);
      expect(find.textContaining('Основа'), findsWidgets);
      expect(find.text('2026-09-24'), findsOneWidget);
      expect(find.text('Пояснение'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-edit-date')),
        '0001-01-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-edit-description')),
        ' \n ',
      );
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-edit-completed')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-edit-submit')),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('daily-choice-edit-submit')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-edit-submit')));
      await tester.pump();
      expect(repository.updateCommands, hasLength(1));
      final command = repository.updateCommands.single;
      expect(command.choiceId, _choice(1));
      expect(
        (command.patch.date as DailyChoiceFieldSet<CalendarDate>).value,
        CalendarDate.fromParts(1, 1, 1),
      );
      expect(command.patch.description, isA<DailyChoiceDescriptionCleared>());
      expect(
        (command.patch.isCompleted as DailyChoiceFieldSet<bool>).value,
        isFalse,
      );
      repository.succeedUpdate();
      await tester.pumpAndSettle();
      expect(router.current.name, DailyChoiceDetailsRoute.name);
    },
  );

  testWidgets('отмена и неверный ввод не отправляют правку', (tester) async {
    final repository = _Repository();
    final router = AppRouter();
    addTearDown(() async {
      router.dispose();
      await repository.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    unawaited(router.push(DailyChoiceDetailsRoute(choiceId: _choice(1))));
    await tester.pump();
    repository.emit(_details());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daily-choice-edit-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-edit-date')),
      '9999-02-30',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-edit-submit')),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('daily-choice-edit-submit')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-edit-submit')));
    await tester.pump();
    expect(repository.updateCommands, isEmpty);
    expect(find.text('9999-02-30'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('daily-choice-edit-date')),
          )
          .decoration
          ?.errorText,
      'Check the daily choice date.',
    );

    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-edit-date')),
      '9999-12-31',
    );
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-edit-description')),
      'е\u0301' * 4097,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-edit-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-edit-submit')));
    await tester.pump();
    expect(repository.updateCommands, isEmpty);
    expect(find.text('е\u0301' * 4097), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('daily-choice-edit-cancel')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(DailyChoiceEditPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-edit-cancel')));
    await tester.pumpAndSettle();
    expect(router.current.name, DailyChoiceDetailsRoute.name);
    expect(repository.updateCommands, isEmpty);
  });

  testWidgets(
    'каждый участник и связь открываются по сохранённому идентификатору',
    (tester) async {
      final repository = _Repository();
      final router = AppRouter();
      addTearDown(() async {
        router.dispose();
        await repository.dispose();
      });
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWith((ref) => repository),
          ],
          retry: (count, error) => null,
          child: MaterialApp.router(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
          ),
        ),
      );
      unawaited(router.push(DailyChoiceDetailsRoute(choiceId: _choice(1))));
      await tester.pump();
      repository.emit(_details());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('daily-choice-relation-2')));
      await tester.pump();
      expect(router.current.name, RelationDetailsRoute.name);
      expect(
        router.current.argsAs<RelationDetailsRouteArgs>().relationId,
        _relationId(2),
      );
      unawaited(router.maybePop());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('daily-choice-intention-2')));
      await tester.pump();
      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        _intentionId(2),
      );
    },
  );

  testWidgets('показывает порядок и типы всего пути с архивными состояниями', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_app(repository, const Locale('ru')));
    repository.emit(_details());
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-09-24'), findsOneWidget);
    expect(find.text('Выполнено'), findsOneWidget);
    expect(find.textContaining('Основание'), findsOneWidget);
    expect(find.textContaining('Нужно'), findsWidgets);
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daily-choice-intention-1')))
          .label,
      contains('Основание'),
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daily-choice-relation-1')))
          .label,
      contains('Нужно'),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('daily-choice-intention-3')),
      250,
    );
    expect(find.textContaining('Выбранное действие'), findsOneWidget);
    expect(find.textContaining('Можно'), findsWidgets);
    expect(find.textContaining('Архивировано'), findsWidgets);
    expect(find.textContaining('Не готово к действию'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daily-choice-intention-3')))
          .label,
      contains('Выбранное действие'),
    );
    semantics.dispose();
  });

  testWidgets('одношаговый путь оставляет тип связи и отметку действия', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_app(repository, const Locale('ru')));
    repository.emit(_details(oneStep: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нужно'), findsWidgets);
    expect(find.textContaining('Промежуточное намерение'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('daily-choice-intention-2')),
      250,
    );
    expect(find.textContaining('Выбранное действие'), findsOneWidget);
  });

  testWidgets('после переименования показывает текущий снимок на английском', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_app(repository, const Locale('en')));
    repository.emit(_details());
    await tester.pumpAndSettle();
    repository.emit(
      _details(
        middleTitle: 'Renamed middle',
        relationDescription: 'Changed explanation',
        relationPriority: RelationPriority.p3,
        isCompleted: false,
        choiceDescription: 'Updated note',
      ),
      revision: 2,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Renamed middle'), findsWidgets);
    expect(find.text('Not completed'), findsOneWidget);
    expect(find.text('Updated note'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('daily-choice-intention-3')),
      250,
    );
    expect(find.textContaining('Changed explanation'), findsWidgets);
    expect(find.textContaining('P3'), findsWidgets);
    expect(find.textContaining('Selected action'), findsOneWidget);
    expect(find.textContaining('Archived'), findsWidgets);
  });

  testWidgets('удаление и повреждение убирают путь целиком', (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_app(repository, const Locale('ru')));
    repository.emit(_details());
    await tester.pumpAndSettle();
    expect(find.textContaining('Основание'), findsOneWidget);

    repository.emitMissing(revision: 2);
    await tester.pumpAndSettle();
    expect(find.text('Дневной выбор больше не существует.'), findsOneWidget);
    expect(find.textContaining('Основание'), findsNothing);

    repository.fail(const DailyChoiceReadCorruptionFailure());
    await tester.pumpAndSettle();
    expect(
      find.text('Сохранённый путь повреждён и не может быть показан.'),
      findsOneWidget,
    );
    expect(find.textContaining('Основание'), findsNothing);
  });
}

Widget _app(_Repository repository, Locale locale) => ProviderScope(
  overrides: [
    personalGraphRepositoryProvider.overrideWith((ref) => repository),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
      child: DailyChoiceDetailsPage(choiceId: _choice(1)),
    ),
  ),
);

String _uuid(int n) =>
    '018f0b5d-6b2e-7c80-8000-${n.toRadixString(16).padLeft(12, '0')}';
DailyChoiceId _choice(int n) =>
    (DailyChoiceId.decode(_uuid(n)) as DailyChoiceIdDecodingSuccess).id;
IntentionId _intentionId(int n) =>
    (IntentionId.decode(_uuid(n)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relationId(int n) => (LongTermRelationId.decode(
  _uuid(n),
) as LongTermRelationIdDecodingSuccess).id;
ChoicePathStepId _stepId(int n) =>
    (ChoicePathStepId.decode(_uuid(n)) as ChoicePathStepIdDecodingSuccess).id;

Intention _intention(
  int n,
  String title, {
  bool archived = false,
  bool ready = false,
}) => Intention(
  id: _intentionId(n),
  title: title,
  description: null,
  readiness: ready ? IntentionReadiness.ready : IntentionReadiness.notReady,
  archiveState: archived
      ? IntentionArchiveState.archived
      : IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

DailyChoiceDetails _details({
  String middleTitle = 'Середина',
  bool oneStep = false,
  String? relationDescription,
  RelationPriority relationPriority = RelationPriority.p2,
  bool isCompleted = true,
  String choiceDescription = 'Пояснение',
}) {
  final source = _intention(1, 'Основа', archived: true);
  final middle = _intention(2, middleTitle);
  final selected = _intention(3, 'Действие');
  final choice = DailyChoice(
    id: _choice(1),
    sourceIntentionId: source.id,
    selectedIntentionId: selected.id,
    date: CalendarDate.fromParts(2026, 9, 24),
    description: DailyChoiceDescription.fromInput(choiceDescription),
    isCompleted: isCompleted,
  );
  DailyChoicePathStepDetails step(
    int n,
    Intention from,
    Intention to,
    LongTermRelationType type,
    RelationScope scope,
    ChoicePathStepId? previous,
  ) => DailyChoicePathStepDetails(
    step: ChoicePathStep(
      id: _stepId(n),
      dailyChoiceId: choice.id,
      relationId: _relationId(n),
      previousStepId: previous,
    ),
    relation: LongTermRelation(
      id: _relationId(n),
      sourceIntentionId: from.id,
      relatedIntentionId: to.id,
      type: type,
      priority: relationPriority,
      scope: scope,
      creationSequence: RelationCreationSequence(n),
    ),
    description: relationDescription == null
        ? null
        : LongTermRelationDescription.fromInput(relationDescription),
    source: from,
    related: to,
  );
  return DailyChoiceDetails(
    choice: choice,
    source: source,
    selected: selected,
    path: oneStep
        ? [
            step(
              1,
              source,
              selected,
              LongTermRelationType.need,
              RelationScope.archived,
              null,
            ),
          ]
        : [
            step(
              1,
              source,
              middle,
              LongTermRelationType.need,
              RelationScope.archived,
              null,
            ),
            step(
              2,
              middle,
              selected,
              LongTermRelationType.can,
              RelationScope.active,
              _stepId(1),
            ),
          ],
  );
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;
  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    final n = value.compareTo((other as _Revision).value);
    return n < 0
        ? GraphRevisionOrder.older
        : n > 0
        ? GraphRevisionOrder.newer
        : GraphRevisionOrder.same;
  }
}

final class _Change implements GraphChange {
  const _Change();
  @override
  GraphRevision get revision => const _Revision(2);
}

final class _Repository implements PersonalGraphRepository {
  final updateCommands = <UpdateDailyChoiceFields>[];
  final updateRequests = <Completer<DailyChoiceCommandResult>>[];
  final controller = StreamController<DailyChoiceReadResult>.broadcast(
    sync: true,
  );
  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      controller.stream;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! UpdateDailyChoiceFields) throw UnimplementedError();
    updateCommands.add(command as UpdateDailyChoiceFields);
    final request = Completer<DailyChoiceCommandResult>();
    updateRequests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void succeedUpdate() {
    final details = _details();
    final choice = details.choice;
    updateRequests.single.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: const _Revision(2),
          value: DailyChoiceFieldsUpdated(
            before: choice,
            choice: choice,
            path: StoredChoicePath(details.path.map((step) => step.step)),
            changes: const [_Change()],
          ),
        ),
      ),
    );
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => Future.error(StateError('Нет данных каталога в этом тесте'));

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      const Stream.empty();

  @override
  Stream<Result<GraphSnapshot<application.IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => const Stream.empty();

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) => Future.error(StateError('Нет данных соседства в этом тесте'));
  void emit(DailyChoiceDetails details, {int revision = 1}) => controller.add(
    DailyChoiceReadSuccess(
      GraphSnapshot(value: details, revision: _Revision(revision)),
    ),
  );
  void emitMissing({required int revision}) => controller.add(
    DailyChoiceReadSuccess(
      GraphSnapshot<DailyChoiceDetails?>(
        value: null,
        revision: _Revision(revision),
      ),
    ),
  );
  void fail(DailyChoiceReadFailure failure) =>
      controller.add(DailyChoiceReadError(failure));
  Future<void> dispose() => controller.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
