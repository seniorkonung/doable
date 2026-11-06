import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_state.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  final id = _choiceId(1);

  test(
    'наблюдает нужный выбор, отклоняет старый снимок и закрывает поток',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final model = harness.model;
      expect(harness.repository.observedId, id);
      harness.repository.emit(null, revision: 2);
      await pumpEventQueue();
      expect(model.state, isA<DailyChoiceDetailsNotFound>());
      harness.repository.emit(_details(id), revision: 1);
      await pumpEventQueue();
      expect(model.state, isA<DailyChoiceDetailsNotFound>());
      model.dispose();
      await pumpEventQueue();
      expect(harness.repository.hasListener, isFalse);
    },
  );

  test('изменение отправляет патч этого выбора и завершается успехом только '
      'со снимком записанной ревизии из подписки', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;
    final confirmed = model.state;

    bool? saved;
    unawaited(model.change(_patch).then((value) => saved = value));
    expect(model.operation, isA<DailyChoiceDetailsOperationWriting>());
    expect(harness.repository.updates.single.choiceId, id);
    expect(harness.repository.updates.single.patch, same(_patch));

    harness.repository.succeedUpdate(id);
    await pumpEventQueue();
    expect(model.operation, isA<DailyChoiceDetailsOperationAwaitingSnapshot>());
    expect(model.state, same(confirmed));
    expect(saved, isNull);

    harness.repository.emit(_details(id), revision: 2);
    await pumpEventQueue();
    expect(model.state, isNot(same(confirmed)));
    expect(model.state, isA<DailyChoiceDetailsLoaded>());
    expect(model.operation, isA<DailyChoiceDetailsOperationIdle>());
    expect(saved, isTrue);
  });

  for (final (outcome, finish) in <(String, void Function(_Repository))>[
    ('выбор не найден', (repository) => repository.emit(null, revision: 3)),
    (
      'отказ чтения',
      (repository) => repository.controller.add(
        const DailyChoiceReadError(DailyChoiceReadUnavailableFailure()),
      ),
    ),
  ]) {
    test(
      'исход подписки «$outcome» тоже заканчивает ожидание снимка',
      () async {
        final harness = await _Harness.loaded();
        addTearDown(harness.dispose);
        final model = harness.model;

        final saved = model.change(_patch);
        harness.repository.succeedUpdate(id);
        await pumpEventQueue();
        expect(
          model.operation,
          isA<DailyChoiceDetailsOperationAwaitingSnapshot>(),
        );

        finish(harness.repository);

        expect(await saved, isTrue);
        expect(model.operation, isA<DailyChoiceDetailsOperationIdle>());
      },
    );
  }

  test('запись без изменения значений не оставляет ожидание снимка', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;
    final shown = _details(id).choice;

    final saved = model.change(_patch);
    harness.repository.succeedUpdate(id, written: shown);

    expect(await saved, isTrue);
    expect(model.operation, isA<DailyChoiceDetailsOperationIdle>());
    expect(model.state, isA<DailyChoiceDetailsLoaded>());

    final next = model.change(_patch);
    expect(harness.repository.commands, hasLength(2));
    expect(model.operation, isA<DailyChoiceDetailsOperationWriting>());
    harness.repository.succeedUpdate(id, written: shown);
    expect(await next, isTrue);
  });

  test('запись, отличающаяся от показанного снимка любым значением, ждёт '
      'снимок', () async {
    final shown = _details(id).choice;
    final differing = <String, DailyChoice>{
      'датой': _withFields(shown, date: CalendarDate.fromParts(2026, 9, 25)),
      'описанием': _withFields(
        shown,
        description: DailyChoiceDescription.fromInput('Описание'),
      ),
      'выполнением': _withFields(shown, isCompleted: true),
      'временем': _withFields(
        shown,
        schedule: DailyChoiceTime(hour: 9, minute: 0),
      ),
      'приоритетом': _withFields(shown, priority: DailyChoicePriority.p1),
    };
    for (final MapEntry(key: field, value: written) in differing.entries) {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;

      final saved = model.change(_patch);
      harness.repository.succeedUpdate(id, written: written);
      await pumpEventQueue();

      expect(
        model.operation,
        isA<DailyChoiceDetailsOperationAwaitingSnapshot>(),
        reason: 'запись, отличающаяся $field',
      );

      harness.repository.emit(_details(id), revision: 2);
      expect(await saved, isTrue);
    }
  });

  test('изменение и удаление делят одну операцию', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;

    model.change(_patch);
    model.change(_patch);
    expect(await model.delete(), isFalse);
    expect(harness.repository.commands, hasLength(1));
    expect(model.operation, isA<DailyChoiceDetailsOperationWriting>());

    harness.repository.succeedUpdate(id);
    await pumpEventQueue();
    expect(await model.delete(), isFalse);
    expect(harness.repository.commands, hasLength(1));

    harness.repository.emit(_details(id), revision: 2);
    await pumpEventQueue();
    final deletion = model.delete();
    model.change(_patch);
    expect(harness.repository.commands, hasLength(2));
    harness.repository.succeedDelete(id);
    expect(await deletion, isTrue);
  });

  test('без загруженного выбора операции не отправляются', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final model = harness.model;

    model.change(_patch);
    expect(await model.delete(), isFalse);

    harness.repository.emit(null, revision: 1);
    await pumpEventQueue();
    model.change(_patch);
    expect(await model.delete(), isFalse);

    expect(harness.repository.commands, isEmpty);
    expect(model.operation, isA<DailyChoiceDetailsOperationIdle>());
  });

  test(
    'отказ оставляет подтверждённый снимок и переживает новые снимки',
    () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;
      final confirmed = model.state;

      model.change(_patch);
      harness.repository.fail(const DailyChoiceUnavailableFailure());
      await pumpEventQueue();

      final failed = model.operation as DailyChoiceDetailsOperationFailed;
      expect(failed.failure, isA<DailyChoiceUnavailableFailure>());
      expect(failed.failurePresentation, isNotNull);
      expect(model.state, same(confirmed));

      harness.repository.emit(_details(id), revision: 2);
      await pumpEventQueue();
      expect(model.operation, same(failed));
    },
  );

  test(
    'принятая операция снимает прежний отказ и отдаёт его общей поверхности',
    () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;
      final shell = harness.coordinator.registerAppPresentation();
      addTearDown(shell.release);
      final claim = shell.nextClaim();

      model.change(_patch);
      harness.repository.fail(const DailyChoiceUnavailableFailure());
      await pumpEventQueue();

      model.change(_patch);
      expect(model.operation, isA<DailyChoiceDetailsOperationWriting>());
      expect((await claim)!.completions, hasLength(1));
      expect((await claim)!.completions.single.isFailure, isTrue);
      expect(harness.repository.commands, hasLength(2));
    },
  );

  for (final closesBeforeResult in [true, false]) {
    final moment = closesBeforeResult ? 'до результата' : 'после отказа';
    test('закрытие $moment отдаёт отказ общей поверхности один раз', () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;
      final shell = harness.coordinator.registerAppPresentation();
      addTearDown(shell.release);
      final claim = shell.nextClaim();

      model.change(_patch);
      if (closesBeforeResult) model.dispose();
      harness.repository.fail(const DailyChoiceUnavailableFailure());
      await pumpEventQueue();
      if (!closesBeforeResult) model.dispose();

      expect((await claim)!.completions, hasLength(1));
      expect((await claim)!.completions.single.isFailure, isTrue);
    });
  }

  test('занятый выбор даёт отказ конфликта без права предъявления', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;
    harness.coordinator.acceptDailyChoiceUpdate(
      UpdateDailyChoiceFields(choiceId: id, patch: _patch),
    );

    expect(await model.delete(), isFalse);
    final failed = model.operation as DailyChoiceDetailsOperationFailed;
    expect(
      failed.failure,
      isA<DailyChoiceConflictFailure>().having(
        (failure) => failure.reason,
        'причина',
        DailyChoiceConflictReason.dependencyChanged,
      ),
    );
    expect(failed.failurePresentation, isNull);
    expect(harness.repository.commands, hasLength(1));
    harness.repository.succeedUpdate(id);
  });

  test('остановка координатора даёт непредвиденный отказ', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;
    unawaited(harness.coordinator.shutdown());

    model.change(_patch);
    final failed = model.operation as DailyChoiceDetailsOperationFailed;
    expect(failed.failure, isA<DailyChoiceUnexpectedFailure>());
    expect(failed.failurePresentation, isNull);
    expect(harness.repository.commands, isEmpty);
  });

  test('удаление истинно только после подтверждения этого выбора', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;

    final failedDeletion = model.delete();
    expect(model.operation, isA<DailyChoiceDetailsOperationWriting>());
    harness.repository.fail(const DailyChoiceUnavailableFailure());
    expect(await failedDeletion, isFalse);
    expect(model.operation, isA<DailyChoiceDetailsOperationFailed>());

    final foreignDeletion = model.delete();
    harness.repository.succeedDelete(_choiceId(2));
    expect(await foreignDeletion, isFalse);
    expect(
      (model.operation as DailyChoiceDetailsOperationFailed).failure,
      isA<DailyChoiceUnexpectedFailure>(),
    );

    final deletion = model.delete();
    harness.repository.succeedDelete(id);
    expect(await deletion, isTrue);
    expect(model.operation, isA<DailyChoiceDetailsOperationIdle>());
    final command = harness.repository.commands.last as DeleteDailyChoice;
    expect(command.choiceId, id);
  });
}

