import '../../graph/application/graph_command_result.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/tag_color.dart';
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

/// Место нового тега в ручном порядке задаётся соседом, а не ключом:
/// ключ вычисляет запись по соседям, прочитанным в той же транзакции.
sealed class TagPlacement {
  const TagPlacement();

  static const first = FirstTagPlacement();
}

/// Перед текущим первым тегом каталога.
final class FirstTagPlacement extends TagPlacement {
  const FirstTagPlacement();
}

/// Сразу после тега [tagId] и перед следующим за ним.
final class AfterTagPlacement extends TagPlacement {
  const AfterTagPlacement(this.tagId);

  final TagId tagId;
}

final class CreateTag extends TagLifecycleCommand {
  const CreateTag({
    required this.name,
    required this.color,
    required this.placement,
  });

  final TagName name;
  final TagColor? color;
  final TagPlacement placement;
}

/// Задаёт полное новое редактируемое состояние тега: название и цвет
/// сохраняются вместе, `null` возвращает тег к состоянию «Без цвета».
final class UpdateTag extends TagLifecycleCommand {
  const UpdateTag({
    required this.tagId,
    required this.name,
    required this.color,
  });

  final TagId tagId;
  final TagName name;
  final TagColor? color;
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
