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
enum ActionPathRelationKind { need, can }

/// Намерение в сохранённом пути: существующее открывается, удалённое остаётся
/// на месте таким, каким было при удалении, и ничего не открывает.
sealed class ActionPathStep {
  const ActionPathStep._({required this.name});

  /// Название намерения; у удалённого — то, что хранит надгробие.
  final String name;

  /// Существующее намерение, активное или архивное.
  const factory ActionPathStep.existing({
    required String name,
    required String semanticLabel,
    required VoidCallback onOpen,
    bool archived,
    Key? buttonKey,
  }) = ActionPathExistingStep;

  /// Намерение, удалённое после сохранения пути.
  const factory ActionPathStep.deleted({required String name}) =
      ActionPathDeletedStep;
}

final class ActionPathExistingStep extends ActionPathStep {
  const ActionPathExistingStep({
    required super.name,
    required this.semanticLabel,
    required this.onOpen,
    this.archived = false,
    this.buttonKey,
  }) : super._();

  /// Доступное название кнопки шага.
  final String semanticLabel;

  /// Открывает страницу намерения.
  final VoidCallback onOpen;

  /// Намерение архивировано: имя `muted`, глиф `grip`, а после имени метка.
  final bool archived;

  /// Ключ кнопки шага.
  final Key? buttonKey;
}

final class ActionPathDeletedStep extends ActionPathStep {
  const ActionPathDeletedStep({required super.name}) : super._();
}

/// Связь между двумя соседними намерениями сохранённого пути: существующая
/// открывается, удалённая остаётся на месте с типом на момент удаления.
sealed class ActionPathRelation {
  const ActionPathRelation._({required this.kind});

  final ActionPathRelationKind kind;

  /// Существующая связь пары, активная или архивная.
  const factory ActionPathRelation.existing({
    required ActionPathRelationKind kind,
    required DoablePriority priority,
    required String semanticLabel,
    required VoidCallback onOpen,
    bool archived,
    Key? buttonKey,
  }) = ActionPathExistingRelation;

  /// Связь, удалённая после сохранения пути; её приоритета не сохранилось.
  const factory ActionPathRelation.deleted({
    required ActionPathRelationKind kind,
  }) = ActionPathDeletedRelation;
}

final class ActionPathExistingRelation extends ActionPathRelation {
  const ActionPathExistingRelation({
    required super.kind,
    required this.priority,
    required this.semanticLabel,
    required this.onOpen,
    this.archived = false,
    this.buttonKey,
  }) : super._();

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

final class ActionPathDeletedRelation extends ActionPathRelation {
  const ActionPathDeletedRelation({required super.kind}) : super._();
}

/// Связь и намерение, к которому она ведёт от предыдущего.
final class ActionPathLink {
  const ActionPathLink({required this.relation, required this.step});

  final ActionPathRelation relation;
  final ActionPathStep step;
}

/// Строки под путём, в котором что-то архивировано или удалено.
final class ActionPathNotes {
  const ActionPathNotes({
    required this.archived,
    required this.deleted,
    required this.archivedAndDeleted,
  });

  /// В пути есть архивные намерения или связи.
  final String archived;

  /// В пути есть удалённые намерения или связи.
  final String deleted;

  /// В пути есть и архивные, и удалённые.
  final String archivedAndDeleted;
}

/// Сохранённый путь действия целиком: каждое намерение от корневого до
/// конечного и каждая связь между ними. Самого действия в конце нет.
///
/// Намерение — строка не ниже `tap-min`: глиф в рейке шириной 22 и название
/// `action` за `space-3` от неё. Ромб — корневое намерение, кольцо — каждое
/// промежуточное, жирное кольцо — конечное, то есть последняя причина. Путь
/// из одного намерения — один ромб. Название переносится, глиф остаётся на
/// первой строке, а линия под ним тянется. Путь не сокращается и не
/// прокручивается сам: длинный путь прокручивает родитель.
///
/// Связь — строка высотой 30, через рейку которой проходит её линия, а рядом
/// стоят плитка цвета приоритета самой связи и слово вида. Ромб и жирное кольцо
/// цвета [priority], линии и кольца между ними — он же пополам с `grip`, а у
/// выполненного действия все они `grip`.
///
/// Путь — копия, сохранённая вместе с действием. Архивные намерения и связи
/// остаются на месте приглушёнными с меткой [archivedBadge]. Удалённые
/// остаются так же, с меткой [deletedBadge], и не нажимаются. Тексты, метки,
/// ключи, обработчики и доступные названия задаёт потребитель. Родитель задаёт
/// ширину.
final class ActionPath extends StatelessWidget {
  const ActionPath({
    required this.root,
    required this.priority,
    required this.kindWord,
    required this.archivedBadge,
    required this.deletedBadge,
    required this.notes,
    this.links = const [],
    this.done = false,
    super.key,
  });

