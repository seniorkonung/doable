import 'tag_id.dart';
import 'tag_target.dart';

final class TagAssignment {
  const TagAssignment({required this.tagId, required this.target});

  final TagId tagId;
  final TagTarget target;

  @override
  bool operator ==(Object other) =>
      other is TagAssignment && other.tagId == tagId && other.target == target;

  @override
  int get hashCode => Object.hash(tagId, target);
}
