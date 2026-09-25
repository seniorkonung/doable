import '../../graph/application/graph_command_result.dart';
import '../domain/tag_id.dart';
import '../domain/tag_name.dart';
import 'tag_result.dart';

/// Команды исполняет общий последовательный исполнитель личного графа.
/// Успех возвращается только после commit; фактическое изменение продвигает
/// общую ревизию ровно один раз, отказ и полное совпадение имени — ни разу.
sealed class TagCommand
    implements GraphCommand<TagCommandSuccess, TagCommandFailure> {
  const TagCommand();
}

final class CreateTag extends TagCommand {
  const CreateTag(this.name);

  final TagName name;
}

final class RenameTag extends TagCommand {
  const RenameTag({required this.tagId, required this.name});

  final TagId tagId;
  final TagName name;
}

/// Подтверждение привязано к id. Исполнение удаляет тег и все его назначения
/// одной транзакцией, включая незагруженные и назначения архивным сущностям.
final class DeleteTag extends TagCommand {
  const DeleteTag(this.tagId);

  final TagId tagId;
}
