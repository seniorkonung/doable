import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_state.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('4097 графем отвергаются вместе с изменённой датой', () {
    final state = DailyChoiceEditState.initial(_choice())
        .withDate(CalendarDate.fromParts(9999, 12, 31))
        .withDescription('е\u0301' * 4097);
    expect(
      state.toPatch,
      throwsA(isA<DailyChoiceDescriptionValidationException>()),
    );
    expect(state.description, 'е\u0301' * 4097);
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
);
