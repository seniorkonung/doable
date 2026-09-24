import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_state.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'явная дата охватывает весь календарь; прошлая не включает выполнение',
    () {
      final harness = _Harness(date: CalendarDate.fromParts(1, 1, 1));
      addTearDown(harness.dispose);

      expect(harness.state.date, CalendarDate.fromParts(1, 1, 1));
      expect(harness.state.isCompleted, isFalse);
      expect(harness.state.path, same(harness.path));
      harness.model.changeCompletion(true);
      expect(harness.state.date, CalendarDate.fromParts(1, 1, 1));
      expect(harness.state.isCompleted, isTrue);
      harness.model.changeDate(CalendarDate.fromParts(9999, 12, 31));
      harness.model.submit();

      expect(
        harness.repository.commands.single.date,
        CalendarDate.fromParts(9999, 12, 31),
      );
      expect(harness.repository.commands.single.isCompleted, isTrue);
      expect(harness.repository.commands.single.path, same(harness.path));
    },
  );

  test('описание проверяется по Unicode и графемам с сохранением ввода', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final grapheme = 'е\u0301';
    harness.model.changeDescription(grapheme * 4097);
    harness.model.submit();

    expect(harness.repository.commands, isEmpty);
    expect(harness.state.description, grapheme * 4097);
    expect(
      harness.state.operation,
      isA<DailyChoiceCreationFailed>().having(
        (value) => value.failure,
        'причина',
        isA<DailyChoiceCreationDescriptionInvalid>().having(
          (value) => value.failure.reason,
          'ограничение',
          DailyChoiceDescriptionValidationReason.tooLong,
        ),
      ),
    );

    harness.model.changeDescription('текст\u0000');
    harness.model.submit();
    expect(harness.repository.commands, isEmpty);
    expect(harness.state.description, 'текст\u0000');
    expect(
      ((harness.state.operation as DailyChoiceCreationFailed).failure
              as DailyChoiceCreationDescriptionInvalid)
          .failure
          .reason,
      DailyChoiceDescriptionValidationReason.invalidUnicodeRepertoire,
    );

    harness.model.changeDescription(grapheme * 4096);
    harness.model.submit();
    expect(
      harness.repository.commands.single.description?.value,
      grapheme * 4096,
    );
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
    'одна форма отправляет один раз и узнаёт об успехе после commit',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final presenter = harness.coordinator.registerAppPresentation();
      addTearDown(presenter.release);

      harness.model
        ..submit()
        ..submit();
      expect(harness.repository.commands, hasLength(1));
      expect(harness.state.operation, isA<DailyChoiceCreationSubmitting>());
      expect(harness.state.event, isNull);

      harness.repository.succeed(0);
      await pumpEventQueue();
      expect(harness.state.operation, isA<DailyChoiceCreationSucceeded>());
      expect(harness.state.event, isA<DailyChoiceCreationCreated>());
      expect(harness.state.failurePresentation, isNull);
      harness.model.submit();
      expect(harness.repository.commands, hasLength(1));
      final claim = await presenter.nextClaim();
      expect(claim?.completion, isA<DailyChoiceCommandCompletion>());
      harness.coordinator.confirmPresentation(claim!);
      harness.model.consumeEvent();
      expect(harness.state.event, isNull);
    },
  );

  test('новая форма допускает полный самостоятельный дубликат', () {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    addTearDown(container.dispose);
    final path = _path();
    final date = CalendarDate.fromParts(2024, 1, 1);
    final first = dailyChoiceCreationViewModelProvider(
      DailyChoiceCreationFormKey(),
      path,
      date,
    );
    final second = dailyChoiceCreationViewModelProvider(
      DailyChoiceCreationFormKey(),
      path,
      date,
    );
    final a = container.listen(first, (_, _) {});
    final b = container.listen(second, (_, _) {});
    addTearDown(a.close);
    addTearDown(b.close);

    container.read(first.notifier)
      ..changeDescription('Одинаковое описание')
      ..changeCompletion(true)
      ..submit();
    container.read(second.notifier)
      ..changeDescription('Одинаковое описание')
      ..changeCompletion(true)
      ..submit();
    expect(repository.commands, hasLength(2));
    expect(repository.commands[0].path, same(path));
    expect(repository.commands[1].path, same(path));
    expect(repository.commands[0].date, date);
    expect(repository.commands[1].date, date);
    expect(repository.commands[0].description?.value, 'Одинаковое описание');
    expect(repository.commands[1].description?.value, 'Одинаковое описание');
    expect(repository.commands[0].isCompleted, isTrue);
    expect(repository.commands[1].isCompleted, isTrue);
  });

  test(
    'тот же ключ блокирует отправку после пересоздания формы во время записи',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);
      final key = DailyChoiceCreationFormKey();
      final path = _path();
      final date = CalendarDate.fromParts(2024, 1, 1);
      final provider = dailyChoiceCreationViewModelProvider(key, path, date);
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
    expect(
      harness.state.failurePresentation,
      isA<GraphInitiatorPresentationClaim>(),
    );
    harness.model.changeDate(CalendarDate.fromParts(2024, 3, 2));
    harness.model.submit();
    expect(harness.repository.commands, hasLength(1));

    final refreshed = _path(type: LongTermRelationType.can);
    harness.model.confirmRefreshedPath(refreshed);
    expect(harness.state.canSubmit, isTrue);
    harness.model.submit();
    expect(harness.repository.commands, hasLength(2));
    expect(harness.repository.commands.last.path, same(refreshed));
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
      expect(
        harness.state.failurePresentation,
        isA<GraphInitiatorPresentationClaim>(),
      );
      harness.model.submit();
      expect(harness.repository.commands, hasLength(2));
      harness.repository.fail(1, const DailyChoiceUnexpectedFailure());
      await pumpEventQueue();
      expect(harness.state.canSubmit, isFalse);
      expect(harness.state.description, isEmpty);
    },
  );

  test(
    'повтор передаёт исправленное описание после временного отказа',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final presenter = harness.coordinator.registerAppPresentation();
      addTearDown(presenter.release);

      harness.model
        ..changeDescription('Первый текст')
        ..submit()
        ..submit()
        ..changeDescription('Недопустимая правка');
      expect(harness.repository.commands, hasLength(1));
      expect(harness.state.description, 'Первый текст');
      expect(
        harness.repository.commands.single.description?.value,
        'Первый текст',
      );

      harness.repository.fail(0, const DailyChoiceUnavailableFailure());
      await pumpEventQueue();
      expect(harness.state.description, 'Первый текст');
      expect(harness.state.canRetry, isTrue);
      expect(
        harness.state.failurePresentation,
        isA<GraphInitiatorPresentationClaim>(),
      );

      harness.model.changeDescription('Исправленный текст');
      expect(harness.state.description, 'Исправленный текст');
      harness.model.submit();
      expect(harness.repository.commands, hasLength(2));
      expect(
        harness.repository.commands.last.description?.value,
        'Исправленный текст',
      );
      harness.repository.succeed(1);
      await pumpEventQueue();
      expect(harness.state.operation, isA<DailyChoiceCreationSucceeded>());
      final claim = await presenter.nextClaim();
      expect(claim?.completion, isA<DailyChoiceCommandCompletion>());
      harness.coordinator.confirmPresentation(claim!);
      expect(harness.repository.commands, hasLength(2));
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
    expect(
      harness.state.failurePresentation,
      isA<GraphInitiatorPresentationClaim>(),
    );

    harness.model.changeDate(CalendarDate.fromParts(9999, 12, 31));
    expect(harness.state.canSubmit, isTrue);
    expect(harness.state.description, 'Оставить описание');
    harness.model.submit();
    expect(
      harness.repository.commands.last.date,
      CalendarDate.fromParts(9999, 12, 31),
    );
  });

  test('уход формы не отменяет команду и передаёт ошибку оболочке', () async {
    final harness = _Harness();
    final presenter = harness.coordinator.registerAppPresentation();
    addTearDown(presenter.release);
    harness.model.submit();
    harness.closeForm();
    harness.repository.fail(0, const DailyChoiceUnexpectedFailure());
    final claim = await presenter.nextClaim();
    expect(claim?.completion, isA<DailyChoiceCommandCompletion>());
    harness.coordinator.confirmPresentation(claim!);
    harness.dispose();
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
      DailyChoiceCreationFormKey(),
      path,
      date ?? CalendarDate.fromParts(2024, 1, 1),
    );
    subscription = container.listen(provider, (_, _) {});
  }

  final _Repository repository;
  final ConfirmedChoicePath path;
  late final ProviderContainer container;
  late final DailyChoiceCreationViewModelProvider provider;
  late final ProviderSubscription<DailyChoiceCreationState> subscription;
  DailyChoiceCreationViewModel get model => container.read(provider.notifier);
  DailyChoiceCreationState get state => container.read(provider);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  void closeForm() => subscription.close();
  void dispose() => container.dispose();
}

final class _Repository implements PersonalGraphRepository {
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
