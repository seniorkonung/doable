import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'badge.dart';
import 'relation_stroke.dart';

/// Вид связи на строке: сплошная метка — «нужно», пунктирная — «можно».
enum RelationRowKind { need, can }

/// Приоритет связи: от него зависят подкраска строки и цвет метки вида.
enum RelationRowPriority { p1, p2, p3, p4 }

/// Строка связи на странице намерения: вид и приоритет словами, название
/// намерения на другом конце и заметка.
///
/// Строка — две области нажатия. Строка целиком вызывает [onOpen], стрелка
/// справа шириной 48 на всю высоту строки — [onWalk]. Тексты, включая
/// готовую подпись вида и приоритета, и доступные названия областей задаёт
/// потребитель.
///
/// Архивированная связь серая: плоскость `fill`, метка `grip`, подпись и
/// название `muted`. Связь с архивированным соседом сохраняет цвет, но её
/// название `muted`; в приглушённой строке молния действия тоже `muted`.
final class RelationRow extends StatelessWidget {
  const RelationRow({
    required this.kind,
    required this.priority,
    required this.label,
    required this.name,
    required this.semanticLabel,
    required this.walkLabel,
    required this.onOpen,
    required this.onWalk,
    this.note,
    this.action = false,
    this.archived = false,
    this.intentionArchived = false,
    super.key,
  }) : assert(note != '');

  final RelationRowKind kind;
  final RelationRowPriority priority;

  /// Готовая подпись вида и приоритета, например «Нужно · P1».
  final String label;

  /// Название намерения на другом конце связи.
  final String name;

  /// Заметка связи; без неё последней строки нет.
  final String? note;

  /// Другой конец связи — действие.
  final bool action;

  /// Связь архивирована.
  final bool archived;

  /// Намерение на другом конце связи архивировано.
  final bool intentionArchived;

  /// Доступное название строки.
  final String semanticLabel;

  /// Доступное название стрелки.
  final String walkLabel;

  final VoidCallback onOpen;
  final VoidCallback onWalk;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(DoableMetrics.radiusLg),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final priorityColor = switch (priority) {
      RelationRowPriority.p1 => colors.p1,
      RelationRowPriority.p2 => colors.p2,
      RelationRowPriority.p3 => colors.p3,
      RelationRowPriority.p4 => colors.p4,
    };
    // Без подкраски остаются архивированная связь и p4.
    final plain = archived || priority == RelationRowPriority.p4;
    final dim = archived || intentionArchived;
    final markColor = plain ? colors.grip : priorityColor;
    final note = this.note;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: plain ? colors.fill : Color.lerp(colors.fill, priorityColor, .1),
        borderRadius: _radius,
      ),
      // Отклик нажатия рисуется на плоскости строки, а не под ней:
      // https://api.flutter.dev/flutter/material/InkWell-class.html
      child: Material(
        type: MaterialType.transparency,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TapArea(
                  label: semanticLabel,
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      DoableMetrics.space4,
                      9,
                      0,
                      11,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 2,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 20),
                          child: Row(
                            spacing: 6,
                            children: [
                              RelationKindMark(
                                kind: switch (kind) {
                                  RelationRowKind.need =>
                                    RelationStrokeKind.need(markColor),
                                  RelationRowKind.can => RelationStrokeKind.can(
                                    markColor,
                                  ),
                                },
                              ),
                              Flexible(
                                child: Padding(
                                  // Метки отстоят от подписи на 8: 6 между
                                  // элементами и 2 в запас у самой подписи,
                                  // как в вёрстке дизайн-системы.
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 2,
                                  ),
                                  child: Text(
                                    label,
                                    style: DoableType.label.copyWith(
                                      color: plain
                                          ? colors.muted
                                          : Color.lerp(
                                              colors.ink,
                                              priorityColor,
                                              .7,
                                            ),
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (intentionArchived)
                                const Badge.mark(
                                  icon: DoableIconData.archive,
                                  tone: BadgeTone.muted,
                                ),
                              if (action)
                                Badge.mark(
                                  icon: DoableIconData.bolt,
                                  tone: dim ? BadgeTone.muted : BadgeTone.ink,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          name,
                          style: DoableType.action.copyWith(
                            color: dim ? colors.muted : colors.ink,
                          ),
                        ),
                        if (note != null)
                          Text(
                            note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DoableType.note.copyWith(
                              color: colors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              _TapArea(
                label: walkLabel,
                onTap: onWalk,
                child: SizedBox(
                  width: 48,
                  child: Padding(
                    // Стрелка по центру 44 слева: справа остаётся поле в 4.
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Center(
                      child: DoableIcon(
                        DoableIconData.arrowUpRight,
                        size: 20,
                        color: colors.muted,
                      ),
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

/// Область нажатия строки с кольцом фокуса клавиатуры вокруг неё.
final class _TapArea extends StatefulWidget {
  const _TapArea({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TapArea> createState() => _TapAreaState();
}

final class _TapAreaState extends State<_TapArea> {
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

    return MergeSemantics(
      child: Semantics(
        label: widget.label,
        button: true,
        enabled: true,
        // Плоскость строки закрашена, поэтому тень `focus-ring` легла бы на
        // неё сплошным слоем: кольцо рисуется только снаружи области.
        child: CustomPaint(
          foregroundPainter: showsFocus
              ? _FocusRingPainter(ring: colors.accent, gap: colors.bg)
              : null,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: RelationRow._radius,
            focusColor: Colors.transparent,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: ExcludeSemantics(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// `focus-ring` дизайн-системы вокруг области: зазор `bg` в 2, затем `accent`
/// в 2.
final class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({required this.ring, required this.gap});

  final Color ring;
  final Color gap;

  static const double _width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final area = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(DoableMetrics.radiusLg),
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
      ring != oldDelegate.ring || gap != oldDelegate.gap;
}
