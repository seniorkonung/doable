import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';
import 'path_glyph.dart';

/// Кандидат следующего намерения с отдельным открытием его страницы.
final class StepOption extends StatelessWidget {
  const StepOption({
    required this.name,
    required this.priority,
    required this.label,
    required this.openLabel,
    required this.onPick,
    required this.onOpen,
    this.freshText,
    super.key,
  });
  final String name;
  final DoablePriority priority;
  final String label;
  final String openLabel;
  final VoidCallback onPick;
  final VoidCallback onOpen;
  final String? freshText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final color = priority.color(colors);
    return Material(
      color: priority == DoablePriority.p4
          ? colors.fill
          : Color.alphaBlend(color.withValues(alpha: .1), colors.fill),
      borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              excludeSemantics: true,
              button: true,
              label: label,
              onTap: onPick,
              child: InkWell(
                onTap: onPick,
                excludeFromSemantics: true,
                borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 0, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 22,
                        child: Center(
                          child: PathGlyph(
                            shape: PathGlyphShape.ring,
                            outline: PathGlyphOutline.solid,
                            size: 14,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              name,
                              style: DoableType.action.copyWith(
                                color: colors.ink,
                              ),
                            ),
                            if (freshText case final text?)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.bg,
                                  borderRadius: BorderRadius.circular(
                                    DoableMetrics.radiusXs,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 1,
                                  ),
                                  child: Text(
                                    text,
                                    style: DoableType.caption.copyWith(
                                      color: colors.muted,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: openLabel,
              onPressed: onOpen,
              icon: DoableIcon(
                DoableIconData.arrowUpRight,
                size: 18,
                color: colors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
