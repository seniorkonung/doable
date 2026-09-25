import '../../graph/application/graph_command_result.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/calendar_date.dart';
import '../domain/daily_choice_description.dart';
import '../domain/daily_choice_id.dart';
import 'confirmed_choice_path.dart';
import 'daily_choice_result.dart';

/// Исполняется через общий последовательный исполнитель графа. Создание и
/// замена проверяют весь подтверждённый путь на актуальном снимке и сохраняют
/// его одной транзакцией. Правка полей проверяет целостность существующего
/// выбора, но не требует повторной допустимости уже сохранённого пути.
/// Удаление затрагивает только выбранную запись и принадлежащие ей шаги.
sealed class DailyChoiceCommand
    implements
        GraphCommand<DailyChoiceCommandSuccess, DailyChoiceCommandFailure> {
  const DailyChoiceCommand();
}

final class CreateDailyChoice extends DailyChoiceCommand {
  factory CreateDailyChoice({
    required IntentionId sourceIntentionId,
    required IntentionId selectedIntentionId,
    required ConfirmedChoicePath path,
    required CalendarDate date,
    required DailyChoiceDescription? description,
    required bool isCompleted,
  }) {
    if (sourceIntentionId == selectedIntentionId) {
      throw ArgumentError.value(selectedIntentionId, 'selectedIntentionId');
    }
    return CreateDailyChoice._(
      sourceIntentionId: sourceIntentionId,
      selectedIntentionId: selectedIntentionId,
      path: path,
      date: date,
      description: description,
      isCompleted: isCompleted,
    );
  }

  const CreateDailyChoice._({
    required this.sourceIntentionId,
    required this.selectedIntentionId,
    required this.path,
    required this.date,
    required this.description,
    required this.isCompleted,
  });

  final IntentionId sourceIntentionId;
  final IntentionId selectedIntentionId;
  final ConfirmedChoicePath path;
  final CalendarDate date;
  final DailyChoiceDescription? description;
  final bool isCompleted;
}

sealed class DailyChoiceFieldPatch<T extends Object> {
  const DailyChoiceFieldPatch();
}

final class DailyChoiceFieldUnchanged<T extends Object>
    extends DailyChoiceFieldPatch<T> {
  const DailyChoiceFieldUnchanged();
}

final class DailyChoiceFieldSet<T extends Object>
    extends DailyChoiceFieldPatch<T> {
  const DailyChoiceFieldSet(this.value);

  final T value;
}

sealed class DailyChoiceDescriptionPatch {
  const DailyChoiceDescriptionPatch();
}

final class DailyChoiceDescriptionUnchanged
    extends DailyChoiceDescriptionPatch {
  const DailyChoiceDescriptionUnchanged();
}

final class DailyChoiceDescriptionCleared extends DailyChoiceDescriptionPatch {
  const DailyChoiceDescriptionCleared();
}

final class DailyChoiceDescriptionSet extends DailyChoiceDescriptionPatch {
  const DailyChoiceDescriptionSet(this.value);

  final DailyChoiceDescription value;
}

final class DailyChoiceFieldsPatch {
  const DailyChoiceFieldsPatch({
    this.date = const DailyChoiceFieldUnchanged<CalendarDate>(),
    this.description = const DailyChoiceDescriptionUnchanged(),
    this.isCompleted = const DailyChoiceFieldUnchanged<bool>(),
  });

  final DailyChoiceFieldPatch<CalendarDate> date;
  final DailyChoiceDescriptionPatch description;
  final DailyChoiceFieldPatch<bool> isCompleted;
}

final class UpdateDailyChoiceFields extends DailyChoiceCommand {
  const UpdateDailyChoiceFields({required this.choiceId, required this.patch});

  final DailyChoiceId choiceId;
  final DailyChoiceFieldsPatch patch;
}

final class ReplaceDailyChoicePath extends DailyChoiceCommand {
  factory ReplaceDailyChoicePath({
    required DailyChoiceId choiceId,
    required IntentionId sourceIntentionId,
    required IntentionId selectedIntentionId,
    required ConfirmedChoicePath path,
  }) {
    if (sourceIntentionId == selectedIntentionId) {
      throw ArgumentError.value(selectedIntentionId, 'selectedIntentionId');
    }
    return ReplaceDailyChoicePath._(
      choiceId: choiceId,
      sourceIntentionId: sourceIntentionId,
      selectedIntentionId: selectedIntentionId,
      path: path,
    );
  }

  const ReplaceDailyChoicePath._({
    required this.choiceId,
    required this.sourceIntentionId,
    required this.selectedIntentionId,
    required this.path,
  });

  final DailyChoiceId choiceId;
  final IntentionId sourceIntentionId;
  final IntentionId selectedIntentionId;
  final ConfirmedChoicePath path;
}

final class DeleteDailyChoice extends DailyChoiceCommand {
  const DeleteDailyChoice(this.choiceId);

  final DailyChoiceId choiceId;
}
