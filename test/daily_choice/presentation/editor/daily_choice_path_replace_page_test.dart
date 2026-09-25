import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_path_replace_page.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  test('показанные шаги обязаны совпадать с подтверждаемым путём', () {
    final path = ConfirmedChoicePath([
      _pathStep(2, 3, 4, LongTermRelationType.need),
    ]);
    expect(
      () => DailyChoicePathReplacePage(
        choiceId: _choiceId(),
        path: path,
        steps: [
          DailyChoiceCreationStep(
            relation: _relation(3, 3, 4, LongTermRelationType.need),
            sourceTitle: 'Основание',
            relatedTitle: 'Действие',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'показывает полный новый путь и сохраняемые поля до подтверждения',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      expect(find.text('Загружаем дневной выбор…'), findsOneWidget);
      expect(repository.commands, isEmpty);

      repository.completeRead(repository.details);
      await tester.pumpAndSettle();
      expect(find.textContaining('Старое основание'), findsWidgets);
      expect(find.textContaining('Старое действие'), findsWidgets);
      expect(find.textContaining('Новое основание'), findsWidgets);
      expect(find.textContaining('Промежуточное Б'), findsWidgets);
      expect(find.textContaining('Промежуточное В'), findsWidgets);
      expect(find.textContaining('Новое действие'), findsWidgets);
      expect(find.textContaining('2026-09-24'), findsWidgets);
      expect(find.text('Прежнее описание'), findsOneWidget);
      expect(find.text('Выполнено'), findsWidgets);
      expect(find.textContaining('сохраня'), findsWidgets);
      expect(repository.commands, isEmpty);

      await _tapVisible(tester, const ValueKey('daily-choice-replace-confirm'));
      await tester.pump();
      expect(repository.commands, hasLength(1));
      expect(repository.commands.single.choiceId, repository.choice.id);
      expect(repository.commands.single.path.steps, hasLength(3));
      expect(repository.commands.single.selectedIntentionId, _intentionId(6));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('daily-choice-replace-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Старое основание'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Старое основание'), findsWidgets);
    },
  );

  testWidgets('отмена возвращает к прежнему выбору без команды', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    repository.completeRead(repository.details);
    await tester.pumpAndSettle();
    await _tapVisible(tester, const ValueKey('daily-choice-replace-cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Домашний экран'), findsOneWidget);
    expect(repository.commands, isEmpty);
  });

  testWidgets('успех закрывает подтверждение только после результата команды', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    repository.completeRead(repository.details);
    await tester.pumpAndSettle();
    await _tapVisible(tester, const ValueKey('daily-choice-replace-confirm'));
    await tester.pump();
    expect(find.text('Домашний экран'), findsNothing);
    repository.succeed();
    await tester.pumpAndSettle();
    expect(find.text('Домашний экран'), findsOneWidget);
    expect(find.textContaining('Путь дневного выбора заменён'), findsOneWidget);
  });

  testWidgets('отсутствие и ошибки чтения не предлагают воссоздание', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository);
    repository.completeRead(null);
    await tester.pumpAndSettle();
    expect(find.text('Дневной выбор больше не существует.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('daily-choice-replace-confirm')),
      findsNothing,
    );
    expect(repository.commands, isEmpty);

    final retryRepository = _Repository();
    await _pump(tester, retryRepository);
    retryRepository.failRead(const DailyChoiceReadUnavailableFailure());
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось загрузить дневной выбор. Повторите попытку.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(retryRepository.reads, hasLength(2));
    retryRepository.failRead(const DailyChoiceReadCorruptionFailure());
    await tester.pumpAndSettle();
    expect(
      find.text('Сохранённый путь повреждён и не может быть показан.'),
      findsOneWidget,
    );
    expect(find.text('Повторить'), findsNothing);
  });

  testWidgets(
    'временный отказ показан общим сообщением и допускает явный повтор',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      repository.completeRead(repository.details);
      await tester.pumpAndSettle();
      await _tapVisible(tester, const ValueKey('daily-choice-replace-confirm'));
      await tester.pump();
      repository.fail(const DailyChoiceUnavailableFailure());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('daily-choice-replace-failure')),
        findsOneWidget,
      );
      expect(find.textContaining('Повторите попытку'), findsWidgets);
      expect(repository.commands, hasLength(1));
      await _tapVisible(tester, const ValueKey('daily-choice-replace-confirm'));
      await tester.pump();
      expect(repository.commands, hasLength(2));
      repository.fail(const DailyChoiceNotFoundFailure());
      await tester.pumpAndSettle();
      expect(find.text('Дневной выбор больше не существует.'), findsWidgets);
      expect(
        find.byKey(const ValueKey('daily-choice-replace-confirm')),
        findsNothing,
      );
    },
  );

  testWidgets('конфликт не повторяет команду и возвращает к выбору пути', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    repository.completeRead(repository.details);
    await tester.pumpAndSettle();
    await _tapVisible(tester, const ValueKey('daily-choice-replace-confirm'));
    await tester.pump();
    repository.fail(
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.relationArchived,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('daily-choice-replace-failure')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('daily-choice-replace-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(repository.commands, hasLength(1));
    expect(
      find.byKey(const ValueKey('daily-choice-replace-refresh-path')),
      findsOneWidget,
    );
    await tester.tap(find.text('Вернуться к выбору пути'));
    await tester.pumpAndSettle();
    expect(find.text('Домашний экран'), findsOneWidget);
    expect(repository.commands, hasLength(1));
  });

  testWidgets('неизвестный отказ не предлагает повтор или актуализацию пути', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository);
    repository.completeRead(repository.details);
    await tester.pumpAndSettle();
    await _tapVisible(tester, const ValueKey('daily-choice-replace-confirm'));
    await tester.pump();
    repository.fail(const DailyChoiceUnexpectedFailure());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('daily-choice-replace-failure')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('daily-choice-replace-refresh-path')),
      findsNothing,
    );
    expect(find.text('Повторить'), findsNothing);
    expect(repository.commands, hasLength(1));
  });

  testWidgets(
    'английская семантика и крупный текст раскрывают направление и каждый переход',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      await _pump(
        tester,
        repository,
        locale: const Locale('en'),
        textScale: 2,
        direction: ChoicePathDraftDirection.bottomUp,
      );
      repository.completeRead(repository.details);
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      expect(
        find.textContaining('from the action to a source'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Source intention: Новое основание')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Step 1:')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Step 2:')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Step 3:')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Selected action: Новое действие')),
        findsOneWidget,
      );
      expect(find.textContaining('Completion stays'), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp('Completion stays on')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  Locale locale = const Locale('ru'),
  GlobalKey<NavigatorState>? navigatorKey,
  ChoicePathDraftDirection direction = ChoicePathDraftDirection.topDown,
  double textScale = 1,
}) async {
  final path = ConfirmedChoicePath([
    _pathStep(2, 3, 4, LongTermRelationType.need),
    _pathStep(3, 4, 5, LongTermRelationType.can),
    _pathStep(4, 5, 6, LongTermRelationType.need),
  ]);
  final names = [
    'Новое основание',
    'Промежуточное Б',
    'Промежуточное В',
    'Новое действие',
  ];
  final steps = [
    for (var index = 0; index < 3; index++)
      DailyChoiceCreationStep(
        relation: _relation(
          index + 2,
          index + 3,
          index + 4,
          path.steps[index].type,
        ),
        sourceTitle: names[index],
        relatedTitle: names[index + 1],
      ),
  ];
  final page = DailyChoicePathReplacePage(
    choiceId: repository.choice.id,
    path: path,
    steps: steps,
    direction: direction,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: GraphOperationPresenter(child: child!),
        ),
        home: navigatorKey == null
            ? page
            : const Scaffold(body: Text('Домашний экран')),
      ),
    ),
  );
  if (navigatorKey != null) {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
}

