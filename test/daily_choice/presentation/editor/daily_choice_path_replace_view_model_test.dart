import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_path_replace_state.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_path_replace_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  test(
    'читает выбранную запись, принимает целый путь и отменяет черновик',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      expect(harness.model.state, isA<DailyChoicePathReplaceLoading>());
      expect(harness.repository.readId, harness.repository.choice.id);
      harness.repository.completeRead(harness.repository.details);
      await pumpEventQueue();
      expect(harness.model.state, isA<DailyChoicePathReplaceChoosing>());
      harness.model.selectPath(_newPath());
      final ready = harness.model.state as DailyChoicePathReplaceReady;
      expect(ready.details.choice.isCompleted, isTrue);
      expect(ready.details.choice.description?.value, 'Прежнее описание');
      expect(ready.path.steps.last.relatedIntentionId, _intentionId(4));
      expect(harness.repository.commands, isEmpty);
      harness.model.cancelSelection();
      expect(harness.model.state, isA<DailyChoicePathReplaceChoosing>());
      expect(harness.repository.commands, isEmpty);
    },
  );

  test(
    'подтверждение меняет только путь и ждёт commit без повторной команды',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.completeRead(harness.repository.details);
      await pumpEventQueue();
      harness.model
        ..selectPath(_newPath())
        ..confirm()
        ..confirm();
      expect(harness.model.state, isA<DailyChoicePathReplaceSubmitting>());
      expect(harness.repository.commands, hasLength(1));
      final command = harness.repository.commands.single;
      expect(command.choiceId, harness.repository.choice.id);
      expect(command.sourceIntentionId, _intentionId(3));
      expect(command.selectedIntentionId, _intentionId(4));
      expect(command.path.steps.single.relationId, _relationId(2));
      expect(
        harness.coordinator.isDailyChoiceRunning(command.choiceId),
        isTrue,
      );
      expect(
        harness.coordinator.acceptDailyChoiceDelete(
          DeleteDailyChoice(command.choiceId),
        ),
        isA<DailyChoiceCommandAlreadyRunning>(),
      );
      harness.repository.succeed();
      await pumpEventQueue();
      final succeeded = harness.model.state as DailyChoicePathReplaceSucceeded;
      expect(succeeded.choice.id, harness.repository.choice.id);
      expect(succeeded.choice.date, harness.repository.choice.date);
      expect(
        succeeded.choice.description,
        harness.repository.choice.description,
      );
      expect(succeeded.choice.isCompleted, isTrue);
      expect(succeeded.choice.selectedIntentionId, _intentionId(4));
      expect(
        harness.coordinator.isDailyChoiceRunning(command.choiceId),
        isFalse,
      );
    },
  );

  test('отсутствие записи и ошибка чтения не разрешают замену', () async {
    final missing = _Harness();
    addTearDown(missing.dispose);
    missing.repository.completeRead(null);
    await pumpEventQueue();
    expect(missing.model.state, isA<DailyChoicePathReplaceNotFound>());
    missing.model
      ..selectPath(_newPath())
      ..confirm();
    expect(missing.repository.commands, isEmpty);

    final unavailable = _Harness();
    addTearDown(unavailable.dispose);
    unavailable.repository.failRead(const DailyChoiceReadUnavailableFailure());
    await pumpEventQueue();
    expect(unavailable.model.state, isA<DailyChoicePathReplaceReadFailed>());
    unavailable.model.retryRead();
    expect(unavailable.model.state, isA<DailyChoicePathReplaceLoading>());
    unavailable.repository.completeRead(unavailable.repository.details);
    await pumpEventQueue();
    expect(unavailable.model.state, isA<DailyChoicePathReplaceChoosing>());

    final corrupted = _Harness();
    addTearDown(corrupted.dispose);
    corrupted.repository.failRead(const DailyChoiceReadCorruptionFailure());
    await pumpEventQueue();
    expect(
      (corrupted.model.state as DailyChoicePathReplaceReadFailed).canRetry,
      isFalse,
    );
    corrupted.model.retryRead();
    expect(corrupted.repository.reads, hasLength(1));
  });

  test('временный отказ допускает явный повтор; конфликт и отсутствие требуют нового выбора', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.completeRead(harness.repository.details);
    await pumpEventQueue();
    harness.model
      ..selectPath(_newPath())
      ..confirm();
    harness.repository.fail(const DailyChoiceUnavailableFailure());
    await pumpEventQueue();
    final failed = harness.model.state as DailyChoicePathReplaceRejected;
    expect(failed.canRetry, isTrue);
    expect(failed.failurePresentation, isNotNull);
    harness.model.confirm();
    expect(harness.repository.commands, hasLength(2));
    harness.repository.fail(const DailyChoiceNotFoundFailure());
    await pumpEventQueue();
    expect(harness.model.state, isA<DailyChoicePathReplaceNotFound>());
    expect(
      (harness.model.state as DailyChoicePathReplaceNotFound)
          .failurePresentation,
      isNotNull,
    );
    harness.model.confirm();
    expect(harness.repository.commands, hasLength(2));

    final conflict = _Harness();
    addTearDown(conflict.dispose);
    conflict.repository.completeRead(conflict.repository.details);
    await pumpEventQueue();
    conflict.model
      ..selectPath(_newPath())
      ..confirm();
    conflict.repository.fail(
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.relationArchived,
      ),
    );
    await pumpEventQueue();
    expect(
      (conflict.model.state as DailyChoicePathReplaceRejected).canRetry,
      isFalse,
    );
    conflict.model.confirm();
    expect(conflict.repository.commands, hasLength(1));
    expect(conflict.repository.choice.isCompleted, isTrue);
  });

  test('конфликт требует нового предложения, а неизвестный отказ не допускает повтор', () async {
    final conflict = _Harness();
    addTearDown(conflict.dispose);
    conflict.repository.completeRead(conflict.repository.details);
    await pumpEventQueue();
    conflict.model
      ..selectPath(_newPath())
      ..confirm();
    conflict.repository.fail(
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.confirmedPathChanged,
      ),
    );
    await pumpEventQueue();
    conflict.model.confirm();
    expect(conflict.repository.commands, hasLength(1));
    conflict.model.selectPath(_anotherPath());
    expect(conflict.model.state, isA<DailyChoicePathReplaceLoading>());
    expect(conflict.repository.reads, hasLength(2));
    conflict.repository.completeRead(conflict.repository.details);
    await pumpEventQueue();
    expect(conflict.model.state, isA<DailyChoicePathReplaceReady>());
    conflict.model.confirm();
    expect(
      conflict.repository.commands.last.path.steps.single.relationId,
      _relationId(3),
    );
    conflict.repository.fail(const DailyChoiceUnavailableFailure());
    await pumpEventQueue();

    final unknown = _Harness();
    addTearDown(unknown.dispose);
    unknown.repository.completeRead(unknown.repository.details);
    await pumpEventQueue();
    unknown.model
      ..selectPath(_newPath())
      ..confirm();
    unknown.repository.fail(const DailyChoiceUnexpectedFailure());
    await pumpEventQueue();
    expect(
      (unknown.model.state as DailyChoicePathReplaceRejected).canRetry,
      isFalse,
    );
    unknown.model.confirm();
    expect(unknown.repository.commands, hasLength(1));
  });

  test('актуализация конфликта не возвращает старые поля и игнорирует два поздних чтения', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.completeRead(harness.repository.details);
    await pumpEventQueue();
    harness.model
      ..selectPath(_newPath())
      ..confirm();
    harness.repository.fail(
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.confirmedPathChanged,
      ),
    );
    await pumpEventQueue();

    harness.model.selectPath(_anotherPath());
    harness.model.selectPath(_newPath());
    expect(harness.repository.reads, hasLength(3));
    expect(harness.model.state, isA<DailyChoicePathReplaceLoading>());
    final changedChoice = DailyChoice(
      id: harness.repository.choice.id,
      sourceIntentionId: harness.repository.choice.sourceIntentionId,
      selectedIntentionId: harness.repository.choice.selectedIntentionId,
      date: CalendarDate.fromParts(2026, 9, 25),
      description: DailyChoiceDescription.fromInput('Актуальное описание'),
      isCompleted: false,
    );
    final details = harness.repository.details;
    harness.repository.completeReadAt(
      2,
      DailyChoiceDetails(
        choice: changedChoice,
        source: details.source,
        selected: details.selected,
        path: details.path,
      ),
    );
    await pumpEventQueue();
    final ready = harness.model.state as DailyChoicePathReplaceReady;
    expect(ready.details.choice.date, CalendarDate.fromParts(2026, 9, 25));
    expect(ready.details.choice.description?.value, 'Актуальное описание');
    expect(ready.details.choice.isCompleted, isFalse);
    expect(ready.path.steps.single.relationId, _relationId(2));
    harness.repository.completeReadAt(1, details);
    await pumpEventQueue();
    expect(identical(harness.model.state, ready), isTrue);
    harness.model.confirm();
    expect(harness.repository.commands, hasLength(2));
    expect(
      harness.repository.commands.last.path.steps.single.relationId,
      _relationId(2),
    );
    harness.repository.fail(const DailyChoiceUnavailableFailure());
    await pumpEventQueue();
  });

  test(
    'исчезновение записи и повреждение при актуализации не допускают замены',
    () async {
      final missing = _Harness();
      addTearDown(missing.dispose);
      missing.repository.completeRead(missing.repository.details);
      await pumpEventQueue();
      missing.model
        ..selectPath(_newPath())
        ..confirm();
      missing.repository.fail(
        const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.relationArchived,
        ),
      );
      await pumpEventQueue();
      missing.model.selectPath(_anotherPath());
      missing.repository.completeRead(null);
      await pumpEventQueue();
      expect(missing.model.state, isA<DailyChoicePathReplaceNotFound>());
      missing.model.confirm();
      expect(missing.repository.commands, hasLength(1));

      final corrupted = _Harness();
      addTearDown(corrupted.dispose);
      corrupted.repository.completeRead(corrupted.repository.details);
      await pumpEventQueue();
      corrupted.model
        ..selectPath(_newPath())
        ..confirm();
      corrupted.repository.fail(
        const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.relationArchived,
        ),
      );
      await pumpEventQueue();
      corrupted.model.selectPath(_anotherPath());
      corrupted.repository.failRead(const DailyChoiceReadCorruptionFailure());
      await pumpEventQueue();
      expect(
        (corrupted.model.state as DailyChoicePathReplaceReadFailed).canRetry,
        isFalse,
      );
      corrupted.model.confirm();
      expect(corrupted.repository.commands, hasLength(1));
    },
  );

  test(
    'временная ошибка чтения при актуализации допускает только явный повтор',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.completeRead(harness.repository.details);
      await pumpEventQueue();
      harness.model
        ..selectPath(_newPath())
        ..confirm();
      harness.repository.fail(
        const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.relationArchived,
        ),
      );
      await pumpEventQueue();
      harness.model.selectPath(_anotherPath());
      harness.repository.failRead(const DailyChoiceReadUnavailableFailure());
      await pumpEventQueue();
      expect(
        (harness.model.state as DailyChoicePathReplaceReadFailed).canRetry,
        isTrue,
      );
      expect(harness.repository.reads, hasLength(2));
      harness.model.retryRead();
      expect(harness.repository.reads, hasLength(3));
      harness.repository.completeRead(harness.repository.details);
      await pumpEventQueue();
      final ready = harness.model.state as DailyChoicePathReplaceReady;
      expect(ready.path.steps.single.relationId, _relationId(3));
      expect(harness.repository.commands, hasLength(1));
    },
  );

  test('новое предложение обязано быть непрерывным и простым', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.completeRead(harness.repository.details);
    await pumpEventQueue();
    final broken = ConfirmedChoicePath([
      _newPath().steps.single,
      ConfirmedChoicePathStep(
        relationId: _relationId(3),
        sourceIntentionId: _intentionId(1),
        type: LongTermRelationType.need,
        relatedIntentionId: _intentionId(2),
      ),
    ]);
    expect(() => harness.model.selectPath(broken), throwsArgumentError);
    expect(harness.model.state, isA<DailyChoicePathReplaceChoosing>());
  });

  test('закрытие модели не отменяет принятую команду и передаёт результат оболочке', () async {
    final harness = _Harness();
    final registration = harness.coordinator.registerAppPresentation();
    addTearDown(() async {
      registration.release();
      await harness.dispose();
    });
    harness.repository.completeRead(harness.repository.details);
    await pumpEventQueue();
    harness.model
      ..selectPath(_newPath())
      ..confirm();
    harness.model.dispose();
    harness.repository.succeed();
    final claim = await registration.nextClaim();
    expect(claim?.completion, isA<DailyChoiceCommandCompletion>());
    harness.coordinator.confirmPresentation(claim!);
    expect(harness.repository.commands, hasLength(1));
  });
}

