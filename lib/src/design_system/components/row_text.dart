import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'badge.dart';
import 'tag_chip.dart';
import 'tag_line.dart';

/// Колонка текста строки списка: название, описание и линия меток и тегов.
/// Её делят [PickerRow] и [CatalogRow]; поля и область нажатия задаёт строка.
final class RowText extends StatelessWidget {
  const RowText({
    required this.name,
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

  /// Название архивированного элемента приглушено.
  final bool archived;

  /// Метки и все теги в порядке показа; без них линии нет.
  final List<Badge> marks;
  final List<TagChip> tags;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: DoableType.action.copyWith(
            color: archived ? colors.muted : colors.ink,
          ),
        ),
        if (description case final description?) ...[
          const SizedBox(height: 2),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DoableType.note.copyWith(color: colors.muted),
          ),
        ],
        if (marks.isNotEmpty || tags.isNotEmpty) ...[
          const SizedBox(height: DoableMetrics.space2),
          TagLine(marks: marks, tags: tags),
        ],
      ],
    );
  }
}
