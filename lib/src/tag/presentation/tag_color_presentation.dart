import '../../design_system/components/tag_dot.dart';
import '../domain/tag_color.dart';

/// Перевод предметного цвета в визуальный вариант дизайн-системы.
DoableTagColor? tagColorPresentation(TagColor? color) => switch (color) {
  null => null,
  TagColor.brown => DoableTagColor.brown,
  TagColor.orange => DoableTagColor.orange,
  TagColor.olive => DoableTagColor.olive,
  TagColor.green => DoableTagColor.green,
  TagColor.teal => DoableTagColor.teal,
  TagColor.blue => DoableTagColor.blue,
  TagColor.violet => DoableTagColor.violet,
  TagColor.purple => DoableTagColor.purple,
  TagColor.pink => DoableTagColor.pink,
};
