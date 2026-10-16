import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_state.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('редактор начинает с сохранённых времени и приоритета без правки', () {
    final state = DailyChoiceEditState.initial(_choice());
    expect(state.schedule, DailyChoiceTime(hour: 18, minute: 0));
    expect(state.priority, DailyChoicePriority.p2);
    expect(state.hasEdits, isFalse);
    expect(state.canSubmit, isFalse);
    expect(state.toPatch(), isNull);
  });

  test('правка описания не отправляет остальные поля', () {
    final state = DailyChoiceEditState.initial(_choice())
        .withDescription('Новый текст');
    final patch = state.toPatch()!;
    expect(patch.description, isA<DailyChoiceDescriptionSet>());
    expect(patch.date, isA<DailyChoiceFieldUnchanged<CalendarDate>>());
    expect(patch.isCompleted, isA<DailyChoiceFieldUnchanged<bool>>());
    expect(
      patch.schedule,
      isA<DailyChoiceFieldUnchanged<DailyChoiceSchedule>>(),
    );
    expect(
      patch.priority,
      isA<DailyChoiceFieldUnchanged<DailyChoicePriority>>(),
    );
  });

  for (final (label, schedule) in <(String, DailyChoiceSchedule)>[
    ('19:30', DailyChoiceTime(hour: 19, minute: 30)),
    ('весь день', const DailyChoiceAllDay()),
  ]) {
    test('правка времени на $label отправляет только время', () {
      final state = DailyChoiceEditState.initial(_choice())
          .withSchedule(schedule);
      final patch = state.toPatch()!;
      expect(state.hasEdits, isTrue);
      expect(state.canSubmit, isTrue);
      expect(
        (patch.schedule as DailyChoiceFieldSet<DailyChoiceSchedule>).value,
        schedule,
      );
      expect(
        patch.priority,
        isA<DailyChoiceFieldUnchanged<DailyChoicePriority>>(),
      );
      expect(patch.date, isA<DailyChoiceFieldUnchanged<CalendarDate>>());
      expect(patch.description, isA<DailyChoiceDescriptionUnchanged>());
      expect(patch.isCompleted, isA<DailyChoiceFieldUnchanged<bool>>());
    });
  }

  test('правка приоритета не отправляет остальные поля', () {
    final state = DailyChoiceEditState.initial(_choice())
        .withPriority(DailyChoicePriority.p1);
    final patch = state.toPatch()!;
    expect(state.hasEdits, isTrue);
    expect(state.canSubmit, isTrue);
    expect(
      (patch.priority as DailyChoiceFieldSet<DailyChoicePriority>).value,
      DailyChoicePriority.p1,
    );
    expect(
      patch.schedule,
      isA<DailyChoiceFieldUnchanged<DailyChoiceSchedule>>(),
    );
    expect(patch.date, isA<DailyChoiceFieldUnchanged<CalendarDate>>());
    expect(patch.description, isA<DailyChoiceDescriptionUnchanged>());
    expect(patch.isCompleted, isA<DailyChoiceFieldUnchanged<bool>>());
  });

  test('возврат исходных времени и приоритета снимает правку', () {
    final state = DailyChoiceEditState.initial(_choice())
        .withSchedule(const DailyChoiceAllDay())
        .withPriority(DailyChoicePriority.p4)
        .withSchedule(DailyChoiceTime(hour: 18, minute: 0))
        .withPriority(DailyChoicePriority.p2);
    expect(state.hasEdits, isFalse);
    expect(state.canSubmit, isFalse);
    expect(state.toPatch(), isNull);
  });

  test('правка даты не посылает описание и выполнение', () {
    final state = DailyChoiceEditState.initial(_choice())
        .withDate(CalendarDate.fromParts(1, 1, 1));
    final patch = state.toPatch();
    expect(patch?.date, isA<DailyChoiceFieldSet<CalendarDate>>());
    expect(patch?.description, isA<DailyChoiceDescriptionUnchanged>());
    expect(patch?.isCompleted, isA<DailyChoiceFieldUnchanged<bool>>());
  });

  test('пробельное описание явно очищает поле', () {
    final patch = DailyChoiceEditState.initial(_choice())
        .withDescription('  \n ')
        .toPatch();
    expect(patch?.date, isA<DailyChoiceFieldUnchanged<CalendarDate>>());
    expect(patch?.description, isA<DailyChoiceDescriptionCleared>());
  });

  test('повтор исходных значений не создаёт команду', () {
    final state = DailyChoiceEditState.initial(_choice())
        .withCompletion(false)
        .withDescription('Исходный текст');
    expect(state.toPatch(), isNull);
  });
}

DailyChoice _choice() => DailyChoice(
  id: (DailyChoiceId.decode(
    '018f1400-0000-7000-8000-000000000001',
  ) as DailyChoiceIdDecodingSuccess).id,
  sourceIntentionId: (IntentionId.decode(
    '018f1200-0000-7000-8000-000000000001',
  ) as IntentionIdDecodingSuccess).id,
  selectedIntentionId: (IntentionId.decode(
    '018f1200-0000-7000-8000-000000000002',
  ) as IntentionIdDecodingSuccess).id,
  date: CalendarDate.fromParts(2026, 9, 24),
  description: DailyChoiceDescription.fromInput('Исходный текст'),
  isCompleted: false,
  schedule: DailyChoiceTime(hour: 18, minute: 0),
  priority: DailyChoicePriority.p2,
);
