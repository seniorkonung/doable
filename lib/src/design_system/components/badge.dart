import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Тон иконки метки: `muted` — у коробки архива и у молнии архивированного
/// действия.
enum BadgeTone { ink, muted }

/// Метка рядом с названием, которая сообщает факт и не является кнопкой.
final class Badge extends StatelessWidget {
  /// Метка-значок строки списка на заливке `fill`, поэтому её фон — `bg`.
  /// Узла экранного диктора у метки нет: факт называет доступное название
  /// строки.
  const Badge.mark({required this.icon, required this.tone, super.key})
    : word = null;

  /// Метка «Архив» после названия: слово [word] цвета `muted` на плоскости
  /// `fill` за коробкой архива. Диктор читает слово.
  const Badge.archived({required String this.word, super.key})
    : icon = DoableIconData.archive,
      tone = BadgeTone.muted;

  final DoableIconData icon;
  final BadgeTone tone;

  /// Слово метки; без него метка — значок без слова.
  final String? word;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final word = this.word;
    if (word != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 1, 7, 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DoableMetrics.space1,
            children: [
              DoableIcon(icon, size: 13, color: colors.muted),
              Text(
                word,
                maxLines: 1,
                softWrap: false,
                style: DoableType.caption.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      );
    }

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
