import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';
import 'path_glyph.dart';
import 'relation_stroke.dart';

/// Вид связи пути: «нужно» — сплошная линия, «можно» — пунктирная.
enum ChoicePathRelationKind { need, can }

/// Намерение или действие на пути.
final class ChoicePathStep {
  const ChoicePathStep({
    required this.name,
    required this.semanticLabel,
    required this.onOpen,
    this.archived = false,
    this.buttonKey,
  });

  final String name;

  /// Доступное название кнопки шага.
  final String semanticLabel;

  /// Открывает страницу намерения или действия.
  final VoidCallback onOpen;

  /// Намерение архивировано: имя `muted`, глиф `grip`, а после имени метка.
  final bool archived;

  /// Ключ кнопки шага.
  final Key? buttonKey;
}

/// Долговременная связь между двумя шагами пути.
final class ChoicePathRelation {
  const ChoicePathRelation({
    required this.kind,
    required this.priority,
    required this.semanticLabel,
    required this.onOpen,
    this.archived = false,
    this.buttonKey,
  });

  final ChoicePathRelationKind kind;

  /// Приоритет самой связи: цвет плитки, а не линии.
  final DoablePriority priority;

  /// Доступное название кнопки связи.
  final String semanticLabel;

  /// Открывает подробный просмотр связи.
  final VoidCallback onOpen;

  /// Связь архивирована: линия `grip` с прежним узором, плитка `fill` со
  /// значком `muted`, а после слова метка.
  final bool archived;

  /// Ключ кнопки связи.
  final Key? buttonKey;
}

/// Связь и шаг, к которому она ведёт от предыдущего.
final class ChoicePathLink {
  const ChoicePathLink({required this.relation, required this.step});

  final ChoicePathRelation relation;
  final ChoicePathStep step;
}

/// Сохранённый путь дневного выбора целиком: каждый шаг от исходного намерения
/// до выбранного действия и каждая связь между ними.
///
/// Шаг — строка не ниже `tap-min`: глиф в рейке шириной 22 и название `action`
/// за `space-3` от неё. Ромб — исходное намерение, кольцо — каждое
/// промежуточное, круг — действие. Название переносится, глиф остаётся на
/// первой строке, а линия под ним тянется. Путь не сокращается и не
/// прокручивается сам: длинный путь прокручивает родитель.
///
/// Связь — строка высотой 30, через рейку которой проходит её линия, а рядом
/// стоят плитка цвета приоритета самой связи и слово вида. Ромб и круг цвета
/// [priority], линии и кольца — он же пополам с `grip`, а у выполненного выбора
/// все они `grip`.
///
/// Тексты, метку архива, ключи, обработчики и доступные названия задаёт
/// потребитель. Родитель задаёт ширину.
final class ChoicePath extends StatelessWidget {
  const ChoicePath({
    required this.source,
    required this.intermediate,
    required this.action,
    required this.priority,
    required this.kindWord,
    required this.archivedBadge,
    required this.archivedNote,
    this.done = false,
    super.key,
  });

  /// Исходное намерение.
  final ChoicePathStep source;

  /// Промежуточные намерения в порядке пути, каждое со связью к нему.
  final List<ChoicePathLink> intermediate;

  /// Выбранное действие со связью к нему. Оно есть всегда, поэтому в пути
  /// хотя бы одна связь.
  final ChoicePathLink action;

  /// Приоритет выбора: цвет концов, линий и колец.
  final DoablePriority priority;

  /// Выбор выполнен.
  final bool done;

  /// Слово вида рядом с плиткой.
  final String Function(ChoicePathRelationKind kind) kindWord;

  /// Метка после каждого архивированного шага и связи.
  final Widget archivedBadge;

  /// Строка под путём, в котором что-то архивировано.
  final String archivedNote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final end = done ? colors.grip : priority.color(colors);
    final tone = done ? colors.grip : Color.lerp(end, colors.grip, .5)!;
    final links = [...intermediate, action];
    final hasArchive =
        source.archived ||
        links.any((link) => link.step.archived || link.relation.archived);

    RelationStrokeKind line(ChoicePathRelation relation) {
      final color = relation.archived ? colors.grip : tone;
      return switch (relation.kind) {
        ChoicePathRelationKind.need => RelationStrokeKind.need(color),
        ChoicePathRelationKind.can => RelationStrokeKind.can(color),
      };
    }

