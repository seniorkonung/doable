import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'relation_stroke.dart';

/// Число колонок сетки плиток.
enum CountTileColumns {
  two(2),
  three(3);

  const CountTileColumns(this.count);

  final int count;
}

/// Вид связи на глифе плитки: сплошная линия — «нужно», пунктир — «можно».
enum CountTileGlyphKind { need, can }

/// Конец стрелки глифа, на котором стоит намерение страницы.
enum CountTileGlyphDirection {
  /// Закрашенная точка в начале, кольцо в конце: связь идёт от намерения.
  fromIntention,

  /// Кольцо в начале, закрашенная точка в конце: связь идёт к намерению.
  toIntention,
}

/// Глиф направления связи 38 × 12 в конце строки числа. Закрашенная точка —
/// намерение страницы, кольцо — другое; стрелка идёт слева направо.
final class CountTileGlyph {
  const CountTileGlyph({required this.kind, required this.direction});

  final CountTileGlyphKind kind;
  final CountTileGlyphDirection direction;
}

/// Плитка с числом и готовыми подписью и доступным названием. [id] для
/// плиток непрозрачен и только сравнивается с открытой.
final class CountTile<T extends Object> {
  const CountTile({
    required this.id,
    required this.count,
    required this.name,
    required this.semanticLabel,
    this.glyph,
    this.archived = false,
    this.key,
  }) : assert(count >= 0);

  final T id;
  final int count;
  final String name;

  /// Доступное название плитки: число и наличие архива называет оно.
  final String semanticLabel;

  /// Глиф направления; без него плитка показывает только число и подпись.
  final CountTileGlyph? glyph;

  /// Малый значок архива после числа.
  final bool archived;

  /// Ключ плитки, по которому потребитель находит её в дереве.
  final Key? key;
}

/// Плитки с числом и подписью в сетке равных колонок; ровно одна плитка
/// открыта. Открытую плитку хранит потребитель.
///
/// Нажатие на закрытую плитку вызывает [onPick], а на открытую ничего не
/// делает. Число плиток кратно числу колонок.
final class CountTiles<T extends Object> extends StatelessWidget {
  const CountTiles({
    required this.tiles,
    required this.columns,
    required this.value,
    required this.onPick,
    required this.label,
    super.key,
  });

  final List<CountTile<T>> tiles;
  final CountTileColumns columns;

  /// Идентификатор открытой плитки.
  final T value;
  final ValueChanged<T> onPick;

  /// Доступное название группы плиток.
  final String label;