const _patchedPriority = DailyChoicePriority.p1;
const _patch = DailyChoiceFieldsPatch(
  priority: DailyChoiceFieldSet(_patchedPriority),
);

DailyChoice _withPriority(DailyChoice choice, DailyChoicePriority priority) =>
    _withFields(choice, priority: priority);

/// Копия выбора с заменой указанных значений; пустое описание не задаётся.
DailyChoice _withFields(
  DailyChoice choice, {
  CalendarDate? date,
  DailyChoiceDescription? description,
  bool? isCompleted,
  DailyChoiceSchedule? schedule,
  DailyChoicePriority? priority,
}) => DailyChoice(
  id: choice.id,
  sourceIntentionId: choice.sourceIntentionId,
  selectedIntentionId: choice.selectedIntentionId,
  date: date ?? choice.date,
  description: description ?? choice.description,
  isCompleted: isCompleted ?? choice.isCompleted,
  schedule: schedule ?? choice.schedule,
  priority: priority ?? choice.priority,
);

DailyChoiceId _choiceId(int number) => (DailyChoiceId.decode(
  '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;

final class _Harness {
  _Harness() : repository = _Repository() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    model = DailyChoiceDetailsViewModel(repository, coordinator, _choiceId(1));
  }

  static Future<_Harness> loaded() async {
    final harness = _Harness();
    harness.repository.emit(_details(_choiceId(1)), revision: 1);
    await pumpEventQueue();
    return harness;
  }

  final _Repository repository;
  late final ProviderContainer container;
  late final DailyChoiceDetailsViewModel model;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  Future<void> dispose() async {
    await repository.dispose();
    container.dispose();
  }
}

DailyChoiceDetails _details(DailyChoiceId id) {
  Intention participant(int number) => Intention(
    id: (IntentionId.decode(
      '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
    ) as IntentionIdDecodingSuccess).id,
    title: 'Намерение $number',
    description: null,
    readiness: IntentionReadiness.ready,
    archiveState: IntentionArchiveState.active,
    createdAt: IntentionTimestamp(DateTime.utc(2026)),
    updatedAt: IntentionTimestamp(DateTime.utc(2026)),
  );
  final source = participant(1);
  final selected = participant(2);
  final relationId = (LongTermRelationId.decode(
    '018f0b5d-6b2e-7c80-8000-000000000003',
  ) as LongTermRelationIdDecodingSuccess).id;
  final stepId = (ChoicePathStepId.decode(
    '018f0b5d-6b2e-7c80-8000-000000000004',
  ) as ChoicePathStepIdDecodingSuccess).id;
  return DailyChoiceDetails(
    choice: DailyChoice(
      id: id,
      sourceIntentionId: source.id,
      selectedIntentionId: selected.id,
      date: CalendarDate.fromParts(2026, 9, 24),
      description: null,
      isCompleted: false,
    ),
    source: source,
    selected: selected,
    path: [
      DailyChoicePathStepDetails(
        step: ChoicePathStep(
          id: stepId,
          dailyChoiceId: id,
          relationId: relationId,
          previousStepId: null,
        ),
        relation: LongTermRelation(
          id: relationId,
          sourceIntentionId: source.id,
          relatedIntentionId: selected.id,
          type: LongTermRelationType.need,
          priority: RelationPriority.p1,
          scope: RelationScope.active,
          creationSequence: RelationCreationSequence(1),
          createdAt: RelationTimestamp(DateTime.utc(2026)),
          updatedAt: RelationTimestamp(DateTime.utc(2026)),
        ),
        description: null,
        source: source,
        related: selected,
      ),
    ],
  );
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;
  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    final difference = value.compareTo((other as _Revision).value);
    return difference < 0
        ? GraphRevisionOrder.older
        : difference > 0
        ? GraphRevisionOrder.newer
        : GraphRevisionOrder.same;
  }
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final controller = StreamController<DailyChoiceReadResult>(sync: true);
  final commands = <DailyChoiceCommand>[];
  final _requests = <Completer<DailyChoiceCommandResult>>[];
  DailyChoiceId? observedId;
  bool get hasListener => controller.hasListener;
  Iterable<UpdateDailyChoiceFields> get updates =>
      commands.whereType<UpdateDailyChoiceFields>();
  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) {
    observedId = id;
    return controller.stream;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command as DailyChoiceCommand);
    final request = Completer<DailyChoiceCommandResult>();
    _requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void fail(DailyChoiceCommandFailure failure) =>
      _requests.last.complete(GraphCommandFailed(failure));

  /// Подтверждает запись; без [written] она меняет приоритет, как [_patch].
  void succeedUpdate(DailyChoiceId id, {DailyChoice? written}) {
    final details = _details(id);
    _requests.last.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: const _Revision(2),
          value: DailyChoiceFieldsUpdated(
            before: details.choice,
            choice: written ?? _withPriority(details.choice, _patchedPriority),
            path: StoredChoicePath(details.path.map((step) => step.step)),
            changes: const [_Change()],
          ),
        ),
      ),
    );
  }

  void succeedDelete(DailyChoiceId id) => _requests.last.complete(
    GraphCommandSucceeded(
      ConfirmedGraphResult(
        revision: const _Revision(2),
        value: DailyChoiceDeleted(
          choice: _details(id).choice,
          changes: const [_Change()],
        ),
      ),
    ),
  );

  void emit(DailyChoiceDetails? details, {required int revision}) =>
      controller.add(
        DailyChoiceReadSuccess(
          GraphSnapshot(value: details, revision: _Revision(revision)),
        ),
      );
  Future<void> dispose() => controller.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Change implements GraphChange {
  const _Change();
  @override
  GraphRevision get revision => const _Revision(2);
}
