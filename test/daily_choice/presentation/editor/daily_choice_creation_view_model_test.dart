import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_flow_session.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_state.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_view_model.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/catalog_reconciliation_test_fallback.dart';

void main() {
  test('успех публикует событие перехода к созданному выбору', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model.submit();
    harness.repository.succeed(0);
    await pumpEventQueue();
    expect(harness.state.event, isA<DailyChoiceCreationCreated>());
    expect(harness.state.event!.choiceId, _dailyChoiceId(1));
  });

  test('пустое описание становится отсутствующим, а ввод остаётся видимым', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model.changeDescription('   ');
    harness.model.submit();
    expect(harness.state.description, '   ');
    expect(harness.repository.commands.single.description, isNull);
  });

  test(
    'та же сессия блокирует отправку после пересоздания формы во время записи',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);
      final session = _session();
      final path = _path();
      final date = CalendarDate.fromParts(2024, 1, 1);
      final provider = dailyChoiceCreationViewModelProvider(
        session,
        path,
        date,
      );
      final first = container.listen(provider, (_, _) {});
      container.read(provider.notifier).submit();
      first.close();
      await pumpEventQueue();

      final second = container.listen(provider, (_, _) {});
      addTearDown(second.close);
      container.read(provider.notifier).submit();
      expect(repository.commands, hasLength(1));
      repository.succeed(0);
      await pumpEventQueue();
      container.read(provider.notifier).submit();
      expect(repository.commands, hasLength(1));
    },
  );

  test('конфликт пути сохраняет ввод и требует нового подтверждения', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model
      ..changeDescription('Моё описание')
      ..changeCompletion(true)
      ..submit();
    harness.repository.fail(
      0,
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.confirmedPathChanged,
      ),
    );
    await pumpEventQueue();

    expect(harness.state.description, 'Моё описание');
    expect(harness.state.isCompleted, isTrue);
    expect(harness.state.needsPathRefresh, isTrue);
    harness.model.changeDate(CalendarDate.fromParts(2024, 3, 2));
    harness.model.submit();
    expect(harness.repository.commands, hasLength(1));

    final refreshed = _path(type: LongTermRelationType.can);
    expect(harness.model.confirmRefreshedPath(refreshed), isTrue);
    expect(harness.model.confirmRefreshedPath(_path()), isFalse);
    expect(harness.state.path.steps.single.type, LongTermRelationType.can);
    expect(harness.state.canSubmit, isTrue);
    harness.model.submit();
    expect(harness.repository.commands, hasLength(2));
    expect(
      harness.repository.commands.last.path.steps.single.type,
      LongTermRelationType.can,
    );
    expect(harness.repository.commands.last.description?.value, 'Моё описание');
    expect(
      harness.repository.commands.last.date,
      CalendarDate.fromParts(2024, 3, 2),
    );
    expect(harness.repository.commands.last.isCompleted, isTrue);

    harness.repository.fail(
      1,
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.confirmedPathChanged,
      ),
    );
    await pumpEventQueue();
    expect(harness.state.needsPathRefresh, isTrue);
    expect(harness.state.description, 'Моё описание');
    expect(harness.state.isCompleted, isTrue);
    expect(harness.state.date, CalendarDate.fromParts(2024, 3, 2));
    harness.model.changeDescription('После второго конфликта');
    harness.model.confirmRefreshedPath(_path());
    expect(harness.repository.commands, hasLength(2));
    harness.model.submit();
    expect(harness.repository.commands, hasLength(3));
    expect(
      harness.repository.commands.last.description?.value,
      'После второго конфликта',
    );
    expect(harness.repository.commands.last.isCompleted, isTrue);
    expect(
      harness.repository.commands.last.date,
      CalendarDate.fromParts(2024, 3, 2),
    );
  });

  test(
    'временная ошибка допускает явный повтор; неизвестная удерживает форму',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.model.submit();
      harness.repository.fail(0, const DailyChoiceUnavailableFailure());
      await pumpEventQueue();
      expect(harness.state.canRetry, isTrue);
      harness.model.submit();
      expect(harness.repository.commands, hasLength(2));
      harness.repository.fail(1, const DailyChoiceUnexpectedFailure());
      await pumpEventQueue();
      expect(harness.state.canSubmit, isFalse);
      expect(harness.state.description, isEmpty);
    },
  );

  test('ошибка поля даты допускает исправление без потери описания', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model
      ..changeDescription('Оставить описание')
      ..submit();
    harness.repository.fail(
      0,
      const DailyChoiceValidationFailure(DailyChoiceValidationField.date),
    );
    await pumpEventQueue();
    expect(harness.state.canSubmit, isFalse);

    harness.model.changeDate(CalendarDate.fromParts(9999, 12, 31));
    expect(harness.state.canSubmit, isTrue);
    expect(harness.state.description, 'Оставить описание');
    harness.model.submit();
    expect(
      harness.repository.commands.last.date,
      CalendarDate.fromParts(9999, 12, 31),
    );
  });
}

