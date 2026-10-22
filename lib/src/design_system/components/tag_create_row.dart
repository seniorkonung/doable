import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Первая строка списка тегов, предлагающая создать тег с названием из поиска.
/// Текст переносится без обрезки, а высота растёт от минимальных 48 dp.
final class TagCreateRow extends StatelessWidget {
  static const double _minHeight = 48;
  static const double _iconGap = 10;

  const TagCreateRow({
    required this.text,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String text;

  /// Доступное название строки вместо [text].
  final String label;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final borderRadius = BorderRadius.circular(DoableMetrics.radiusSm);

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: label,
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
                padding: const EdgeInsetsDirectional.only(
                  start: DoableMetrics.space4,
                  end: DoableMetrics.space3,
                ),
                child: Row(
                  children: [
                    DoableIcon(
                      DoableIconData.plusSmall,
                      size: 18,
                      color: colors.accent,
                    ),
                    const SizedBox(width: _iconGap),
                    Expanded(
                      // Текст читает доступное название строки.
                      child: ExcludeSemantics(
                        child: Text(
                          text,
                          style: DoableType.action.copyWith(
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ),
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
