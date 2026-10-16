import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('весь день отличается от полуночи и границы времени допустимы', () {
    const DailyChoiceSchedule allDay = DailyChoiceAllDay();
    final midnight = DailyChoiceTime(hour: 0, minute: 0);
    final endOfDay = DailyChoiceTime(hour: 23, minute: 59);
    final evening = DailyChoiceTime(hour: 18, minute: 37);

    expect(midnight, isNot(allDay));
    expect(midnight.minuteOfDay, 0);
    expect(endOfDay.minuteOfDay, 1439);
    expect(evening.minuteOfDay, 1117);
  });

  test('конкретное время не нормализует недопустимые часы и минуты', () {
    for (final (hour, minute) in [(-1, 0), (24, 0), (0, -1), (0, 60)]) {
      expect(
        () => DailyChoiceTime(hour: hour, minute: minute),
        throwsRangeError,
        reason: 'Недопустимое время: $hour:$minute',
      );
    }
  });

  test('создание принимает время и приоритет с независимыми значениями по умолчанию', () {
    final path = ConfirmedChoicePath([
      ConfirmedChoicePathStep(
        relationId: _relation1,
        sourceIntentionId: _source,
        type: LongTermRelationType.need,
        relatedIntentionId: _selected,
      ),
    ]);
    final defaultCommand = CreateDailyChoice(
      sourceIntentionId: _source,
      selectedIntentionId: _selected,
      path: path,
      date: CalendarDate.fromParts(2026, 10, 16),
      description: null,
      isCompleted: false,
    );
    final plannedCommand = CreateDailyChoice(
      sourceIntentionId: _source,
      selectedIntentionId: _selected,
      path: path,
      date: defaultCommand.date,
      schedule: DailyChoiceTime(hour: 18, minute: 0),
      priority: DailyChoicePriority.p2,
      description: null,
      isCompleted: false,
    );

    expect(defaultCommand.schedule, const DailyChoiceAllDay());
    expect(defaultCommand.priority, DailyChoicePriority.p4);
    expect(plannedCommand.schedule, DailyChoiceTime(hour: 18, minute: 0));
    expect(plannedCommand.priority, DailyChoicePriority.p2);
  });

  test('установка всего дня отличается от отсутствия правки времени', () {
    const unchanged = DailyChoiceFieldsPatch();
    const allDay = DailyChoiceFieldsPatch(
      schedule: DailyChoiceFieldSet(DailyChoiceAllDay()),
    );
    const priorityOnly = DailyChoiceFieldsPatch(
      priority: DailyChoiceFieldSet(DailyChoicePriority.p1),
    );

    expect(
      unchanged.schedule,
      isA<DailyChoiceFieldUnchanged<DailyChoiceSchedule>>(),
    );
    expect(
      allDay.schedule,
      isA<DailyChoiceFieldSet<DailyChoiceSchedule>>().having(
        (patch) => patch.value,
        'новое время',
        const DailyChoiceAllDay(),
      ),
    );
    expect(
      allDay.priority,
      isA<DailyChoiceFieldUnchanged<DailyChoicePriority>>(),
    );
    expect(allDay.date, isA<DailyChoiceFieldUnchanged<CalendarDate>>());
    expect(allDay.description, isA<DailyChoiceDescriptionUnchanged>());
    expect(allDay.isCompleted, isA<DailyChoiceFieldUnchanged<bool>>());
    expect(
      priorityOnly.schedule,
      isA<DailyChoiceFieldUnchanged<DailyChoiceSchedule>>(),
    );
  });

  test('предложение сохраняет подтверждённый порядок и смысл', () {
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
    expect(path.steps.map((step) => step.relationId), [_relation1, _relation2]);
    expect(path.steps.last.type, LongTermRelationType.can);
  });

  test(
    'сохранённый путь копирует переданные шаги и проверяет их связность',
    () {
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
    },
  );

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
    expect(choice.schedule, const DailyChoiceAllDay());
    expect(choice.priority, DailyChoicePriority.p4);
    final plannedChoice = DailyChoice(
      id: choice.id,
      sourceIntentionId: choice.sourceIntentionId,
      selectedIntentionId: choice.selectedIntentionId,
      date: choice.date,
      schedule: DailyChoiceTime(hour: 18, minute: 0),
      priority: DailyChoicePriority.p2,
      description: choice.description,
      isCompleted: choice.isCompleted,
    );
    expect(plannedChoice.schedule, DailyChoiceTime(hour: 18, minute: 0));
    expect(plannedChoice.priority, DailyChoicePriority.p2);
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