final class _Harness {
  _Harness({CalendarDate? date}) : repository = _Repository(), path = _path() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    provider = dailyChoiceCreationViewModelProvider(
      session,
      path,
      date ?? CalendarDate.fromParts(2024, 1, 1),
    );
    subscription = container.listen(provider, (_, _) {});
  }

  final _Repository repository;
  final session = _session();
  final ConfirmedChoicePath path;
  late final ProviderContainer container;
  late final DailyChoiceCreationViewModelProvider provider;
  late final ProviderSubscription<DailyChoiceCreationState> subscription;
  DailyChoiceCreationViewModel get model => container.read(provider.notifier);
  DailyChoiceCreationState get state => container.read(provider);
  void dispose() => container.dispose();
}

final class _Repository
    with TagReadContractTestFallback, CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  final commands = <CreateDailyChoice>[];
  final _requests = <Completer<DailyChoiceCommandResult>>[];

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! CreateDailyChoice) throw UnimplementedError();
    commands.add(command as CreateDailyChoice);
    final request = Completer<DailyChoiceCommandResult>();
    _requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void fail(int index, DailyChoiceCommandFailure failure) =>
      _requests[index].complete(GraphCommandFailed(failure));

  void succeed(int index) {
    final command = commands[index];
    const revision = _Revision();
    final id = _dailyChoiceId(index + 1);
    final choice = DailyChoice(
      id: id,
      sourceIntentionId: command.sourceIntentionId,
      selectedIntentionId: command.selectedIntentionId,
      date: command.date,
      description: command.description,
      isCompleted: command.isCompleted,
    );
    _requests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: DailyChoiceCreated(
            choice: choice,
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(index + 1),
                dailyChoiceId: id,
                relationId: command.path.steps.first.relationId,
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

ConfirmedChoicePath _path({
  LongTermRelationType type = LongTermRelationType.need,
}) => ConfirmedChoicePath([
  ConfirmedChoicePathStep(
    relationId: _relationId(1),
    sourceIntentionId: _intentionId(1),
    type: type,
    relatedIntentionId: _intentionId(2),
  ),
]);

IntentionId _intentionId(int index) => switch (IntentionId.decode(
  '018f1200-0000-7000-8000-${index.toString().padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Некорректный ID.'),
};

LongTermRelationId _relationId(int index) => switch (LongTermRelationId.decode(
  '018f1300-0000-7000-8000-${index.toString().padLeft(12, '0')}',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  InvalidLongTermRelationIdDecoding() => throw StateError('Некорректный ID.'),
};

DailyChoiceId _dailyChoiceId(int index) => switch (DailyChoiceId.decode(
  '018f1400-0000-7000-8000-${index.toString().padLeft(12, '0')}',
)) {
  DailyChoiceIdDecodingSuccess(:final id) => id,
  InvalidDailyChoiceIdDecoding() => throw StateError('Некорректный ID.'),
};

ChoicePathStepId _stepId(int index) => switch (ChoicePathStepId.decode(
  '018f1500-0000-7000-8000-${index.toString().padLeft(12, '0')}',
)) {
  ChoicePathStepIdDecodingSuccess(:final id) => id,
  InvalidChoicePathStepIdDecoding() => throw StateError('Некорректный ID.'),
};

DailyChoiceCreationFlowSession _session() => DailyChoiceCreationFlowSession(
  rootMatchId: UniqueKey(),
  originalHistory: const [],
);
