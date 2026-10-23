import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Плитка фильтра по тегам рядом с полем поиска: той же высоты и с теми же
/// углами. Пока условий нет, это иконка `muted` на `fill`; с условиями
/// иконка и их число становятся `accent` на `accent-soft` и говорят, что
/// список сужен.
final class FilterButton extends StatelessWidget {
  const FilterButton({
    required this.count,
    required this.label,
    required this.onPressed,
    super.key,
  }) : assert(count >= 0);

  /// Число условий: каждый обязательный и каждый исключённый тег считается
  /// одним; 0 — фильтра нет.
  final int count;

  /// Доступное название, которое называет и число условий.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final filtered = count > 0;
    final foreground = filtered ? colors.accent : colors.muted;
    final icon = DoableIcon(DoableIconData.filter, size: 20, color: foreground);

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: filtered ? colors.accentSoft : colors.fill,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusSm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints.tightFor(
                  height: DoableMetrics.tapMin,
                ).copyWith(minWidth: DoableMetrics.tapMin),
                child: filtered
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 10,
                          end: DoableMetrics.space3,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            icon,
                            const SizedBox(width: 5),
                            Text(
                              '$count',
                              style: DoableType.label.copyWith(
                                color: foreground,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Center(widthFactor: 1, child: icon),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
