import 'package:flutter/painting.dart';

import 'doable_colors.dart';

/// Приоритет P1–P4 для компонентов дизайн-системы.
///
/// Перечисление само выбирает цвет приоритета, поэтому компоненты не
/// повторяют это сопоставление. Предметный приоритет переводит в него
/// потребитель на границе экрана.
enum DoablePriority {
  p1,
  p2,
  p3,
  p4;

  /// Цвет приоритета в палитре [colors].
  Color color(DoableColors colors) => switch (this) {
    p1 => colors.p1,
    p2 => colors.p2,
    p3 => colors.p3,
    p4 => colors.p4,
  };
}