    PathGlyph glyph(ChoicePathStep step, PathGlyphShape shape, Color color) =>
        PathGlyph(
          shape: shape,
          outline: PathGlyphOutline.solid,
          size: _glyphSize,
          color: step.archived ? colors.grip : color,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Отклик нажатия рисуется на плоскости пути, а не под ней:
        // https://api.flutter.dev/flutter/material/InkWell-class.html
        Material(
          type: MaterialType.transparency,
          // Связь заходит на соседние шаги, поэтому обход по положению на
          // экране поставил бы шаг ниже связи раньше неё.
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: _PathRows(
              children: [
                _StepRow(
                  step: source,
                  archivedBadge: archivedBadge,
                  rail: _Rail(
                    glyph: glyph(source, PathGlyphShape.diamond, end),
                    below: line(links.first.relation),
                  ),
                ),
                for (final (index, link) in links.indexed) ...[
                  _RelationRow(
                    relation: link.relation,
                    line: line(link.relation),
                    word: kindWord(link.relation.kind),
                    archivedBadge: archivedBadge,
                  ),
                  _StepRow(
                    step: link.step,
                    archivedBadge: archivedBadge,
                    rail: _Rail(
                      above: line(link.relation),
                      glyph: index == links.length - 1
                          ? glyph(link.step, PathGlyphShape.circle, end)
                          : glyph(link.step, PathGlyphShape.ring, tone),
                      below: index == links.length - 1
                          ? null
                          : line(links[index + 1].relation),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasArchive)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: _nameInset,
              top: 10,
            ),
            child: Text(
              archivedNote,
              style: DoableType.hint.copyWith(color: colors.muted),
            ),
          ),
      ],
    );
  }
}

const _railWidth = 22.0;
const _glyphSize = 14.0;

/// Глиф стоит против середины первой строки шага высотой `tap-min`.
const _aboveGlyph = 15.0;

/// Название начинается за рейкой и `space-3`.
const _nameInset = _railWidth + DoableMetrics.space3;

/// На столько строка связи заходит на шаг выше и на шаг ниже: кнопка связи не
/// ниже `tap-min`, а между шагами остаётся 30.
const _relationOverlap = (DoableMetrics.tapMin - 30) / 2;

/// Строки пути сверху вниз: шаг, связь, шаг и так далее, поэтому у связей
/// нечётные индексы.
///
/// Обычный столбец здесь не подходит. Он проверяет нажатие с последней строки,
/// поэтому шаг под связью забрал бы её нижнюю полосу, а за границу своей
/// строки кнопка нажатий не получает. Здесь строка связи целиком лежит внутри
/// столбца поверх соседних шагов и проверяется раньше них. Мимо кнопки связи
/// нажатие проходит к шагу.
final class _PathRows extends MultiChildRenderObjectWidget {
  const _PathRows({required super.children});

  @override
  _RenderPathRows createRenderObject(BuildContext context) => _RenderPathRows();
}

final class _PathRowsParentData extends ContainerBoxParentData<RenderBox> {}

final class _RenderPathRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PathRowsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PathRowsParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PathRowsParentData) {
      child.parentData = _PathRowsParentData();
    }
  }

  @override
  void performLayout() {
    final rowConstraints = BoxConstraints.tightFor(width: constraints.maxWidth);
    var height = 0.0;
    for (final (index, row) in getChildrenAsList().indexed) {
      row.layout(rowConstraints, parentUsesSize: true);
      final overlap = index.isOdd ? _relationOverlap : 0.0;
      (row.parentData! as _PathRowsParentData).offset = Offset(
        0,
        height - overlap,
      );
      height += row.size.height - overlap * 2;
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final rows = getChildrenAsList();
    final relationsFirst = [
      for (var index = 1; index < rows.length; index += 2) rows[index],
      for (var index = 0; index < rows.length; index += 2) rows[index],
    ];
    for (final row in relationsFirst) {
      final offset = (row.parentData! as _PathRowsParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) =>
            row.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}

/// Рейка шага: глиф с линиями над ним и под ним. У концов пути одной из линий
/// нет.
final class _Rail extends StatelessWidget {
  const _Rail({required this.glyph, this.above, this.below});

  final PathGlyph glyph;
  final RelationStrokeKind? above;
  final RelationStrokeKind? below;

  @override
  Widget build(BuildContext context) {
    final above = this.above;
    final below = this.below;
    return ExcludeSemantics(
      child: Column(
        children: [
          SizedBox(
            height: _aboveGlyph,
            child: above == null ? null : _stroke(above),
          ),
          SizedBox.square(
            dimension: _glyphSize,
            child: Center(child: glyph),
          ),
          Expanded(child: below == null ? const SizedBox() : _stroke(below)),
        ],
      ),
    );
  }
}

Widget _stroke(RelationStrokeKind kind) =>
    RelationStroke(kind: kind, axis: RelationStrokeAxis.vertical);

final class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.rail,
    required this.archivedBadge,
  });

  final ChoicePathStep step;
  final _Rail rail;
  final Widget archivedBadge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return _Button(
      key: step.buttonKey,
      label: step.semanticLabel,
      onTap: step.onOpen,
      radius: DoableMetrics.radiusSm,
      builder: (showsFocus) => _FocusRing(
        radius: DoableMetrics.radiusSm,
        shown: showsFocus,
        // Высоту задаёт текст, а рейка тянется по ней. `IntrinsicHeight` не
        // подходит: `Wrap` не учитывает перенос длинного названия внутри своего
        // ребёнка и занижает высоту, поэтому текст вылез бы вниз.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DoableMetrics.tapMin),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: _nameInset,
                  top: 11,
                  bottom: 11,
                ),
                // Метка переносится вместе с длинным названием на следующую
                // строку.
                child: Wrap(
                  spacing: DoableMetrics.space2,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      step.name,
                      style: DoableType.action.copyWith(
                        color: step.archived ? colors.muted : colors.ink,
                      ),
                    ),
                    if (step.archived) archivedBadge,
                  ],
                ),
              ),
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: _railWidth,
                child: rail,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка связи: линия в рейке и кнопка с плиткой и словом. Строка выше
