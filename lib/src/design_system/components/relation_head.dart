import 'dart:math' as math;

import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';
import 'badge.dart';
import 'edge_overhang.dart';
import 'path_glyph.dart';
import 'relation_stroke.dart';

/// Вид связи: «нужно» — сплошная линия, «можно» — пунктирная.
enum RelationHeadKind { need, can }

/// Намерение на одном из концов связи. Шапка его только показывает: другое
/// намерение у связи появиться не может.
final class RelationHeadParticipant {
  const RelationHeadParticipant({
    required this.name,
    required this.semanticLabel,
    required this.onOpen,
    this.archived = false,
  });

  final String name;

  /// Доступное название кнопки названия; архивность в него входит.
  final String semanticLabel;

  /// Открывает страницу намерения.
  final VoidCallback onOpen;

  /// Название приглушено, значок на рейке серый, а после названия стоит
  /// метка архива.
  final bool archived;
}

/// Переключатель вида двумя пилюлями: нажатие на другую пилюлю сообщает вид.
final class RelationHeadKindSwitch {
  const RelationHeadKindSwitch({required this.label, required this.onChange});

  /// Доступное название переключателя.
  final String label;

  /// Без обработчика пилюли недоступны: экранный диктор объявляет
  /// недоступность их состоянием.
  final ValueChanged<RelationHeadKind>? onChange;
}

/// Кнопка параметров связи.
final class RelationHeadMenu {
  const RelationHeadMenu({required this.label, required this.onOpen});

  /// Доступное название кнопки.
  final String label;

  final VoidCallback onOpen;
}

/// Состояние связи, которое показывает шапка.
sealed class RelationHeadStatus {
  const RelationHeadStatus();
}

/// Активная связь. С [kindSwitch] вид меняется нажатием, без него шапка
/// показывает вид плиткой и словом, как при изменении описания.
final class RelationHeadActive extends RelationHeadStatus {
  const RelationHeadActive({this.kindSwitch});

  final RelationHeadKindSwitch? kindSwitch;
}

/// Архивированная связь сохраняет вид до восстановления, поэтому
/// переключателя у неё нет. Все цвета шапки серые, а после слова вида стоит
/// метка архива.
final class RelationHeadArchived extends RelationHeadStatus {
  const RelationHeadArchived({this.note}) : assert(note != '');

  /// Строка под связью, которая объясняет состояние; без неё строки нет.
  final String? note;
}

/// Шапка подробного просмотра связи: два намерения, соединённые линией
/// связи, и вид между ними.
///
/// Рейка шириной 22 слева несёт ромб исходного намерения, линию и кольцо
/// связанного. Ромб и значок плитки вида берут цвет приоритета, линия и
/// кольцо — его тон: цвет пополам с `grip`. Три строки не ниже `tap-min`:
/// исходное намерение, вид и связанное намерение.
///
/// Область нажатия кнопки параметров выходит на 14 за край содержимого и
/// принимает касания там, пока родитель шапки шире её на эту полосу,
/// например поле содержимого листа с отступами.
final class RelationHead extends StatelessWidget {
  const RelationHead({
    required this.kind,
    required this.priority,
    required this.source,
    required this.target,
    required this.kindName,
    required this.archivedWord,
    this.status = const RelationHeadActive(),
    this.menu,
    super.key,
  });

  final RelationHeadKind kind;
  final DoablePriority priority;

  /// Исходное намерение связи стоит первым.
  final RelationHeadParticipant source;
  final RelationHeadParticipant target;
  final RelationHeadStatus status;

  /// Без [menu] кнопки параметров нет.
  final RelationHeadMenu? menu;

  /// Слово вида с заглавной буквы: подпись пилюли переключателя. Рядом с
  /// плиткой то же слово стоит в нижнем регистре.
  final String Function(RelationHeadKind kind) kindName;

  /// Слово метки архива.
  final String archivedWord;

  /// Насколько область нажатия кнопки параметров выходит за край.
  static const double _menuOverhang = 14;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final archived = status is RelationHeadArchived;
    final priorityColor = archived ? colors.grip : priority.color(colors);
    final tone = archived
        ? colors.grip
        : Color.lerp(priorityColor, colors.grip, .5)!;
    final line = switch (kind) {
      RelationHeadKind.need => RelationStrokeKind.need(tone),
      RelationHeadKind.can => RelationStrokeKind.can(tone),
    };
    final menu = this.menu;
    final endInset = menu == null ? 0.0 : _menuOverhang;

