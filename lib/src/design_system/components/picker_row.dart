import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'badge.dart';
import 'row_text.dart';
import 'tag_chip.dart';

/// Строка экрана выбора: нажатие на текст выбирает элемент, а стрелка справа
/// открывает его страницу. Названия областей для экранного диктора задаёт
/// потребитель.
final class PickerRow extends StatelessWidget {
  const PickerRow({
    required this.name,
    required String label,
    required VoidCallback onPick,
    required this.pageLabel,
    required this.onOpenPage,
    this.description,
    this.archived = false,
    this.marks = const [],
    this.tags = const [],
    super.key,
  }) : // Имена параметров остаются открытыми при закрытых полях вариантов.
       // ignore: prefer_initializing_formals
       _label = label,
       // ignore: prefer_initializing_formals
       _onPick = onPick,
       _chosen = null,
       _reason = null;

  const PickerRow.checkable({
    required this.name,
    required String label,
    required bool chosen,
    required VoidCallback onPick,
    required this.pageLabel,
    required this.onOpenPage,
    this.description,
    this.archived = false,
    this.marks = const [],
    this.tags = const [],
    super.key,
  }) : // Публичные параметры сохраняют свои имена.
       // ignore: prefer_initializing_formals
       _label = label,
       // ignore: prefer_initializing_formals
       _onPick = onPick,
       // ignore: prefer_initializing_formals
       _chosen = chosen,
       _reason = null;

  const PickerRow.occupied({
    required this.name,
    required String reason,
    required this.pageLabel,
    required this.onOpenPage,
    super.key,
  }) : description = null,
       archived = false,
       marks = const [],
       tags = const [],
       _label = null,
       _onPick = null,
       _chosen = null,
       // ignore: prefer_initializing_formals
       _reason = reason;

  /// Название переносится и не обрезается.
  final String name;

  /// Описание под названием, не длиннее двух строк.
  final String? description;

  /// Название архивированного элемента приглушено; метки строки передаёт
  /// потребитель.
  final bool archived;

  /// Метки и все теги в порядке показа; без них у строки нет линии меток и
  /// тегов.
  final List<Badge> marks;
  final List<TagChip> tags;

  final String? _label;
  final VoidCallback? _onPick;
  final bool? _chosen;
  final String? _reason;

  /// Название и действие области выбора у незанятых строк.
  String get label => _label!;
  VoidCallback get onPick => _onPick!;

  _PickerBehavior get _behavior => switch ((_reason, _chosen)) {
    (final reason?, _) => _Occupied(reason),
    (_, final chosen?) => _Check(_label!, _onPick!, chosen),
    _ => _Pick(_label!, _onPick!),
  };

  /// Доступное название стрелки.
  final String pageLabel;
  final VoidCallback onOpenPage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return Material(
      color: _behavior is _Occupied ? Colors.transparent : colors.fill,
      shape: _behavior is _Occupied
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
              side: BorderSide(color: colors.hairline),
            )
          : null,
      borderRadius: _behavior is _Occupied
          ? null
          : BorderRadius.circular(DoableMetrics.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: switch (_behavior) {
                _Pick(:final label, :final onPick) => _Area(
                  label: label,
                  onTap: onPick,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      DoableMetrics.space4,
                      11,
                      0,
                      DoableMetrics.space3,
                    ),
                    child: RowText(
                      name: name,
                      description: description,
                      archived: archived,
                      marks: marks,
                      tags: tags,
                    ),
                  ),
                ),
                _Check(:final label, :final onPick, :final chosen) => _Area(
                  label: label,
                  onTap: onPick,
                  checked: chosen,
                  child: _leadingContent(
                    _CheckMark(chosen: chosen),
                    RowText(
                      name: name,
                      description: description,
                      archived: archived,
                      marks: marks,
                      tags: tags,
                    ),
                  ),
                ),
                _Occupied(:final reason) => _leadingContent(
                  Center(
                    child: DoableIcon(
                      DoableIconData.relation,
                      size: 18,
                      color: colors.grip,
                    ),
                  ),
                  MergeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: DoableType.action.copyWith(
                            color: colors.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reason,
                          style: DoableType.label.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              },
            ),
            SizedBox(
              width: 48,
              child: _Area(
                label: pageLabel,
                onTap: onOpenPage,
                // Стрелка стоит по центру области без её правого поля 4,
                // как в макете.
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    end: DoableMetrics.space1,
                  ),
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
    );
  }

  Widget _leadingContent(Widget leading, Widget content) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(
      14,
      11,
      0,
      DoableMetrics.space3,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(dimension: 22, child: leading),
        const SizedBox(width: DoableMetrics.space3),
        Expanded(child: content),
      ],
    ),
  );
}

sealed class _PickerBehavior {
  const _PickerBehavior();
}

final class _Pick extends _PickerBehavior {
  const _Pick(this.label, this.onPick);
  final String label;
  final VoidCallback onPick;
}

final class _Check extends _PickerBehavior {
  const _Check(this.label, this.onPick, this.chosen);
  final String label;
  final VoidCallback onPick;
  final bool chosen;
}

final class _Occupied extends _PickerBehavior {
  const _Occupied(this.reason);
  final String reason;
}

final class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.chosen});
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: chosen ? colors.accent : null,
        border: chosen ? null : Border.all(color: colors.grip, width: 2),
      ),
      child: chosen
          ? Center(
              child: CustomPaint(
                size: const Size.square(14),
                painter: _CheckPainter(colors.onAccent),
              ),
            )
          : null,
    );
  }
}

final class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      Path()
        ..moveTo(5, 12.5)
        ..lineTo(9.5, 17)
        ..lineTo(19, 7.5),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}

/// Область нажатия строки — одна кнопка экранного диктора с [label].
final class _Area extends StatelessWidget {
  const _Area({
    required this.label,
    required this.onTap,
    required this.child,
    this.checked,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool? checked;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: checked == null ? true : null,
      checked: checked,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(child: child),
      ),
    ),
  );
}
