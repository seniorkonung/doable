import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../doable_metrics.dart';
import 'add_row.dart';
import 'tag_chip.dart';

/// Теги намерения: шапка с заголовком и «Добавить», а под ней чипы тегов.
/// Без чипов блок состоит из одной шапки.
final class TagsSection extends StatelessWidget {
  static const double _bottomGap = 6;

  /// Без обработчика «Добавить» выключено и остаётся на своём месте.
  const TagsSection({
    required this.title,
    required this.addText,
    required this.addLabel,
    required this.onAdd,
    required this.chips,
    this.addKey,
    super.key,
  });

  final String title;

  /// Видимая подпись «Добавить».
  final String addText;

  /// Доступное название «Добавить»; его составляет потребитель.
  final String addLabel;

  final VoidCallback? onAdd;

  /// Ключ области нажатия «Добавить», а не всего блока.
  final Key? addKey;

  /// Чипы формы в порядке, в котором теги назначены.
  final List<TagChip> chips;

  @override
  Widget build(BuildContext context) => _Section(
    children: [
      AddRow(
        title: title,
        addText: addText,
        addLabel: addLabel,
        onAdd: onAdd,
        addKey: addKey,
      ),
      if (chips.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: _bottomGap),
          child: Wrap(
            spacing: DoableMetrics.space2,
            runSpacing: DoableMetrics.space2,
            children: chips,
          ),
        ),
    ],
  );
}

/// Колонка, которая отдаёт касания детям и за своими границами: область
/// «Добавить» шапки выходит за край содержимого.
final class _Section extends Flex {
  const _Section({required super.children})
    : super(
        direction: Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      );

  @override
  RenderFlex createRenderObject(BuildContext context) => _RenderSection(
    direction: direction,
    mainAxisSize: mainAxisSize,
    crossAxisAlignment: crossAxisAlignment,
    textDirection: getEffectiveTextDirection(context),
  );
}

final class _RenderSection extends RenderFlex {
  _RenderSection({
    required super.direction,
    required super.mainAxisSize,
    required super.crossAxisAlignment,
    required super.textDirection,
  });

  // Каждый ребёнок сам ограничивает свою область касаний.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
