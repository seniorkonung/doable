import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_priority.dart';
import '../doable_type.dart';
import 'action_path.dart';
import 'edge_overhang.dart';
import 'path_action.dart';
import 'path_glyph.dart';
import 'relation_stroke.dart';

typedef PathBuilderRelationKind = ActionPathRelationKind;

/// Данные связи для отображения на строящемся пути.
final class PathBuilderRelation {
  const PathBuilderRelation({
    required this.kind,
    required this.priority,
    required this.word,
    required this.label,
    required this.onOpen,
  });
  final PathBuilderRelationKind kind;
  final DoablePriority priority;
  final String word;
  final String label;
  final VoidCallback onOpen;
}

/// Данные намерения для отображения на строящемся пути.
final class PathBuilderStep {
  const PathBuilderStep({
    required this.id,
    required this.name,
    required this.label,
    required this.openLabel,
    required this.onOpen,
  });
  final String id;
  final String name;
  final String label;
  final String openLabel;
  final VoidCallback onOpen;
}

/// Следующее намерение и ведущая к нему связь.
final class PathBuilderLink {
  const PathBuilderLink({required this.step, required this.relation});

  final PathBuilderStep step;
  final PathBuilderRelation relation;
}

/// Непустой путь начинается корнем, остальные шаги несут связи.
final class PathBuilderPath {
  const PathBuilderPath({required this.root, this.links = const []});

  final PathBuilderStep root;
  final List<PathBuilderLink> links;
}

