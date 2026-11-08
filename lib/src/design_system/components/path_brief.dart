import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';
import 'action_path.dart';
import 'path_glyph.dart';
import 'relation_stroke.dart';

/// Название намерения и переданные экраном отметки; связь ведёт к нему сверху.
final class PathBriefStep {
  const PathBriefStep({
    required this.name,
    this.relation,
    this.marks = const [],
  });

  final String name;
  final ActionPathRelationKind? relation;
  final List<Widget> marks;
}

/// Свёрнутый путь как одна кнопка. Все строки и доступное имя задаёт экран.
final class PathBrief extends StatelessWidget {
  const PathBrief({
    required this.steps,
    required this.priority,
    required this.emptyText,
    required this.emptyHint,
    required this.betweenText,
    required this.label,
    required this.onPressed,
    this.marks = const [],
    super.key,
  });

  final List<PathBriefStep> steps;
  final DoablePriority priority;
  final String emptyText;
  final String emptyHint;
  final String betweenText;
  final String label;
  final VoidCallback? onPressed;

  /// Отметки разрывов между концами пути.
  final List<Widget> marks;

  @override
  Widget build(BuildContext context) {
    assert(steps.length != 2 || steps.last.relation != null);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final color = priority.color(colors);
    final tone = Color.lerp(color, colors.grip, .5)!;
    final line =
        steps.length == 2 && steps.last.relation == ActionPathRelationKind.need
        ? RelationStrokeKind.need(tone)
        : RelationStrokeKind.can(tone);
    final empty = steps.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Semantics(
            button: true,
            enabled: onPressed != null,
            label: label,
            child: Material(
              color: colors.fill,
              borderRadius: BorderRadius.circular(DoableMetrics.radiusSm),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 10,
                      top: 7,
                      bottom: 7,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _StepRow(
                                name: empty ? emptyText : steps.first.name,
                                marks: empty ? const [] : steps.first.marks,
                                shape: PathGlyphShape.diamond,
                                color: empty ? colors.grip : color,
                                textColor: empty ? colors.accent : colors.ink,
                                dashed: empty,
                                below: steps.length > 1 ? line : null,
                              ),
                              if (steps.length > 2)
                                _BetweenRow(text: betweenText, line: line),
                              if (steps.length > 1)
                                _StepRow(
                                  name: steps.last.name,
                                  marks: steps.last.marks,
                                  shape: PathGlyphShape.finalRing,
                                  color: color,
                                  textColor: colors.ink,
                                  above: line,
                                ),
                              if (marks.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 26,
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 2,
                                    children: marks,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Center(
                            child: DoableIcon(
                              DoableIconData.chevronRight,
                              size: 18,
                              color: colors.muted,
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
        ),
        if (empty)
          Padding(
            padding: const EdgeInsets.only(top: DoableMetrics.space1),
            child: Text(
              emptyHint,
              style: DoableType.hint.copyWith(color: colors.muted),
            ),
          ),
      ],
    );
  }
}

final class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.name,
    required this.marks,
    required this.shape,
    required this.color,
    required this.textColor,
    this.dashed = false,
    this.above,
    this.below,
  });
  final String name;
  final List<Widget> marks;
  final PathGlyphShape shape;
  final Color color;
  final Color textColor;
  final bool dashed;
  final RelationStrokeKind? above;
  final RelationStrokeKind? below;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 36),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 26,
            top: 8,
            bottom: 8,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(name, style: DoableType.row.copyWith(color: textColor)),
              ...marks,
            ],
          ),
        ),
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: 20,
          child: Column(
            children: [
              SizedBox(
                height: 11,
                child: above == null
                    ? null
                    : RelationStroke(
                        kind: above!,
                        axis: RelationStrokeAxis.vertical,
                      ),
              ),
              PathGlyph(
                shape: shape,
                outline: dashed
                    ? PathGlyphOutline.dashed
                    : PathGlyphOutline.solid,
                size: 14,
                color: color,
              ),
              Expanded(
                child: below == null
                    ? const SizedBox()
                    : RelationStroke(
                        kind: below!,
                        axis: RelationStrokeAxis.vertical,
                      ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _BetweenRow extends StatelessWidget {
  const _BetweenRow({required this.text, required this.line});
  final String text;
  final RelationStrokeKind line;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 20,
          child: RelationStroke(kind: line, axis: RelationStrokeAxis.vertical),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: DoableType.caption.copyWith(
              color: Theme.of(context).extension<DoableColors>()!.muted,
            ),
          ),
        ),
      ],
    ),
  );
}
