import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'relation_stroke.dart';

/// Действие в конце строящегося пути; его название не является кнопкой.
final class PathAction extends StatelessWidget {
  const PathAction({
    required this.name,
    required this.emptyText,
    required this.label,
    super.key,
  });

  final String name;
  final String emptyText;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: DoableMetrics.space3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Column(
                  children: [
                    SizedBox(
                      height: 8,
                      child: RelationStroke(
                        kind: RelationStrokeKind.can(colors.grip),
                        axis: RelationStrokeAxis.vertical,
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      child: OverflowBox(
                        maxWidth: 24,
                        child: SizedBox.square(
                          dimension: 24,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.ink,
                            ),
                            child: Center(
                              child: DoableIcon(
                                DoableIconData.bolt,
                                size: 14,
                                color: colors.bg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    name.isEmpty ? emptyText : name,
                    style: DoableType.action.copyWith(
                      fontWeight: FontWeight.w600,
                      color: name.isEmpty ? colors.muted : colors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