/// Путь, действие и кандидаты; состоянием и текстами управляет экран.
final class PathBuilder extends StatelessWidget {
  const PathBuilder({
    required this.path,
    required this.priority,
    required this.actionName,
    required this.actionLabel,
    required this.emptyActionText,
    required this.slotText,
    required this.slotLabel,
    required this.onChooseRoot,
    required this.onStep,
    required this.hint,
    required this.switcher,
    required this.addText,
    required this.addLabel,
    required this.onAdd,
    this.showEndSlot = false,
    this.emptyHalf,
    this.children = const [],
    super.key,
  });
  final PathBuilderPath? path;
  final DoablePriority priority;
  final String actionName;
  final String actionLabel;
  final String emptyActionText;
  final String slotText;
  final String slotLabel;
  final VoidCallback onChooseRoot;
  final ValueChanged<String> onStep;
  final String hint;
  final Widget switcher;
  final String addText;
  final String addLabel;
  final VoidCallback onAdd;
  final bool showEndSlot;
  final ({String title, String text})? emptyHalf;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final currentPath = path;
    final steps = currentPath == null
        ? const <PathBuilderStep>[]
        : [currentPath.root, ...currentPath.links.map((link) => link.step)];
    final colors = Theme.of(context).extension<DoableColors>()!;
    final end = priority.color(colors);
    final tone = Color.lerp(end, colors.grip, .5)!;
    Widget stroke(RelationStrokeKind kind) =>
        RelationStroke(kind: kind, axis: RelationStrokeAxis.vertical);
    RelationStrokeKind line(PathBuilderRelation r) => switch (r.kind) {
      ActionPathRelationKind.need => RelationStrokeKind.need(tone),
      ActionPathRelationKind.can => RelationStrokeKind.can(tone),
    };
    Widget rail({
      required PathGlyph glyph,
      RelationStrokeKind? above,
      RelationStrokeKind? below,
    }) => SizedBox(
      width: 20,
      child: Column(
        children: [
          SizedBox(height: 13, child: above == null ? null : stroke(above)),
          glyph,
          Expanded(child: below == null ? const SizedBox() : stroke(below)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (currentPath == null)
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                rail(
                  glyph: PathGlyph(
                    shape: PathGlyphShape.diamond,
                    outline: PathGlyphOutline.dashed,
                    size: 14,
                    color: colors.grip,
                  ),
                  below: RelationStrokeKind.can(colors.grip),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    excludeSemantics: true,
                    button: true,
                    label: slotLabel,
                    onTap: onChooseRoot,
                    child: InkWell(
                      onTap: onChooseRoot,
                      excludeFromSemantics: true,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          slotText,
                          style: DoableType.action.copyWith(
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          for (final (i, step) in steps.indexed) ...[
            if (i > 0)
              _Relation(
                relation: currentPath.links[i - 1].relation,
                line: line(currentPath.links[i - 1].relation),
              ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 12),
                  rail(
                    glyph: PathGlyph(
                      shape: i == 0
                          ? PathGlyphShape.diamond
                          : i == steps.length - 1
                          ? PathGlyphShape.finalRing
                          : PathGlyphShape.ring,
                      outline: PathGlyphOutline.solid,
                      size: 14,
                      color: i == 0 || i == steps.length - 1 ? end : tone,
                    ),
                    above: i == 0
                        ? null
                        : line(currentPath.links[i - 1].relation),
                    below: i + 1 == steps.length
                        ? RelationStrokeKind.can(colors.grip)
                        : line(currentPath.links[i].relation),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: i == steps.length - 1 && i != 0
                          ? Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                step.name,
                                style: DoableType.action.copyWith(
                                  color: colors.ink,
                                ),
                              ),
                            )
                          : Semantics(
                              excludeSemantics: true,
                              button: true,
                              label: step.label,
                              onTap: i == 0
                                  ? onChooseRoot
                                  : () => onStep(step.id),
                              child: InkWell(
                                onTap: i == 0
                                    ? onChooseRoot
                                    : () => onStep(step.id),
                                excludeFromSemantics: true,
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    step.name,
                                    style: DoableType.action.copyWith(
                                      color: colors.ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: IconButton(
                      tooltip: step.openLabel,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 40),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: step.onOpen,
                      icon: DoableIcon(
                        DoableIconData.arrowUpRight,
                        size: 18,
                        color: colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showEndSlot)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  rail(
                    glyph: PathGlyph(
                      shape: PathGlyphShape.ring,
                      outline: PathGlyphOutline.dashed,
                      size: 14,
                      color: colors.grip,
                    ),
                    above: RelationStrokeKind.can(colors.grip),
                    below: RelationStrokeKind.can(colors.grip),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      slotText,
                      style: DoableType.field.copyWith(color: colors.muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
        PathAction(
          name: actionName,
          emptyText: emptyActionText,
          label: actionLabel,
        ),
        if (hint.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 42, top: 10),
            child: Text(
              hint,
              style: DoableType.hint.copyWith(color: colors.muted),
            ),
          ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          EdgeOverhang(
            end: 6,
            child: Row(
              children: [
                Expanded(child: switcher),
                TextButton.icon(
                  onPressed: onAdd,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accent,
                    minimumSize: const Size(0, 44),
                    textStyle: DoableType.section,
                  ),
                  icon: DoableIcon(
                    DoableIconData.plusSmall,
                    size: 18,
                    color: colors.accent,
                  ),
                  label: Text(addText, semanticsLabel: addLabel),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (emptyHalf case final empty?)
            _EmptyHalf(title: empty.title, text: empty.text)
          else
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              child,
            ],
        ],
      ],
    );
  }
}

final class _Relation extends StatelessWidget {
  const _Relation({required this.relation, required this.line});
  final PathBuilderRelation relation;
  final RelationStrokeKind line;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final color = relation.priority.color(colors);
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: 20,
            height: 26,
            child: Center(
              child: SizedBox(
                height: 26,
                child: RelationStroke(
                  kind: line,
                  axis: RelationStrokeAxis.vertical,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            excludeSemantics: true,
            button: true,
            label: relation.label,
            onTap: relation.onOpen,
            child: InkWell(
              onTap: relation.onOpen,
              excludeFromSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 26,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: relation.priority == DoablePriority.p4
                            ? colors.fill
                            : color.withValues(alpha: .12),
                      ),
                      child: Center(
                        child: DoableIcon(
                          DoableIconData.relationMini,
                          size: 14,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    relation.word,
                    style: DoableType.caption.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _EmptyHalf extends StatelessWidget {
  const _EmptyHalf({required this.title, required this.text});
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return CustomPaint(
      painter: _DashedBorder(colors.grip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: DoableType.section.copyWith(color: colors.ink)),
            const SizedBox(height: 4),
            Text(text, style: DoableType.hint.copyWith(color: colors.muted)),
          ],
        ),
      ),
    );
  }
}

final class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.75),
          const Radius.circular(16),
        ),
      );
    canvas.drawPath(
      dashPath(path, dash: 5, gap: 5),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => color != oldDelegate.color;
}
