import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Заголовок сворачиваемой секции списка: название, счётчик и шеврон.
///
/// Весь заголовок — одна кнопка высотой `tap-min`, которая вызывает
/// [onToggle]. Диктор читает название и счётчик одним заголовком с
/// состоянием раскрытости. Шеврон смотрит вверх у раскрытой секции и вниз
/// у свёрнутой. Счётчик показывает 0 у секции без строк, а шеврон выходит
/// на 2 в поле у края. Отступы между заголовками и строками задаёт список.
final class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    required this.count,
    required this.onToggle,
    this.open = true,
    super.key,
  }) : assert(count >= 0);

  final String title;

  /// Число строк секции.
  final int count;

  /// Строки секции показаны.
  final bool open;

  final VoidCallback onToggle;

  static const double _chevronSize = 18;
  static const double _chevronOverhang = 2;
  static const double _chipSize = 24;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    // Название и счётчик сливаются в одно имя кнопки-заголовка:
    // https://api.flutter.dev/flutter/widgets/MergeSemantics-class.html
    return MergeSemantics(
      child: Semantics(
        header: true,
        button: true,
        enabled: true,
        expanded: open,
        // Отклик нажатия рисуется на плоскости заголовка, а не под списком:
        // https://api.flutter.dev/flutter/material/InkWell-class.html
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DoableMetrics.tapMin,
              ),
              child: Row(
                spacing: DoableMetrics.space2,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: DoableType.section.copyWith(color: colors.ink),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.fill,
                      borderRadius: BorderRadius.circular(_chipSize / 2),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: _chipSize,
                        minHeight: _chipSize,
                      ),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Text(
                            '$count',
                            style: DoableType.label.copyWith(
                              color: colors.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Шеврон занимает место на 2 меньше и рисуется за краем:
                  // https://api.flutter.dev/flutter/widgets/OverflowBox-class.html
                  SizedBox(
                    width: _chevronSize - _chevronOverhang,
                    height: _chevronSize,
                    child: OverflowBox(
                      maxWidth: _chevronSize,
                      maxHeight: _chevronSize,
                      alignment: AlignmentDirectional.centerStart,
                      child: RotatedBox(
                        quarterTurns: open ? 2 : 0,
                        child: DoableIcon(
                          DoableIconData.chevronDown,
                          size: _chevronSize,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
