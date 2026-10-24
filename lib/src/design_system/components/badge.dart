import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';

/// Тон иконки метки: `muted` — у коробки архива и у молнии архивированного
/// действия.
enum BadgeTone { ink, muted }

/// Метка рядом с названием, которая сообщает факт и не является кнопкой.
final class Badge extends StatelessWidget {
  /// Метка-значок строки списка на заливке `fill`, поэтому её фон — `bg`.
  /// Узла экранного диктора у метки нет: факт называет доступное название
  /// строки.
  const Badge.mark({required this.icon, required this.tone, super.key});

  final DoableIconData icon;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return SizedBox(
      width: 22,
      height: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        ),
        child: Center(
          child: DoableIcon(
            icon,
            size: 14,
            color: switch (tone) {
              BadgeTone.ink => colors.ink,
              BadgeTone.muted => colors.muted,
            },
          ),
        ),
      ),
    );
  }
}
