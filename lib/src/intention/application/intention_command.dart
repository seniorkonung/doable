import '../../graph/application/graph_command_result.dart';
import '../../tag/domain/tag_id.dart';
import '../domain/intention.dart';
import '../domain/intention_id.dart';
import 'cascade/intention_cascade.dart';
import 'intention_catalog.dart';
import 'intention_result.dart';

sealed class IntentionCommand
    implements GraphCommand<IntentionCommandSuccess, IntentionFailure> {
  const IntentionCommand();
}

/// Создаёт новое активное намерение вместе с его полным начальным состоянием.
///
/// Намерение создаётся главным. Оно и назначения всех тегов [tagIds]
/// сохраняются одной атомарной операцией: при любом отказе не остаётся ни
/// намерения, ни части его назначений. Успех подтверждается одним [IntentionSaved] по правилам
/// результата создания.
///
/// Выбранные теги определяются только идентификаторами. Если хотя бы один из
/// них отсутствует на момент атомарной проверки, всё создание отклоняется
/// [IntentionCreationTagsMissingFailure] без пропуска тега и без подмены его
/// одноимённым.
///
/// Принятую отправку до результата удерживает координатор команд графа:
/// уход инициатора не отменяет и не повторяет её.
final class CreateIntention extends IntentionCommand {
  /// Минимальные данные: намерение создаётся без тегов.
  const CreateIntention({required this.title, required this.description})
    : tagIds = const {};

  /// Полное начальное состояние, подготовленное до создания намерения.
  ///
  /// Команда хранит собственную неизменяемую копию [tagIds]: изменение
  /// переданной коллекции не меняет уже созданную команду, а повторы одного
  /// идентификатора дают одно назначение.
  CreateIntention.withInitialState({
    required this.title,
    required this.description,
    required Iterable<TagId> tagIds,
  }) : tagIds = Set.unmodifiable(tagIds);

  final String title;
  final String? description;

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

final class ChangeIntentionKind extends ExistingIntentionCommand {
  const ChangeIntentionKind(super.id, this.kind);

  final IntentionKind kind;
}

/// Архивирует намерение по варианту [execution] (D7, ADR-0057).
final class ArchiveIntention extends ExistingIntentionCommand {
  const ArchiveIntention(super.id, {required this.execution});

  final CascadeExecution<ArchiveCascadeComposition> execution;
}

/// Восстанавливает намерение по варианту [execution] (D7, ADR-0057).
final class RestoreIntention extends ExistingIntentionCommand {
  const RestoreIntention(super.id, {required this.execution});

  final CascadeExecution<RestoreCascadeComposition> execution;
}

/// Удаляет намерение по варианту [execution] (D7, ADR-0057).
final class DeleteIntention extends ExistingIntentionCommand {
  const DeleteIntention(super.id, {required this.execution});

  final CascadeExecution<DeleteCascadeComposition> execution;
}