  @override
  Widget build(BuildContext context) {
    final columnCount = columns.count;
    assert(tiles.isNotEmpty && tiles.length % columnCount == 0);
    assert(tiles.map((tile) => tile.id).toSet().length == tiles.length);
    assert(tiles.any((tile) => tile.id == value));
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.radioGroup,
      label: label,
      child: Column(
        spacing: DoableMetrics.space2,
        children: [
          for (var start = 0; start < tiles.length; start += columnCount)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DoableMetrics.space2,
                children: [
                  for (final tile in tiles.sublist(start, start + columnCount))
                    Expanded(
                      child: _Tile(
                        key: tile.key,
                        tile: tile,
                        open: tile.id == value,
                        onPick: onPick,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

final class _Tile<T extends Object> extends StatefulWidget {
  const _Tile({
    required this.tile,
    required this.open,
    required this.onPick,
    super.key,
  });

  final CountTile<T> tile;
  final bool open;
  final ValueChanged<T> onPick;

  @override
  State<_Tile<T>> createState() => _TileState<T>();
}

final class _TileState<T extends Object> extends State<_Tile<T>> {
  var _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_handleHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_handleHighlightMode);
    super.dispose();
  }

  // Кольцо фокуса нужно только при управлении с клавиатуры.
  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final tile = widget.tile;
    final open = widget.open;
    const radius = BorderRadius.all(Radius.circular(DoableMetrics.radiusLg));
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final numberColor = tile.count == 0 ? colors.grip : colors.ink;

    return MergeSemantics(
      child: Semantics(
        label: tile.semanticLabel,
        enabled: true,
        checked: open,
        inMutuallyExclusiveGroup: true,
        // Плоскость, кольца и отклик нажатия рисуются в порядке потомков,
        // поэтому область прокрутки их обрезает. На Material предка они
        // рисовались бы под всем его содержимым и без этой обрезки:
        // https://api.flutter.dev/flutter/material/InkWell-class.html
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: open ? colors.fill : null,
            borderRadius: radius,
            boxShadow: showsFocus
                ? [
                    BoxShadow(color: colors.accent, spreadRadius: 4),
                    BoxShadow(color: colors.bg, spreadRadius: 2),
                  ]
                : null,
          ),
          // Кольцо лежит поверх содержимого внутри плитки и не сдвигает его,
          // как внутренняя тень макета.
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: open ? null : Border.all(color: colors.hairline),
              borderRadius: radius,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  if (!open) widget.onPick(tile.id);
                },
                borderRadius: radius,
                focusColor: Colors.transparent,
                onFocusChange: (focused) => setState(() => _focused = focused),
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DoableMetrics.space3,
                      11,
                      DoableMetrics.space3,
                      DoableMetrics.space3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 2,
                      children: [
                        Row(
                          spacing: 6,
                          children: [
                            Expanded(
                              child: Row(
                                spacing: 6,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${tile.count}',
                                      style: DoableType.headline.copyWith(
                                        color: numberColor,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (tile.archived)
                                    DoableIcon(
                                      DoableIconData.archive,
                                      size: 14,
                                      color: colors.muted,
                                    ),
                                ],
                              ),
                            ),
                            if (tile.glyph case final glyph?)
                              _DirectionGlyph(glyph: glyph, color: numberColor),
                          ],
                        ),
                        Text(
                          tile.name,
                          style: DoableType.caption.copyWith(
                            color: colors.muted,
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

/// Глиф 38 × 12 на сетке макета: линия между точками — [RelationStroke],
/// точки и наконечник стрелки рисует [_GlyphPainter].
final class _DirectionGlyph extends StatelessWidget {
  const _DirectionGlyph({required this.glyph, required this.color});

  static const Size size = Size(38, 12);
  static const double _lineStart = 12;
  static const double _lineLength = 12;

  final CountTileGlyph glyph;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _GlyphPainter(color: color, direction: glyph.direction),
          ),
        ),
        Positioned(
          left: _lineStart,
          top: 0,
          width: _lineLength,
          height: size.height,
          child: RelationStroke(
            kind: switch (glyph.kind) {
              CountTileGlyphKind.need => RelationStrokeKind.need(color),
              CountTileGlyphKind.can => RelationStrokeKind.can(color),
            },
            axis: RelationStrokeAxis.horizontal,
          ),
        ),
      ],
    ),
  );
}

final class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.color, required this.direction});

  final Color color;
  final CountTileGlyphDirection direction;

  static const double _outlineWidth = 1.5;
  static const double _dotRadius = 4.25;
  static const double _ringRadius = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _outlineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Кольцо чуть смещено к линии: его внешний край стоит там же, где край
    // закрашенной точки.
    switch (direction) {
      case CountTileGlyphDirection.fromIntention:
        canvas.drawCircle(const Offset(5, 6), _dotRadius, fill);
        canvas.drawCircle(const Offset(32.75, 6), _ringRadius, stroke);
      case CountTileGlyphDirection.toIntention:
        canvas.drawCircle(const Offset(5.25, 6), _ringRadius, stroke);
        canvas.drawCircle(const Offset(33, 6), _dotRadius, fill);
    }
    canvas.drawPath(
      Path()
        ..moveTo(23.25, 3.25)
        ..lineTo(26.25, 6)
        ..lineTo(23.25, 8.75),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      color != oldDelegate.color || direction != oldDelegate.direction;
}