  /// Корневое намерение.
  final ActionPathStep root;

  /// Остальные намерения в порядке пути, каждое со связью к нему; последнее —
  /// конечное. У пути из одного намерения связей нет.
  final List<ActionPathLink> links;

  /// Приоритет действия: цвет ромба и жирного кольца, линий и колец между
  /// ними.
  final DoablePriority priority;

  /// Действие выполнено.
  final bool done;

  /// Слово вида рядом с плиткой.
  final String Function(ActionPathRelationKind kind) kindWord;

  /// Метка после каждого архивного намерения и связи.
  final Widget archivedBadge;

  /// Метка после каждого удалённого намерения и связи.
  final Widget deletedBadge;

  /// Строки под путём.
  final ActionPathNotes notes;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final end = done ? colors.grip : priority.color(colors);
    final tone = done ? colors.grip : Color.lerp(end, colors.grip, .5)!;
    final steps = [root, for (final link in links) link.step];
    final relations = [for (final link in links) link.relation];
    final hasArchive =
        steps.any(_isArchived) || relations.any(_isArchivedRelation);
    final hasDeleted =
        steps.any((step) => step is ActionPathDeletedStep) ||
        relations.any((relation) => relation is ActionPathDeletedRelation);

    RelationStrokeKind line(ActionPathRelation relation) {
      final color = _isGoneRelation(relation) ? colors.grip : tone;
      return switch (relation.kind) {
        ActionPathRelationKind.need => RelationStrokeKind.need(color),
        ActionPathRelationKind.can => RelationStrokeKind.can(color),
      };
    }

    PathGlyph glyph(ActionPathStep step, PathGlyphShape shape, Color color) =>
        PathGlyph(
          shape: shape,
          outline: PathGlyphOutline.solid,
          size: _glyphSize,
          color: _isGoneStep(step) ? colors.grip : color,
        );

    final note = switch ((hasArchive, hasDeleted)) {
      (false, false) => null,
      (true, false) => notes.archived,
      (false, true) => notes.deleted,
      (true, true) => notes.archivedAndDeleted,
    };

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
                  step: root,
                  archivedBadge: archivedBadge,
                  deletedBadge: deletedBadge,
                  rail: _Rail(
                    glyph: glyph(root, PathGlyphShape.diamond, end),
                    below: links.isEmpty ? null : line(links.first.relation),
                  ),
                ),
                for (final (index, link) in links.indexed) ...[
                  _RelationRow(
                    relation: link.relation,
                    line: line(link.relation),
                    word: kindWord(link.relation.kind),
                    archivedBadge: archivedBadge,
                    deletedBadge: deletedBadge,
                  ),
                  _StepRow(
                    step: link.step,
                    archivedBadge: archivedBadge,
                    deletedBadge: deletedBadge,
                    rail: _Rail(
                      above: line(link.relation),
                      glyph: index == links.length - 1
                          ? glyph(link.step, PathGlyphShape.finalRing, end)
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
        if (note != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: _nameInset,
              top: 10,
            ),
            child: Text(
              note,
              style: DoableType.hint.copyWith(color: colors.muted),
            ),
          ),
      ],
    );
  }
}

bool _isArchived(ActionPathStep step) =>
    step is ActionPathExistingStep && step.archived;

bool _isArchivedRelation(ActionPathRelation relation) =>
    relation is ActionPathExistingRelation && relation.archived;

bool _isGoneStep(ActionPathStep step) =>
    _isArchived(step) || step is ActionPathDeletedStep;

