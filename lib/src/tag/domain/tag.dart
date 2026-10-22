import 'tag_color.dart';
import 'tag_id.dart';
import 'tag_name.dart';
import 'tag_position.dart';

/// Переиспользуемая метка намерений, включая действия.
/// Сам тег существует независимо от назначений и не имеет архивного состояния.
final class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.color,
    required this.position,
  });

  final TagId id;
  final TagName name;

  /// Общий для всех назначений тега; `null` — «Без цвета».
  final TagColor? color;

  /// Место в едином ручном порядке тегов.
  final TagPosition position;
}
