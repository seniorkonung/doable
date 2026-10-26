import 'package:flutter/material.dart';

import 'path_glyph.dart';
import 'relation_stroke.dart';

/// Что стоит в колонке рейки пути.
sealed class PathRailMark {
  const PathRailMark();

  /// Глиф против первой строки текста; линии над ним и под ним
  /// необязательны: у первой строки формы нет линии сверху, у последней —
  /// снизу.
  const factory PathRailMark.glyph(
    PathGlyph glyph, {
    RelationStrokeKind? above,
    RelationStrokeKind? below,
  }) = PathRailGlyph;

  /// Строка без глифа — одна линия на всю высоту.
  const factory PathRailMark.stroke(RelationStrokeKind kind) = PathRailStroke;
}

final class PathRailGlyph extends PathRailMark {
  const PathRailGlyph(this.glyph, {this.above, this.below});

  final PathGlyph glyph;
  final RelationStrokeKind? above;
  final RelationStrokeKind? below;
}

final class PathRailStroke extends PathRailMark {
  const PathRailStroke(this.kind);

  final RelationStrokeKind kind;
}

/// Строка пути: слева колонка рейки, справа содержимое, которое задаёт
/// высоту строки. Зазор до рейки задаёт содержимое. Колонка исключена из
/// семантики: роль и вид называют слова содержимого.
final class PathRail extends StatelessWidget {
  const PathRail({required this.mark, required this.child, super.key});

  final PathRailMark mark;
  final Widget child;

  static const double _width = 22;

  /// Сегмент над глифом ставит его против первой строки текста поля.
  static const double _aboveGlyph = 17;
  static const double _glyphSlot = 14;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _width,
          child: ExcludeSemantics(
            child: Column(
              children: switch (mark) {
                PathRailGlyph(:final glyph, :final above, :final below) => [
                  SizedBox(
                    height: _aboveGlyph,
                    child: above == null ? null : _stroke(above),
                  ),
                  SizedBox.square(
                    dimension: _glyphSlot,
                    child: Center(child: glyph),
                  ),
                  Expanded(
                    child: below == null ? const SizedBox() : _stroke(below),
                  ),
                ],
                PathRailStroke(:final kind) => [Expanded(child: _stroke(kind))],
              },
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );

  static Widget _stroke(RelationStrokeKind kind) =>
      RelationStroke(kind: kind, axis: RelationStrokeAxis.vertical);
}