/// Архивная или удалённая связь рисуется серой.
bool _isGoneRelation(ActionPathRelation relation) =>
    _isArchivedRelation(relation) || relation is ActionPathDeletedRelation;

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
    required this.deletedBadge,
  });

  final ActionPathStep step;
  final _Rail rail;
  final Widget archivedBadge;
  final Widget deletedBadge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final gone = _isGoneStep(step);

    // Высоту задаёт текст, а рейка тянется по ней. `IntrinsicHeight` не
    // подходит: `Wrap` не учитывает перенос длинного названия внутри своего
    // ребёнка и занижает высоту, поэтому текст вылез бы вниз.
    Widget content() => ConstrainedBox(
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
                    color: gone ? colors.muted : colors.ink,
                  ),
                ),
                switch (step) {
                  ActionPathExistingStep(archived: true) => archivedBadge,
                  ActionPathDeletedStep() => deletedBadge,
                  ActionPathExistingStep() => const SizedBox.shrink(),
                },
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
    );

    return switch (step) {
      ActionPathExistingStep(
        :final semanticLabel,
        :final onOpen,
        :final buttonKey,
      ) =>
        _Button(
          key: buttonKey,
          label: semanticLabel,
          onTap: onOpen,
          radius: DoableMetrics.radiusSm,
          builder: (showsFocus) => _FocusRing(
            radius: DoableMetrics.radiusSm,
            shown: showsFocus,
            child: content(),
          ),
        ),
      // Название и метка читаются одним узлом, нажатия нет.
      ActionPathDeletedStep() => MergeSemantics(child: content()),
    };
  }
}

/// Строка связи: линия в рейке и кнопка с плиткой и словом. Строка выше
/// видимой на [_relationOverlap] с обеих сторон, а линия занимает только
/// видимую часть. Крупный шрифт растит кнопку и строку вместе с ней.
/// Удалённая связь выглядит так же, но не нажимается.
final class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.relation,
    required this.line,
    required this.word,
    required this.archivedBadge,
    required this.deletedBadge,
  });

  final ActionPathRelation relation;
  final RelationStrokeKind line;
  final String word;
  final Widget archivedBadge;
  final Widget deletedBadge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    Widget content({
      required bool showsFocus,
      required DoablePriority? priority,
      required Widget? badge,
    }) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: DoableMetrics.tapMin),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DoableMetrics.space2,
          children: [
            _FocusRing(
              radius: _RelationTile.size / 2,
              shown: showsFocus,
              child: _RelationTile(priority: priority),
            ),
            Flexible(
              child: Wrap(
                spacing: DoableMetrics.space2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    word,
                    style: DoableType.caption.copyWith(color: colors.muted),
                  ),
                  ?badge,
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final body = switch (relation) {
      ActionPathExistingRelation(
        :final priority,
        :final archived,
        :final semanticLabel,
        :final onOpen,
        :final buttonKey,
      ) =>
        _Button(
          key: buttonKey,
          label: semanticLabel,
          onTap: onOpen,
          radius: DoableMetrics.tapMin / 2,
          builder: (showsFocus) => content(
            showsFocus: showsFocus,
            // Плитка архивной связи простая, как у `p4`.
            priority: archived ? null : priority,
            badge: archived ? archivedBadge : null,
          ),
        ),
      // Слово и метка читаются одним узлом, нажатия нет.
      ActionPathDeletedRelation() => MergeSemantics(
        child: content(showsFocus: false, priority: null, badge: deletedBadge),
      ),
    };

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: _railWidth),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            heightFactor: 1,
            child: body,
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
/// `p4` и у связи без приоритета — архивной или удалённой — `fill` со значком
/// `muted`.
final class _RelationTile extends StatelessWidget {
  const _RelationTile({required this.priority});

  /// Приоритет самой связи; у архивной и удалённой связи его нет.
  final DoablePriority? priority;

  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final priority = this.priority;
    final color = priority?.color(colors);
    final plain = priority == null || priority == DoablePriority.p4;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: plain ? colors.fill : color!.withValues(alpha: .12),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: DoableIcon(
            DoableIconData.relationMini,
            size: 16,
            color: color ?? colors.muted,
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
