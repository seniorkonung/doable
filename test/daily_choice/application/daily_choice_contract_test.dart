import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'предложение требует шаг и сохраняет подтверждённый порядок и смысл',
    () {
      expect(() => ConfirmedChoicePath([]), throwsA(isA<ArgumentError>()));
      final steps = [
        ConfirmedChoicePathStep(
          relationId: _relation1,
          sourceIntentionId: _source,
          type: LongTermRelationType.need,
          relatedIntentionId: _middle,
        ),
        ConfirmedChoicePathStep(
          relationId: _relation2,
          sourceIntentionId: _middle,
          type: LongTermRelationType.can,
          relatedIntentionId: _selected,
        ),
      ];
      final path = ConfirmedChoicePath(steps);
      steps.clear();
      expect(path.steps.map((step) => step.relationId), [
        _relation1,
        _relation2,
      ]);
      expect(path.steps.last.type, LongTermRelationType.can);
      expect(() => path.steps.clear(), throwsUnsupportedError);
    },
  );

  test('сохранённый путь владеет только своими шагами и неизменяем', () {
    final steps = [
      ChoicePathStep(
        id: _step1,
        dailyChoiceId: _choice,
        relationId: _relation1,
        previousStepId: null,
      ),
      ChoicePathStep(
        id: _step2,
        dailyChoiceId: _choice,
        relationId: _relation2,
        previousStepId: _step1,
      ),
    ];
    final path = StoredChoicePath(steps);
    steps.clear();
    expect(path.steps.map((step) => step.id), [_step1, _step2]);
    expect(() => path.steps.clear(), throwsUnsupportedError);
    expect(
      () => StoredChoicePath([
        ChoicePathStep(
          id: _step2,
          dailyChoiceId: _choice,
          relationId: _relation2,
          previousStepId: _step1,
        ),
      ]),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('дневной выбор имеет разных прямых участников и независимые поля', () {
    final choice = DailyChoice(
      id: _choice,
      sourceIntentionId: _source,
      selectedIntentionId: _selected,
      date: CalendarDate.fromParts(2026, 9, 23),
      description: DailyChoiceDescription.fromInput('  Мой выбор  '),
      isCompleted: true,
    );
    expect(choice.description?.value, '  Мой выбор  ');
    expect(choice.isCompleted, isTrue);
    expect(
      () => DailyChoice(
        id: _choice,
        sourceIntentionId: _source,
        selectedIntentionId: _source,
        date: choice.date,
        description: null,
        isCompleted: false,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('команды различают создание, поля, путь и удаление', () {
    final proposed = ConfirmedChoicePath([
      ConfirmedChoicePathStep(
        relationId: _relation1,
        sourceIntentionId: _source,
        type: LongTermRelationType.need,
        relatedIntentionId: _selected,
      ),
    ]);
    final created = CreateDailyChoice(
      sourceIntentionId: _source,
      selectedIntentionId: _selected,
      path: proposed,
      date: CalendarDate.fromParts(2026, 9, 23),
      description: null,
      isCompleted: false,
    );
    expect(created.path, same(proposed));
    expect(created.isCompleted, isFalse);

    const unchanged = DailyChoiceFieldsPatch();
    expect(unchanged.date, isA<DailyChoiceFieldUnchanged<CalendarDate>>());
    expect(unchanged.description, isA<DailyChoiceDescriptionUnchanged>());
    expect(unchanged.isCompleted, isA<DailyChoiceFieldUnchanged<bool>>());
    final clear = UpdateDailyChoiceFields(
      choiceId: _choice,
      patch: const DailyChoiceFieldsPatch(
        description: DailyChoiceDescriptionCleared(),
      ),
    );
    final set = UpdateDailyChoiceFields(
      choiceId: _choice,
      patch: DailyChoiceFieldsPatch(
        description: DailyChoiceDescriptionSet(
          DailyChoiceDescription.fromInput('Текст')!,
        ),
      ),
    );
    expect(clear.patch.description, isA<DailyChoiceDescriptionCleared>());
    expect(set.patch.description, isA<DailyChoiceDescriptionSet>());
    expect(
      ReplaceDailyChoicePath(
        choiceId: _choice,
        sourceIntentionId: _source,
        selectedIntentionId: _selected,
        path: proposed,
      ).path,
      same(proposed),
    );
    expect(DeleteDailyChoice(_choice).choiceId, _choice);
  });

  test('ошибки команд покрывают шесть категорий общего графа', () {
    final failures = <DailyChoiceCommandFailure>[
      const DailyChoiceValidationFailure(DailyChoiceValidationField.path),
      const DailyChoiceNotFoundFailure(),
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.confirmedPathChanged,
      ),
      const DailyChoiceUnavailableFailure(),
      const DailyChoiceCorruptionFailure(),
      const DailyChoiceUnexpectedFailure(),
    ];
    expect(
      failures.map((failure) => failure.category).toSet(),
      GraphFailureCategory.values.toSet(),
    );
  });
}

IntentionId _intention(String uuid) => switch (IntentionId.decode(uuid)) {
  IntentionIdDecodingSuccess(:final id) => id,
  _ => throw StateError('Некорректный UUID.'),
};
LongTermRelationId _relation(String uuid) =>
    switch (LongTermRelationId.decode(uuid)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      _ => throw StateError('Некорректный UUID.'),
    };
DailyChoiceId _dailyChoice(String uuid) => switch (DailyChoiceId.decode(uuid)) {
  DailyChoiceIdDecodingSuccess(:final id) => id,
  _ => throw StateError('Некорректный UUID.'),
};
ChoicePathStepId _pathStep(String uuid) =>
    switch (ChoicePathStepId.decode(uuid)) {
      ChoicePathStepIdDecodingSuccess(:final id) => id,
      _ => throw StateError('Некорректный UUID.'),
    };

final _source = _intention('018f0b5d-6b2e-7c80-8000-000000000001');
final _middle = _intention('018f0b5d-6b2e-7c80-8000-000000000002');
final _selected = _intention('018f0b5d-6b2e-7c80-8000-000000000003');
final _relation1 = _relation('018f0b5d-6b2e-7c80-8000-000000000004');
final _relation2 = _relation('018f0b5d-6b2e-7c80-8000-000000000005');
final _choice = _dailyChoice('018f0b5d-6b2e-7c80-8000-000000000006');
final _step1 = _pathStep('018f0b5d-6b2e-7c80-8000-000000000007');
final _step2 = _pathStep('018f0b5d-6b2e-7c80-8000-000000000008');
