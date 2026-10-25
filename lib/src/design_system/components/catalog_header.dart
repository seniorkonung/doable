import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Заголовок списка: показываемый тип, подтверждённое число и сортировка.
final class CatalogHeader extends StatelessWidget {
  const CatalogHeader({
    required this.title,
    required this.summary,
    this.count,
    super.key,
  });

  final String title;
  final String summary;

  /// Число строк при текущих поиске и тегах; пустой список показывает 0.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (constraints.maxWidth - DoableMetrics.space2) / 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(
                    container: true,
                    header: true,
                    child: Text(
                      title,
                      style: DoableType.section.copyWith(color: colors.ink),
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: DoableMetrics.space2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.fill,
                        borderRadius: BorderRadius.circular(
                          DoableMetrics.radiusSm,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: Text(
                            '$count',
                            style: DoableType.label.copyWith(
                              color: colors.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DoableMetrics.space2),
          Expanded(
            child: Align(
              widthFactor: 1,
              alignment: AlignmentDirectional.centerEnd,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(DoableMetrics.radiusFull),
                ),
                child: SizedBox(
                  height: 32,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DoableMetrics.space2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DoableIcon(
                          DoableIconData.sliders,
                          size: 16,
                          color: colors.muted,
                        ),
                        const SizedBox(width: DoableMetrics.space1),
                        Flexible(
                          child: Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DoableType.caption.copyWith(
                              color: colors.ink,
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
        ],
      ),
    );
  }
}
