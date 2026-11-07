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

/// Плитка на всю ширину под сеткой: число и подпись слева, значок в `muted`
/// справа. Глифа направления и отметки архива у неё нет.
final class CountTileWide<T extends Object> {
  const CountTileWide({
    required this.id,
    required this.count,
    required this.name,
    required this.semanticLabel,
    required this.icon,
    this.key,
  }) : assert(count >= 0);

  final T id;
  final int count;
  final String name;

  /// Доступное название плитки: число называет оно.
  final String semanticLabel;
  final DoableIconData icon;

  /// Ключ плитки, по которому потребитель находит её в дереве.
  final Key? key;

  CountTile<T> get _tile => CountTile(
    id: id,
    count: count,
    name: name,
    semanticLabel: semanticLabel,
    key: key,
  );
}

/// Плитки с числом и подписью в сетке равных колонок; ровно одна плитка
/// открыта. Открытую плитку хранит потребитель.
///
/// Нажатие на закрытую плитку вызывает [onPick], а на открытую ничего не
/// делает. Число плиток кратно числу колонок. Необязательная [wide] стоит
/// под сеткой на всю ширину и входит в ту же радиогруппу.
final class CountTiles<T extends Object> extends StatelessWidget {
  const CountTiles({
    required this.tiles,
    required this.columns,
    required this.value,
    required this.onPick,
    required this.label,
    this.wide,
    super.key,
  });

  final List<CountTile<T>> tiles;
  final CountTileColumns columns;

  /// Плитка на всю ширину под сеткой.
  final CountTileWide<T>? wide;

  /// Идентификатор открытой плитки.
  final T value;
  final ValueChanged<T> onPick;

  /// Доступное название группы плиток.
  final String label;

  @override
  Widget build(BuildContext context) {
    final columnCount = columns.count;
    final ids = [...tiles.map((tile) => tile.id), ?wide?.id];
    assert(tiles.isNotEmpty && tiles.length % columnCount == 0);
    assert(ids.toSet().length == ids.length);
    assert(ids.contains(value));
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
          if (wide case final wide?)
            Row(
              children: [
                Expanded(
                  child: _Tile(
                    key: wide.key,
                    tile: wide._tile,
                    icon: wide.icon,
                    open: wide.id == value,
                    onPick: onPick,
                  ),
                ),
              ],
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
    this.icon,
    super.key,
  });

  final CountTile<T> tile;

  /// Значок в конце плитки на всю ширину; у плитки сетки его нет.
  final DoableIconData? icon;
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

    final content = Column(
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
                        fontFeatures: const [FontFeature.tabularFigures()],
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
          style: DoableType.caption.copyWith(color: colors.muted),
        ),
      ],
    );

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
                    child: switch (widget.icon) {
                      null => content,
                      final icon => Row(
                        spacing: DoableMetrics.space3,
                        children: [
                          Expanded(child: content),
                          DoableIcon(icon, size: 24, color: colors.muted),
                        ],
                      ),
                    },
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
