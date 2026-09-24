import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_state.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'отправляет независимые поля и удерживает повтор до результата',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.model
        ..changeDate(CalendarDate.fromParts(1, 1, 1))
        ..changeCompletion(true)
        ..submit()
        ..submit();
      expect(harness.repository.commands, hasLength(1));
      final patch = harness.repository.commands.single.patch;
      expect(patch.date, isA<DailyChoiceFieldSet<CalendarDate>>());
      expect(patch.description, isA<DailyChoiceDescriptionUnchanged>());
      expect((patch.isCompleted as DailyChoiceFieldSet<bool>).value, isTrue);
      expect(harness.state.operation, isA<DailyChoiceEditSubmitting>());
      harness.repository.succeed(0);
      await pumpEventQueue();
      expect(harness.state.operation, isA<DailyChoiceEditSucceeded>());
    },
  );

  test('очистка описания не меняет дату и выполнение', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model
      ..changeDescription(' \n ')
      ..submit();
    final patch = harness.repository.commands.single.patch;
    expect(patch.description, isA<DailyChoiceDescriptionCleared>());
    expect(patch.date, isA<DailyChoiceFieldUnchanged<CalendarDate>>());
    expect(patch.isCompleted, isA<DailyChoiceFieldUnchanged<bool>>());
  });

  test('отказ описания сохраняет дату и 4097 графем для исправления', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model
      ..changeDate(CalendarDate.fromParts(9999, 12, 31))
      ..changeDescription('е\u0301' * 4097)
      ..submit();
    expect(harness.repository.commands, isEmpty);
    expect(harness.state.date, CalendarDate.fromParts(9999, 12, 31));
    expect(harness.state.description, 'е\u0301' * 4097);
    expect(harness.state.operation, isA<DailyChoiceEditFailed>());
    harness.model.changeDescription('Исправлено');
    expect(harness.state.canSubmit, isTrue);
    harness.model.submit();
    expect(harness.repository.commands, hasLength(1));
  });

  test(
    'временный отказ допускает повтор, отсутствие и конфликт его блокируют',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.model.changeCompletion(true);
      harness.model.submit();
      harness.repository.fail(0, const DailyChoiceUnavailableFailure());
      await pumpEventQueue();
      expect(harness.state.canRetry, isTrue);
      expect(harness.state.failurePresentation, isNotNull);
      harness.model.submit();
      harness.repository.fail(1, const DailyChoiceNotFoundFailure());
      await pumpEventQueue();
      expect(harness.state.canSubmit, isFalse);
      expect(harness.state.isCompleted, isTrue);
      harness.model.submit();
      expect(harness.repository.commands, hasLength(2));

      final another = _Harness();
      addTearDown(another.dispose);
      another.model.changeCompletion(true);
      another.model.submit();
      another.repository.fail(
        0,
        const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.dependencyChanged,
        ),
      );
      await pumpEventQueue();
      expect(another.state.canSubmit, isFalse);
      expect(another.state.isCompleted, isTrue);
    },
  );

  test(
    'исправление ошибки даты исходным значением сохраняет другую правку',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.model
        ..changeDate(CalendarDate.fromParts(9999, 12, 31))
        ..changeCompletion(true)
        ..submit();
      harness.repository.fail(
        0,
        const DailyChoiceValidationFailure(DailyChoiceValidationField.date),
      );
      await pumpEventQueue();
      expect(harness.state.canSubmit, isFalse);
      harness.model.changeDate(CalendarDate.fromParts(2026, 9, 24));
      expect(harness.state.canSubmit, isTrue);
      harness.model.submit();
      expect(harness.repository.commands, hasLength(2));
      expect(
        harness.repository.commands.last.patch.date,
        isA<DailyChoiceFieldUnchanged<CalendarDate>>(),
      );
      expect(
        (harness.repository.commands.last.patch.isCompleted
                as DailyChoiceFieldSet<bool>)
            .value,
        isTrue,
      );
    },
  );

  test('уход формы не отменяет принятую запись и поздний результат', () async {
    final harness = _Harness();
    final presenter = harness.coordinator.registerAppPresentation();
    addTearDown(presenter.release);
    harness.model.changeCompletion(true);
    harness.model.submit();
    harness.closeForm();
    harness.repository.succeed(0);
    final claim = await presenter.nextClaim();
    expect(claim?.completion, isA<DailyChoiceCommandCompletion>());
    harness.coordinator.confirmPresentation(claim!);
    harness.dispose();
  });
}

final class _Harness {
  _Harness() : repository = _Repository() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    provider = dailyChoiceEditViewModelProvider(repository.choice);
    subscription = container.listen(provider, (_, _) {});
  }

  final _Repository repository;
  late final ProviderContainer container;
  late final DailyChoiceEditViewModelProvider provider;
  late final ProviderSubscription<DailyChoiceEditState> subscription;
  DailyChoiceEditViewModel get model => container.read(provider.notifier);
  DailyChoiceEditState get state => container.read(provider);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  void closeForm() => subscription.close();
  void dispose() => container.dispose();
}

final class _Repository implements PersonalGraphRepository {
  final choice = DailyChoice(
    id: _choiceId(),
    sourceIntentionId: _intentionId(1),
    selectedIntentionId: _intentionId(2),
    date: CalendarDate.fromParts(2026, 9, 24),
    description: DailyChoiceDescription.fromInput('Исходное описание'),
    isCompleted: false,
  );
  final commands = <UpdateDailyChoiceFields>[];
  final _requests = <Completer<DailyChoiceCommandResult>>[];

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! UpdateDailyChoiceFields) throw UnimplementedError();
    commands.add(command as UpdateDailyChoiceFields);
    final request = Completer<DailyChoiceCommandResult>();
    _requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void fail(int index, DailyChoiceCommandFailure failure) =>
      _requests[index].complete(GraphCommandFailed(failure));

  void succeed(int index) {
    final command = commands[index];
    _requests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: const _Revision(),
          value: DailyChoiceFieldsUpdated(
            before: choice,
            choice: DailyChoice(
              id: choice.id,
              sourceIntentionId: choice.sourceIntentionId,
              selectedIntentionId: choice.selectedIntentionId,
              date: switch (command.patch.date) {
                DailyChoiceFieldSet<CalendarDate>(:final value) => value,
                _ => choice.date,
              },
              description: choice.description,
              isCompleted: switch (command.patch.isCompleted) {
                DailyChoiceFieldSet<bool>(:final value) => value,
                _ => choice.isCompleted,
              },
            ),
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(),
                dailyChoiceId: choice.id,
                relationId: _relationId(),
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

final class _Revision implements GraphRevision {
  const _Revision();
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is _Revision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

final class _Change implements GraphChange {
  const _Change();
  @override
  GraphRevision get revision => const _Revision();
}

String _uuid(int index) =>
    '018f1400-0000-7000-8000-${index.toString().padLeft(12, '0')}';
DailyChoiceId _choiceId() =>
    (DailyChoiceId.decode(_uuid(1)) as DailyChoiceIdDecodingSuccess).id;
ChoicePathStepId _stepId() =>
    (ChoicePathStepId.decode(_uuid(2)) as ChoicePathStepIdDecodingSuccess).id;
LongTermRelationId _relationId() => (LongTermRelationId.decode(
  _uuid(3),
) as LongTermRelationIdDecodingSuccess).id;
IntentionId _intentionId(int index) =>
    (IntentionId.decode(_uuid(index + 3)) as IntentionIdDecodingSuccess).id;
