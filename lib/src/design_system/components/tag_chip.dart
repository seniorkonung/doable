import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'tag_dot.dart';

/// Тег в строке списка: точка цвета и название в одну строку. Чип не кнопка:
/// нажатие принадлежит строке, которая его показывает.
final class TagChip extends StatelessWidget {
  /// Малый чип на заливке `fill` строки, поэтому его фон — `bg`.
  const TagChip.small({
    required this.name,
    required this.color,
    this.strong = false,
    super.key,
  });

  final String name;
  final DoableTagColor? color;

  /// Название цвета `ink` у тега, которого требует фильтр.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          7,
          1,
          DoableMetrics.space2,
          1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TagDot(color: color, size: TagDotSize.small),
            const SizedBox(width: 5),
            // Слишком широкое название обрезает край, а не переносит.
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: DoableType.caption.copyWith(
                  color: strong ? colors.ink : colors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