    final head = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ParticipantRow(
          rail: _Rail(
            glyph: PathGlyph(
              shape: PathGlyphShape.diamond,
              outline: PathGlyphOutline.solid,
              size: _glyphSize,
              color: source.archived ? colors.grip : priorityColor,
            ),
            below: line,
          ),
          participant: source,
          archivedWord: archivedWord,
          endInset: endInset,
        ),
        _KindRow(
          kind: kind,
          priority: priority,
          priorityColor: priorityColor,
          tone: tone,
          line: line,
          status: status,
          menu: menu,
          kindName: kindName,
          archivedWord: archivedWord,
        ),
        _ParticipantRow(
          rail: _Rail(
            above: line,
            glyph: PathGlyph(
              shape: PathGlyphShape.ring,
              outline: PathGlyphOutline.solid,
              size: _glyphSize,
              color: target.archived ? colors.grip : tone,
            ),
          ),
          participant: target,
          archivedWord: archivedWord,
          endInset: endInset,
        ),
        if (status case RelationHeadArchived(:final note?))
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: _noteInset,
              top: 2,
              end: endInset,
            ),
            child: Text(
              note,
              style: DoableType.hint.copyWith(color: colors.muted),
            ),
          ),
      ],
    );
    return menu == null ? head : EdgeOverhang(end: _menuOverhang, child: head);
  }
}

const _railWidth = 22.0;
const _glyphSize = 14.0;

/// Ромб и кольцо стоят против середины первой строки названия высотой 44.
const _aboveGlyph = 15.0;

/// Строка под связью начинается на одной линии с названиями: рейка и
/// space-3.
const _noteInset = _railWidth + DoableMetrics.space3;

/// Рейка строки намерения: глиф с линией над ним или под ним.
final class _Rail extends StatelessWidget {
  const _Rail({required this.glyph, this.above, this.below});

  final PathGlyph glyph;
  final RelationStrokeKind? above;
  final RelationStrokeKind? below;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _railWidth,
    child: ExcludeSemantics(
      child: Column(
        children: [
          SizedBox(
            height: _aboveGlyph,
            child: switch (above) {
              final above? => RelationStroke(
                kind: above,
                axis: RelationStrokeAxis.vertical,
              ),
              null => null,
            },
          ),
          SizedBox.square(
            dimension: _glyphSize,
            child: Center(child: glyph),
          ),
          Expanded(
            child: switch (below) {
              final below? => RelationStroke(
                kind: below,
                axis: RelationStrokeAxis.vertical,
              ),
              null => const SizedBox(),
            },
          ),
        ],
      ),
    ),
  );
}

final class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.rail,
    required this.participant,
    required this.archivedWord,
    required this.endInset,
  });

  final _Rail rail;
  final RelationHeadParticipant participant;
  final String archivedWord;
  final double endInset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: DoableMetrics.tapMin),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rail,
            Expanded(
              // Полоса за краем принадлежит кнопке параметров, а не названию.
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: endInset),
                child: MergeSemantics(
                  child: Semantics(
                    button: true,
                    label: participant.semanticLabel,
                    child: _Control(
                      onTap: participant.onOpen,
                      radius: DoableMetrics.radiusSm,
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: DoableMetrics.space3,
                            top: 11,
                            bottom: 11,
                          ),
                          // Метка архива переносится вместе с длинным
                          // названием на следующую строку.
                          child: Wrap(
                            spacing: DoableMetrics.space2,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                participant.name,
                                style: DoableType.title.copyWith(
                                  color: participant.archived
                                      ? colors.muted
                                      : colors.ink,
                                ),
                              ),
                              if (participant.archived)
                                Badge.archived(word: archivedWord),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.priority,
    required this.priorityColor,
    required this.tone,
    required this.line,
    required this.status,
    required this.menu,
    required this.kindName,
    required this.archivedWord,
  });

  final RelationHeadKind kind;
  final DoablePriority priority;
  final Color priorityColor;
  final Color tone;
  final RelationStrokeKind line;
  final RelationHeadStatus status;
  final RelationHeadMenu? menu;
  final String Function(RelationHeadKind kind) kindName;
  final String archivedWord;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final archived = status is RelationHeadArchived;
    final menu = this.menu;

    final content = switch (status) {
      RelationHeadActive(kindSwitch: final kindSwitch?) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 6),
        child: _KindSwitch(
          kindSwitch: kindSwitch,
          kind: kind,
          tone: tone,
          kindName: kindName,
          grip: colors.grip,
        ),
      ),
      RelationHeadActive(kindSwitch: null) || RelationHeadArchived() => Padding(
        padding: const EdgeInsetsDirectional.only(start: DoableMetrics.space3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DoableMetrics.space2,
          children: [
            _KindTile(
              priority: priority,
              color: priorityColor,
              archived: archived,
            ),
            Flexible(
              child: Text(
                kindName(kind).toLowerCase(),
                style: DoableType.section.copyWith(
                  color: archived ? colors.muted : colors.ink,
                ),
              ),
            ),
            if (archived) Badge.archived(word: archivedWord),
          ],
        ),
      ),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: DoableMetrics.tapMin),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _railWidth,
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Expanded(
                      child: RelationStroke(
                        kind: line,
                        axis: RelationStrokeAxis.vertical,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: content,
              ),
            ),
            if (menu != null)
              MergeSemantics(
                child: Semantics(
                  button: true,
                  label: menu.label,
                  child: _Control(
                    onTap: menu.onOpen,
                    radius: DoableMetrics.tapMin / 2,
                    child: SizedBox.square(
                      dimension: DoableMetrics.tapMin,
                      child: Center(
                        child: ExcludeSemantics(
                          child: DoableIcon(
                            DoableIconData.more,
                            size: DoableMetrics.iconSize,
                            color: colors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Круглая плитка 26 со значком связи: подкраска цвета приоритета, у `p4` и
/// архивированной связи — `fill`.
final class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.priority,
    required this.color,
    required this.archived,
  });

  final DoablePriority priority;
  final Color color;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final plain = archived || priority == DoablePriority.p4;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: plain ? colors.fill : color.withValues(alpha: .12),
        ),
        child: SizedBox.square(
          dimension: 26,
          child: Center(
            child: DoableIcon(
              DoableIconData.relationMini,
              size: 16,
              color: archived ? colors.muted : color,
            ),
          ),
        ),
      ),
    );
  }
}

