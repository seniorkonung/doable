import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';

/// Кольцо флажка дневного выбора: цвет кольца — приоритет, выполненный выбор
/// заливается серым с галочкой.
///
/// Метка без области нажатия и без собственного имени: нажатие и доступное
/// название, в том числе приоритета, задаёт охватывающий элемент управления.
///
/// P1–P3 рисуют кольцо цвета приоритета с его тоном 12% внутри, P4 — кольцо
/// без тона. У выполненного выбора кольцо и заливка `grip`, галочка цвета
/// плоскости под кольцом, и приоритет в нём уже не виден.
final class ChoiceCheck extends StatelessWidget {
  const ChoiceCheck({
    required this.priority,
    this.done = false,
    this.markColor,
    super.key,
  });

  final DoablePriority priority;

  /// Выбор выполнен.
  final bool done;

  /// Цвет галочки: цвет плоскости под кольцом. Без него `fill`, плоскость
  /// строки списка; в шапке листа плоскость `raised`.
  final Color? markColor;

  static const double _ringWidth = 2;
  static const double _tintAlpha = .12;
  static const double _checkSize = 12;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final ringColor = done ? colors.grip : priority.color(colors);
    final tint = switch ((done, priority)) {
      (true, _) => colors.grip,
      (false, DoablePriority.p4) => null,
      (false, _) => ringColor.withValues(alpha: _tintAlpha),
    };

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: tint,
        shape: CircleBorder(
          side: BorderSide(color: ringColor, width: _ringWidth),
        ),
      ),
      child: SizedBox.square(
        dimension: DoableMetrics.checkSize,
        child: done
            ? Center(
                child: DoableIcon(
                  DoableIconData.check,
                  size: _checkSize,
                  color: markColor ?? colors.fill,
                ),
              )
            : null,
      ),
    );
  }
}
