import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_metrics.dart';
import 'badge.dart';
import 'row_text.dart';
import 'tag_chip.dart';

/// Строка каталога: вся карточка — одна кнопка, открывающая страницу
/// элемента. Экранный диктор видит одну кнопку с готовым названием; текст,
/// метки и теги называет [label].
final class CatalogRow extends StatelessWidget {
  const CatalogRow({
    required this.name,
    required this.label,
    required this.onOpen,
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

  /// Доступное название кнопки.
  final String label;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return Material(
      color: colors.fill,
      borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: onOpen,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  DoableMetrics.space4,
                  11,
                  DoableMetrics.space4,
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
        ),
      ),
    );
  }
}
