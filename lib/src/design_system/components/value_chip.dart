import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';

/// Значок значения даты или времени.
enum ValueChipIcon { calendar, clock }

/// Значение нового действия; экран задаёт текст, доступное имя и нажатие.
final class ValueChip extends StatelessWidget {
  const ValueChip.icon({
    required this.value,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  }) : priority = null;
  const ValueChip.priority({
    required this.value,
    required this.priority,
    required this.label,
    required this.onPressed,
    super.key,
  }) : icon = null;

  final String value;
  final String label;
  final VoidCallback? onPressed;
  final ValueChipIcon? icon;
  final DoablePriority? priority;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final priority = this.priority;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            customBorder: const StadiumBorder(),
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DoableMetrics.tapMin,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: DoableMetrics.controlHeightSm,
                    ),
                    padding: const EdgeInsetsDirectional.only(
                      start: 10,
                      end: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colors.fill,
                      borderRadius: BorderRadius.circular(
                        DoableMetrics.radiusFull,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (priority != null)
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: priority.color(colors),
                                width: 2,
                              ),
                              color: priority == DoablePriority.p4
                                  ? null
                                  : priority
                                        .color(colors)
                                        .withValues(alpha: .12),
                            ),
                          )
                        else
                          DoableIcon(
                            switch (icon!) {
                              ValueChipIcon.calendar => DoableIconData.calendar,
                              ValueChipIcon.clock => DoableIconData.clock,
                            },
                            size: 18,
                            color: colors.muted,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          value,
                          softWrap: false,
                          maxLines: 1,
                          style: DoableType.section.copyWith(
                            color: colors.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
