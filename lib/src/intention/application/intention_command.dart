import '../../graph/application/graph_command_result.dart';
import '../../tag/domain/tag_id.dart';
import '../domain/intention.dart';
import '../domain/intention_id.dart';
import 'intention_catalog.dart';
import 'intention_result.dart';

sealed class IntentionCommand
    implements GraphCommand<IntentionCommandSuccess, IntentionFailure> {
  const IntentionCommand();
}

/// Создаёт новое активное намерение вместе с его полным начальным состоянием.
///
/// Намерение, назначения всех тегов [tagIds] и отметка избранного
/// сохраняются одной атомарной операцией с начальной готовностью
/// [readiness]: при любом отказе не остаётся ни намерения, ни части его
/// назначений, ни отметки или места в порядке избранных. Успех подтверждается
/// одним [IntentionSaved] по правилам результата создания.
///
/// Выбранные теги определяются только идентификаторами. Если хотя бы один из
/// них отсутствует на момент атомарной проверки, всё создание отклоняется
/// [IntentionCreationTagsMissingFailure] без пропуска тега и без подмены его
/// одноимённым.
///
/// Принятую отправку до результата удерживает координатор команд графа:
/// уход инициатора не отменяет и не повторяет её.
final class CreateIntention extends IntentionCommand {
  /// Минимальные данные: намерение создаётся неготовым, без отметки
  /// избранного и без тегов.
  const CreateIntention({required this.title, required this.description})
    : readiness = IntentionReadiness.notReady,
      favoriteMark = FavoriteMark.notFavorite,
      tagIds = const {};

  /// Полное начальное состояние, подготовленное до создания намерения.
  ///
  /// Команда хранит собственную неизменяемую копию [tagIds]: изменение
  /// переданной коллекции не меняет уже созданную команду, а повторы одного
  /// идентификатора дают одно назначение.
  CreateIntention.withInitialState({
    required this.title,
    required this.description,
    required this.readiness,
    required this.favoriteMark,
    required Iterable<TagId> tagIds,
  }) : tagIds = Set.unmodifiable(tagIds);

  final String title;
  final String? description;

  /// Начальная готовность к действию, выбранная явным решением человека.
  final IntentionReadiness readiness;

  /// Начальная отметка избранного. Отмеченное намерение занимает последнее
  /// место всего порядка избранных на момент сохранения.
  final FavoriteMark favoriteMark;

  /// Неизменяемый набор тегов будущих назначений; пустой набор означает
  /// создание без тегов.
  final Set<TagId> tagIds;
}

sealed class ExistingIntentionCommand extends IntentionCommand {
  const ExistingIntentionCommand(this.id);

  final IntentionId id;
}

final class UpdateIntention extends ExistingIntentionCommand {
  const UpdateIntention({
    required IntentionId id,
    required this.title,
    required this.description,
  }) : super(id);

  final String title;
  final String? description;
}

final class EnableIntentionReadiness extends ExistingIntentionCommand {
  const EnableIntentionReadiness(super.id);
}

final class DisableIntentionReadiness extends ExistingIntentionCommand {
  const DisableIntentionReadiness(super.id);
}

final class ArchiveIntention extends ExistingIntentionCommand {
  const ArchiveIntention(super.id);
}

final class RestoreIntention extends ExistingIntentionCommand {
  const RestoreIntention(super.id);
}

final class DeleteIntention extends ExistingIntentionCommand {
  const DeleteIntention(super.id);
}

/// Отмечает намерение избранным. Отметка уже избранного намерения успешно
/// оставляет одну отметку и прежнее место в порядке избранных.
final class MarkIntentionFavorite extends ExistingIntentionCommand {
  const MarkIntentionFavorite(super.id);
}

/// Снимает отметку избранного намерения. Снятие отсутствующей отметки
/// успешно оставляет намерение без отметки.
final class UnmarkIntentionFavorite extends ExistingIntentionCommand {
  const UnmarkIntentionFavorite(super.id);
}
