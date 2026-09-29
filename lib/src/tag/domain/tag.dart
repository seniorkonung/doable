import 'tag_id.dart';
import 'tag_name.dart';

/// Переиспользуемая метка намерений, включая действия.
/// Сам тег существует независимо от назначений и не имеет архивного состояния.
final class Tag {
  const Tag({required this.id, required this.name});

  final TagId id;
  final TagName name;
}
