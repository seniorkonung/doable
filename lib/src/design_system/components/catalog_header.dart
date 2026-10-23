import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Заголовок списка в экране выбора: что показывает список и сколько в нём
/// строк. Это текст, а не кнопка, и он прокручивается вместе со строками.
final class CatalogHeader extends StatelessWidget {
  const CatalogHeader({required this.title, required this.count, super.key});

  final String title;

  /// Число строк при текущих поиске и тегах; пустой список показывает 0.
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return Row(
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
        const SizedBox(width: DoableMetrics.space2),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(DoableMetrics.radiusSm),
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
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