/// видимой на [_relationOverlap] с обеих сторон, а линия занимает только
/// видимую часть. Крупный шрифт растит кнопку и строку вместе с ней.
final class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.relation,
    required this.line,
    required this.word,
    required this.archivedBadge,
  });

  final ChoicePathRelation relation;
  final RelationStrokeKind line;
  final String word;
  final Widget archivedBadge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: _railWidth),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            heightFactor: 1,
            child: _Button(
              key: relation.buttonKey,
              label: relation.semanticLabel,
              onTap: relation.onOpen,
              radius: DoableMetrics.tapMin / 2,
              builder: (showsFocus) => ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DoableMetrics.tapMin,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DoableMetrics.space3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: DoableMetrics.space2,
                    children: [
                      _FocusRing(
                        radius: _RelationTile.size / 2,
                        shown: showsFocus,
                        child: _RelationTile(
                          priority: relation.priority,
                          archived: relation.archived,
                        ),
                      ),
                      Flexible(
                        child: Wrap(
                          spacing: DoableMetrics.space2,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              word,
                              style: DoableType.caption.copyWith(
                                color: colors.muted,
                              ),
                            ),
                            if (relation.archived) archivedBadge,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: 0,
          top: _relationOverlap,
          bottom: _relationOverlap,
          width: _railWidth,
          child: ExcludeSemantics(
            child: Column(children: [Expanded(child: _stroke(line))]),
          ),
        ),
      ],
    );
  }
}

/// Круглая плитка 26 со значком связи: подкраска цвета приоритета связи, у
/// `p4` и архивированной связи — `fill`.
final class _RelationTile extends StatelessWidget {
  const _RelationTile({required this.priority, required this.archived});

  final DoablePriority priority;
  final bool archived;

  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final color = priority.color(colors);
    final plain = archived || priority == DoablePriority.p4;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: plain ? colors.fill : color.withValues(alpha: .12),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: DoableIcon(
            DoableIconData.relationMini,
            size: 16,
            color: archived ? colors.muted : color,
          ),
        ),
      ),
    );
  }
}

/// Кнопка пути: одна область нажатия с названием для диктора. Кольцо фокуса
/// клавиатуры рисует содержимое по признаку, который получает от кнопки.
final class _Button extends StatefulWidget {
  const _Button({
    required this.label,
    required this.onTap,
    required this.radius,
    required this.builder,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final double radius;
  final Widget Function(bool showsFocus) builder;

  @override
  State<_Button> createState() => _ButtonState();
}

final class _ButtonState extends State<_Button> {
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
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    return MergeSemantics(
      child: Semantics(
        label: widget.label,
        button: true,
        enabled: true,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(widget.radius),
          focusColor: Colors.transparent,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: ExcludeSemantics(child: widget.builder(showsFocus)),
        ),
      ),
    );
  }
}

/// `focus-ring` дизайн-системы вокруг [child]: зазор `bg` в 2, затем `accent`
/// в 2. Кольцо лежит снаружи содержимого: тень легла бы сплошным слоем на
/// плоскость пути.
final class _FocusRing extends StatelessWidget {
  const _FocusRing({
    required this.radius,
    required this.shown,
    required this.child,
  });

  final double radius;
  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return CustomPaint(
      foregroundPainter: shown
          ? _FocusRingPainter(
              ring: colors.accent,
              gap: colors.bg,
              radius: radius,
            )
          : null,
      child: child,
    );
  }
}

final class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({
    required this.ring,
    required this.gap,
    required this.radius,
  });

  final Color ring;
  final Color gap;
  final double radius;

  static const double _width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final area = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas
      ..drawRRect(
        area.inflate(_width / 2),
        Paint()
          ..color = gap
          ..style = PaintingStyle.stroke
          ..strokeWidth = _width,
      )
      ..drawRRect(
        area.inflate(_width * 1.5),
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = _width,
      );
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) =>
      ring != oldDelegate.ring ||
      gap != oldDelegate.gap ||
      radius != oldDelegate.radius;
}
