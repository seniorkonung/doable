import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'path_glyph.dart';
import 'relation_head.dart';
import 'relation_stroke.dart';

/// Направление связей относительно намерения страницы.
enum RelationBatchDirection { outgoing, incoming }

/// Отметка с идентичностью, не зависящей от названия намерения.
final class RelationBatchItem<T> {
  const RelationBatchItem({required this.value, required this.name});

  final T value;
  final String name;
}

/// Будущие связи: намерение страницы и отдельная ветвь каждой отметки.
final class RelationBatch<T> extends StatelessWidget {
  const RelationBatch({
    required this.anchor,
    required this.kind,
    required this.direction,
    required this.items,
    required this.onRemove,
    required this.anchorNote,
    required this.emptyText,
    required this.needLabel,
    required this.canLabel,
    required this.listLabel,
    required this.anchorSemanticLabel,
    required this.itemSemanticLabel,
    required this.removeLabel,
    super.key,
  });

  final String anchor;
  final RelationHeadKind kind;
  final RelationBatchDirection direction;
  final List<RelationBatchItem<T>> items;
  final ValueChanged<T> onRemove;
  final String anchorNote;
  final String emptyText;
  final String needLabel;
  final String canLabel;
  final String listLabel;
  final String anchorSemanticLabel;
  final String Function(String name) itemSemanticLabel;
  final String Function(String name) removeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final outgoing = direction == RelationBatchDirection.outgoing;
    final stroke = switch (kind) {
      RelationHeadKind.need => RelationStrokeKind.need(colors.grip),
      RelationHeadKind.can => RelationStrokeKind.can(colors.grip),
    };
    final anchorRow = _TreeRow(
      stroke: stroke,
      above: !outgoing,
      below: outgoing,
      glyph: outgoing ? PathGlyphShape.diamond : PathGlyphShape.ring,
      bottomGap: outgoing,
      child: Semantics(
        label: '$anchorSemanticLabel. $anchorNote',
        child: ExcludeSemantics(
          child: _Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anchor,
                    style: DoableType.action.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    anchorNote,
                    style: DoableType.hint.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final kindRow = _TreeRow(
      stroke: stroke,
      above: true,
      below: true,
      junction: 22,
      child: SizedBox(
        height: DoableMetrics.tapMin,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14),
          child: Row(
            children: [
              RelationKindMark(kind: stroke),
              const SizedBox(width: 7),
              Text(
                kind == RelationHeadKind.need ? needLabel : canLabel,
                style: DoableType.section.copyWith(color: colors.ink),
              ),
            ],
          ),
        ),
      ),
    );
    final count = items.isEmpty ? 1 : items.length;
    final list = Semantics(
      label: listLabel,
      explicitChildNodes: true,
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            _TreeRow(
              stroke: stroke,
              above: outgoing || i > 0,
              below: !outgoing || i < count - 1,
              branch: true,
              bottomGap: !outgoing || i < count - 1,
              child: items.isEmpty
                  ? _EmptyCard(text: emptyText)
                  : _ItemCard<T>(
                      item: items[i],
                      semanticLabel: itemSemanticLabel(items[i].name),
                      removeLabel: removeLabel(items[i].name),
                      onRemove: onRemove,
                    ),
            ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: outgoing
          ? [anchorRow, kindRow, list]
          : [list, kindRow, anchorRow],
    );
  }
}

final class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.stroke,
    required this.above,
    required this.below,
    required this.child,
    this.glyph,
    this.branch = false,
    this.bottomGap = false,
    this.junction = 24,
  });

  final RelationStrokeKind stroke;
  final bool above;
  final bool below;
  final Widget child;
  final PathGlyphShape? glyph;
  final bool branch;
  final bool bottomGap;
  final double junction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: ExcludeSemantics(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (above)
                    Positioned(
                      top: 0,
                      left: 10,
                      height: junction - (glyph == null ? 0 : 7),
                      child: RelationStroke(
                        kind: stroke,
                        axis: RelationStrokeAxis.vertical,
                      ),
                    ),
                  if (below)
                    Positioned(
                      top: junction + (glyph == null ? 0 : 7),
                      bottom: 0,
                      left: 10,
                      child: RelationStroke(
                        kind: stroke,
                        axis: RelationStrokeAxis.vertical,
                      ),
                    ),
                  if (branch)
                    Positioned(
                      left: 11,
                      top: junction - 1,
                      width: 21,
                      height: 2,
                      child: RelationStroke(
                        kind: stroke,
                        axis: RelationStrokeAxis.horizontal,
                      ),
                    ),
                  if (glyph case final shape?)
                    Positioned(
                      left: 4,
                      top: junction - 7,
                      child: PathGlyph(
                        shape: shape,
                        outline: PathGlyphOutline.solid,
                        size: 14,
                        color: colors.grip,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: 10,
                bottom: bottomGap ? 8 : 0,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

final class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).extension<DoableColors>()!.fill,
      borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: child,
    ),
  );
}

final class _ItemCard<T> extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.semanticLabel,
    required this.removeLabel,
    required this.onRemove,
  });
  final RelationBatchItem<T> item;
  final String semanticLabel;
  final String removeLabel;
  final ValueChanged<T> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 14,
                top: 13,
                bottom: 13,
              ),
              child: Semantics(
                label: semanticLabel,
                child: ExcludeSemantics(
                  child: Text(
                    item.name,
                    style: DoableType.action.copyWith(color: colors.ink),
                  ),
                ),
              ),
            ),
          ),
          SizedBox.square(
            dimension: 48,
            child: IconButton(
              tooltip: removeLabel,
              padding: EdgeInsets.zero,
              onPressed: () => onRemove(item.value),
              icon: DoableIcon(
                DoableIconData.close,
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

final class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return CustomPaint(
      foregroundPainter: _DashedBorder(colors.grip),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            text,
            style: DoableType.field.copyWith(color: colors.muted),
          ),
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
          const Radius.circular(DoableMetrics.radiusLg),
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
