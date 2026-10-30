import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import 'badge.dart';
import 'row_text.dart';
import 'tag_chip.dart';

/// Строка экрана выбора: нажатие на текст выбирает элемент, а стрелка справа
/// открывает его страницу. Экранный диктор видит две кнопки с готовыми
/// названиями; текст, метки и теги называет [label].
final class PickerRow extends StatelessWidget {
  const PickerRow({
    required this.name,
    required this.label,
    required this.onPick,
    required this.pageLabel,
    required this.onOpenPage,
    this.description,
    this.archived = false,
    this.marks = const [],
    this.tags = const [],
    super.key,
  });

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

  /// Доступное название области выбора.
  final String label;
  final VoidCallback onPick;

  /// Доступное название стрелки.
  final String pageLabel;
  final VoidCallback onOpenPage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return Material(
      color: colors.fill,
      borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Area(
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
}

/// Область нажатия строки — одна кнопка экранного диктора с [label].
final class _Area extends StatelessWidget {
  const _Area({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(child: child),
      ),
    ),
  );
}