final class _KindSwitch extends StatelessWidget {
  const _KindSwitch({
    required this.kindSwitch,
    required this.kind,
    required this.tone,
    required this.kindName,
    required this.grip,
  });

  final RelationHeadKindSwitch kindSwitch;
  final RelationHeadKind kind;
  final Color tone;
  final String Function(RelationHeadKind kind) kindName;
  final Color grip;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: kindSwitch.label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DoableMetrics.space1,
      children: [
        for (final option in RelationHeadKind.values)
          _KindPill(
            name: kindName(option),
            chosen: option == kind,
            mark: switch (option) {
              RelationHeadKind.need => RelationStrokeKind.need(
                option == kind ? tone : grip,
              ),
              RelationHeadKind.can => RelationStrokeKind.can(
                option == kind ? tone : grip,
              ),
            },
            onTap: switch (kindSwitch.onChange) {
              null => null,
              final onChange => () {
                if (option != kind) onChange(option);
              },
            },
          ),
      ],
    ),
  );
}

/// Пилюля переключателя: отметка вида и слово. Выбранная лежит на `fill`.
final class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.name,
    required this.chosen,
    required this.mark,
    required this.onTap,
  });

  final String name;
  final bool chosen;
  final RelationStrokeKind mark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onTap != null,
        toggled: chosen,
        label: name,
        child: _Control(
          onTap: onTap,
          radius: DoableMetrics.radiusFull,
          // Пилюля 36 лежит в области нажатия tap-min.
          tapPadding: const EdgeInsets.symmetric(vertical: 4),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DoableMetrics.controlHeightSm,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: chosen ? colors.fill : null,
                  borderRadius: BorderRadius.circular(DoableMetrics.radiusFull),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: DoableMetrics.space3,
                    end: 14,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 7,
                    children: [
                      RelationKindMark(kind: mark),
                      Text(
                        name,
                        style: DoableType.section.copyWith(
                          color: chosen ? colors.ink : colors.muted,
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
    );
  }
}

/// Область нажатия с откликом и кольцом фокуса `focus-ring` вокруг
/// [child] при управлении с клавиатуры.
final class _Control extends StatefulWidget {
  const _Control({
    required this.onTap,
    required this.radius,
    required this.child,
    this.tapPadding = EdgeInsets.zero,
  });

  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets tapPadding;
  final Widget child;

  @override
  State<_Control> createState() => _ControlState();
}

final class _ControlState extends State<_Control> {
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
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    // Отклик нажатия рисуется на собственном Material, поэтому родитель
    // обрезает его вместе с областью:
    // https://api.flutter.dev/flutter/material/InkWell-class.html
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        focusColor: Colors.transparent,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Padding(
          padding: widget.tapPadding,
          // Плоскость прозрачна, поэтому тень `focus-ring` легла бы на неё
          // сплошным слоем: кольцо рисуется только снаружи.
          child: CustomPaint(
            foregroundPainter: showsFocus
                ? _FocusRingPainter(
                    ring: colors.accent,
                    gap: colors.bg,
                    radius: widget.radius,
                  )
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// `focus-ring` дизайн-системы вокруг области: зазор `bg` в 2, затем
/// `accent` в 2.
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
      Radius.circular(math.min(radius, size.shortestSide / 2)),
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
