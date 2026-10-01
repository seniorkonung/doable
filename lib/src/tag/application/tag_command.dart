import '../../graph/application/graph_command_result.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/tag_id.dart';
import '../domain/tag_assignment.dart';
import '../domain/tag_name.dart';
import 'tag_result.dart';

/// Команды исполняет общий последовательный исполнитель личного графа.
/// Успех возвращается только после commit; фактическое изменение продвигает
/// общую ревизию ровно один раз, отказ и повтор без изменения — ни разу.
sealed class TagCommand
    implements GraphCommand<TagCommandSuccess, TagCommandFailure> {
  const TagCommand();
}

/// Команды самостоятельного жизненного цикла тега.
sealed class TagLifecycleCommand extends TagCommand {
  const TagLifecycleCommand();
}

final class CreateTag extends TagLifecycleCommand {
  const CreateTag(this.name);

  final TagName name;
}

final class RenameTag extends TagLifecycleCommand {
  const RenameTag({required this.tagId, required this.name});

  final TagId tagId;
  final TagName name;
}

/// Подтверждение привязано к id. Исполнение удаляет тег и все его назначения
/// одной транзакцией, включая незагруженные и назначения архивным намерениям.
final class DeleteTag extends TagLifecycleCommand {
  const DeleteTag(this.tagId);

  final TagId tagId;
}

/// Назначение относится только к указанным существующим тегу и намерению.
/// Намерение допустимо в обоих архивных состояниях, включая действие.
final class AssignTag extends TagCommand {
  const AssignTag({required this.tagId, required this.intentionId});

  final TagId tagId;
  final IntentionId intentionId;

  TagAssignment get assignment =>
      TagAssignment(tagId: tagId, intentionId: intentionId);
}

/// Снятие указанной пары тега и намерения сохраняет сам тег и другие назначения.
final class RemoveTagAssignment extends TagCommand {
  const RemoveTagAssignment({required this.tagId, required this.intentionId});

  final TagId tagId;
  final IntentionId intentionId;

  TagAssignment get assignment =>
      TagAssignment(tagId: tagId, intentionId: intentionId);
}
