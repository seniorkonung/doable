import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_id.dart';
import '../domain/tag_assignment.dart';

/// Один компактный факт о теге на общей ревизии личного графа.
sealed class TagChange implements GraphChange {
  const TagChange();
}

final class TagCreatedChange extends TagChange {
  const TagCreatedChange({required this.revision, required this.after});

  @override
  final GraphRevision revision;
  final Tag after;
}

enum TagChangeValidationFailure { identityMismatch, nameUnchanged }

final class TagChangeValidationException implements Exception {
  const TagChangeValidationException(this.failure);

  final TagChangeValidationFailure failure;
}

final class TagRenamedChange extends TagChange {
  factory TagRenamedChange({
    required GraphRevision revision,
    required Tag before,
    required Tag after,
  }) {
    if (before.id != after.id) {
      throw const TagChangeValidationException(
        TagChangeValidationFailure.identityMismatch,
      );
    }
    if (before.name == after.name) {
      throw const TagChangeValidationException(
        TagChangeValidationFailure.nameUnchanged,
      );
    }
    return TagRenamedChange._(revision: revision, before: before, after: after);
  }

  const TagRenamedChange._({
    required this.revision,
    required this.before,
    required this.after,
  });

  @override
  final GraphRevision revision;
  final Tag before;
  final Tag after;
}

/// Полное совпадение сохранённого имени подтверждается без новой ревизии.
final class TagUnchangedChange extends TagChange {
  const TagUnchangedChange({required this.revision, required this.tag});

  @override
  final GraphRevision revision;
  final Tag tag;
  Tag get before => tag;
  Tag get after => tag;
}

/// Удаление не перечисляет назначения: охват задаёт TagId на момент commit.
final class TagDeletedChange extends TagChange {
  const TagDeletedChange({required this.revision, required this.tagId});

  @override
  final GraphRevision revision;
  final TagId tagId;
}

/// Подтверждённое состояние пары тега и намерения после назначения или снятия.
enum TagAssignmentState { assigned, absent }

/// Фактическое изменение пары тега и намерения; остальные не перечисляются.
final class TagAssignmentChangedChange extends TagChange {
  const TagAssignmentChangedChange({
    required this.revision,
    required this.assignment,
    required this.state,
  });

  @override
  final GraphRevision revision;
  final TagAssignment assignment;
  final TagAssignmentState state;
}

/// Повтор подтверждает уже существовавшее состояние без новой ревизии.
final class TagAssignmentUnchangedChange extends TagChange {
  const TagAssignmentUnchangedChange({
    required this.revision,
    required this.assignment,
    required this.state,
  });

  @override
  final GraphRevision revision;
  final TagAssignment assignment;
  final TagAssignmentState state;
}