final class _Harness {
  _Harness() : repository = _Repository() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    coordinator = container.read(graphCommandCoordinatorProvider.notifier);
    model = DailyChoicePathReplaceViewModel(
      repository,
      coordinator,
      repository.choice.id,
    );
  }

  final _Repository repository;
  late final ProviderContainer container;
  late final GraphCommandCoordinator coordinator;
  late final DailyChoicePathReplaceViewModel model;
  Future<void> dispose() async {
    if (!model.isDisposed) model.dispose();
    await coordinator.shutdown();
    container.dispose();
  }
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final choice = DailyChoice(
    id: _choiceId(),
    sourceIntentionId: _intentionId(1),
    selectedIntentionId: _intentionId(2),
    date: CalendarDate.fromParts(2026, 9, 24),
    description: DailyChoiceDescription.fromInput('Прежнее описание'),
    isCompleted: true,
  );
  DailyChoiceId? readId;
  final reads = <Completer<DailyChoiceReadResult>>[];
  final commands = <ReplaceDailyChoicePath>[];
  final requests = <Completer<DailyChoiceCommandResult>>[];

  DailyChoiceDetails get details {
    final source = _intention(1, archived: true);
    final selected = _intention(2);
    return DailyChoiceDetails(
      choice: choice,
      source: source,
      selected: selected,
      path: [
        DailyChoicePathStepDetails(
          step: ChoicePathStep(
            id: _stepId(),
            dailyChoiceId: choice.id,
            relationId: _relationId(1),
            previousStepId: null,
          ),
          relation: LongTermRelation(
            id: _relationId(1),
            sourceIntentionId: source.id,
            relatedIntentionId: selected.id,
            type: LongTermRelationType.need,
            priority: RelationPriority.p1,
            scope: RelationScope.archived,
            creationSequence: RelationCreationSequence(1),
          ),
          description: null,
          source: source,
          related: selected,
        ),
      ],
    );
  }

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) {
    readId = id;
    final completer = Completer<DailyChoiceReadResult>();
    reads.add(completer);
    return completer.future;
  }

  void completeRead(DailyChoiceDetails? value) => reads.last.complete(
    DailyChoiceReadSuccess(
      GraphSnapshot(value: value, revision: const _Revision()),
    ),
  );

  void completeReadAt(int index, DailyChoiceDetails? value) =>
      reads[index].complete(
        DailyChoiceReadSuccess(
          GraphSnapshot(value: value, revision: const _Revision()),
        ),
      );

  void failRead(DailyChoiceReadFailure failure) =>
      reads.last.complete(DailyChoiceReadError(failure));

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! ReplaceDailyChoicePath) throw UnimplementedError();
    commands.add(command as ReplaceDailyChoicePath);
    final completer = Completer<DailyChoiceCommandResult>();
    requests.add(completer);
    return await completer.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void fail(DailyChoiceCommandFailure failure) =>
      requests.last.complete(GraphCommandFailed(failure));

  void succeed() {
    final command = commands.last;
    final replaced = DailyChoice(
      id: choice.id,
      sourceIntentionId: command.sourceIntentionId,
      selectedIntentionId: command.selectedIntentionId,
      date: choice.date,
      description: choice.description,
      isCompleted: choice.isCompleted,
    );
    requests.last.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: const _Revision(),
          value: DailyChoicePathReplaced(
            before: choice,
            choice: replaced,
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(),
                dailyChoiceId: choice.id,
                relationId: command.path.steps.single.relationId,
                previousStepId: null,
              ),
            ]),
            changes: const [_Change()],
          ),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConfirmedChoicePath _newPath() => ConfirmedChoicePath([
  ConfirmedChoicePathStep(
    relationId: _relationId(2),
    sourceIntentionId: _intentionId(3),
    type: LongTermRelationType.can,
    relatedIntentionId: _intentionId(4),
  ),
]);

ConfirmedChoicePath _anotherPath() => ConfirmedChoicePath([
  ConfirmedChoicePathStep(
    relationId: _relationId(3),
    sourceIntentionId: _intentionId(1),
    type: LongTermRelationType.need,
    relatedIntentionId: _intentionId(4),
  ),
]);

Intention _intention(int number, {bool archived = false}) => Intention(
  id: _intentionId(number),
  title: 'Намерение $number',
  description: null,
  readiness: IntentionReadiness.ready,
  archiveState: archived
      ? IntentionArchiveState.archived
      : IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

String _uuid(int index) =>
    '018f1400-0000-7000-8000-${index.toString().padLeft(12, '0')}';
DailyChoiceId _choiceId() =>
    (DailyChoiceId.decode(_uuid(1)) as DailyChoiceIdDecodingSuccess).id;
ChoicePathStepId _stepId() =>
    (ChoicePathStepId.decode(_uuid(2)) as ChoicePathStepIdDecodingSuccess).id;
LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  _uuid(2 + number),
) as LongTermRelationIdDecodingSuccess).id;
IntentionId _intentionId(int number) =>
    (IntentionId.decode(_uuid(4 + number)) as IntentionIdDecodingSuccess).id;

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
