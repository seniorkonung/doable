import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'tag_dot.dart';

/// Отметка тега в строке при выборе тегов намерения.
enum TagRowMark { none, checked }

/// Строка тега в панели тегов: точка цвета, полное название и отметка.
/// Название переносится без обрезки, а высота растёт от минимальных 48 dp.
final class TagRow extends StatelessWidget {
  static const double _minHeight = 48;

  const TagRow({
    required this.name,
    required this.color,
    required this.mark,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String name;
  final DoableTagColor? color;
  final TagRowMark mark;

  /// Доступное название строки вместо названия тега; передаёт и отметку
  /// словами, чтобы она не опиралась только на форму галочки.
  final String label;

  /// Без обработчика строка не принимает нажатие, а экранный диктор
  /// объявляет её недоступной; вид строки не меняется.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final borderRadius = BorderRadius.circular(DoableMetrics.radiusSm);

    return MergeSemantics(
      child: Semantics(
        label: label,
        checked: mark == TagRowMark.checked,
        enabled: onPressed != null,
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: borderRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DoableMetrics.space3,
                ),
                child: Row(
                  children: [
                    TagDot(color: color, size: TagDotSize.large),
                    const SizedBox(width: DoableMetrics.space3),
                    Expanded(
                      // Название читает доступное название строки.
                      child: ExcludeSemantics(
                        child: Text(
                          name,
                          style: DoableType.action.copyWith(color: colors.ink),
                        ),
                      ),
                    ),
                    if (mark == TagRowMark.checked) ...[
                      const SizedBox(width: DoableMetrics.space3),
                      DoableIcon(
                        DoableIconData.check,
                        size: 20,
                        color: colors.accent,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