final class _Repository implements PersonalGraphRepository {
  final choice = DailyChoice(
    id: _choiceId(),
    sourceIntentionId: _intentionId(1),
    selectedIntentionId: _intentionId(2),
    date: CalendarDate.fromParts(2026, 9, 24),
    description: DailyChoiceDescription.fromInput('Прежнее описание'),
    isCompleted: true,
  );
  final reads = <Completer<DailyChoiceReadResult>>[];
  final commands = <ReplaceDailyChoicePath>[];
  final requests = <Completer<DailyChoiceCommandResult>>[];

  DailyChoiceDetails get details => DailyChoiceDetails(
    choice: choice,
    source: _intention(1, 'Старое основание'),
    selected: _intention(2, 'Старое действие'),
    path: [
      DailyChoicePathStepDetails(
        step: ChoicePathStep(
          id: _stepId(),
          dailyChoiceId: choice.id,
          relationId: _relationId(1),
          previousStepId: null,
        ),
        relation: _relation(1, 1, 2, LongTermRelationType.need),
        description: null,
        source: _intention(1, 'Старое основание'),
        related: _intention(2, 'Старое действие'),
      ),
    ],
  );

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) {
    final read = Completer<DailyChoiceReadResult>();
    reads.add(read);
    return read.future;
  }

  void completeRead(DailyChoiceDetails? details) => reads.last.complete(
    DailyChoiceReadSuccess(
      GraphSnapshot(value: details, revision: const _Revision()),
    ),
  );
  void failRead(DailyChoiceReadFailure failure) =>
      reads.last.complete(DailyChoiceReadError(failure));

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command as ReplaceDailyChoicePath);
    final request = Completer<DailyChoiceCommandResult>();
    requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void fail(DailyChoiceCommandFailure failure) =>
      requests.last.complete(GraphCommandFailed(failure));

  void succeed() {
    final command = commands.last;
    final replacement = DailyChoice(
      id: choice.id,
      sourceIntentionId: command.sourceIntentionId,
      selectedIntentionId: command.selectedIntentionId,
      date: choice.date,
      description: choice.description,
      isCompleted: choice.isCompleted,
    );
    ChoicePathStepId? previous;
    final steps = <ChoicePathStep>[];
    for (var index = 0; index < command.path.steps.length; index++) {
      final id = _stepId(index + 1);
      steps.add(
        ChoicePathStep(
          id: id,
          dailyChoiceId: choice.id,
          relationId: command.path.steps[index].relationId,
          previousStepId: previous,
        ),
      );
      previous = id;
    }
    requests.last.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: const _Revision(),
          value: DailyChoicePathReplaced(
            before: choice,
            choice: replacement,
            path: StoredChoicePath(steps),
            changes: const [_Change()],
          ),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConfirmedChoicePathStep _pathStep(
  int relation,
  int source,
  int related,
  LongTermRelationType type,
) => ConfirmedChoicePathStep(
  relationId: _relationId(relation),
  sourceIntentionId: _intentionId(source),
  relatedIntentionId: _intentionId(related),
  type: type,
);

LongTermRelation _relation(
  int id,
  int source,
  int related,
  LongTermRelationType type,
) => LongTermRelation(
  id: _relationId(id),
  sourceIntentionId: _intentionId(source),
  relatedIntentionId: _intentionId(related),
  type: type,
  priority: RelationPriority.p1,
  scope: RelationScope.active,
  creationSequence: RelationCreationSequence(id),
);

Intention _intention(int id, String title) => Intention(
  id: _intentionId(id),
  title: title,
  description: null,
  readiness: IntentionReadiness.ready,
  archiveState: IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

String _uuid(int index) =>
    '018f1400-0000-7000-8000-${index.toString().padLeft(12, '0')}';
DailyChoiceId _choiceId() =>
    (DailyChoiceId.decode(_uuid(1)) as DailyChoiceIdDecodingSuccess).id;
ChoicePathStepId _stepId([int id = 1]) => (ChoicePathStepId.decode(
  _uuid(1 + id),
) as ChoicePathStepIdDecodingSuccess).id;
LongTermRelationId _relationId(int id) => (LongTermRelationId.decode(
  _uuid(10 + id),
) as LongTermRelationIdDecodingSuccess).id;
IntentionId _intentionId(int id) =>
    (IntentionId.decode(_uuid(20 + id)) as IntentionIdDecodingSuccess).id;

final class _Revision implements GraphRevision {
  const _Revision();
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

final class _Change implements GraphChange {
  const _Change();
  @override
  GraphRevision get revision => const _Revision();
}
